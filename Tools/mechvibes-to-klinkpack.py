#!/usr/bin/env python3
"""Convert Mechvibes pack(s) to KlinkMac .klinkpack format.

Handles:
  - MP3/OGG → WAV conversion via macOS afconvert (no dependencies)
  - null defines (silently skipped)
  - pitch-based packs (highpitch/midpitch/lowpitch/spacebar)
  - per-letter packs (nk-cream style)
  - numbered WAV packs (ClassicKeyboard style)
  - batch mode: convert every pack in a parent directory

Usage:
    # Single pack → outputs <id>/ dir + <id>.klinkpack beside source
    python3 Tools/mechvibes-to-klinkpack.py soundpacks/mx-blue-pbt

    # Batch: convert all packs in a folder
    python3 Tools/mechvibes-to-klinkpack.py soundpacks/ --batch

    # Custom output dir
    python3 Tools/mechvibes-to-klinkpack.py soundpacks/nk-cream --out converted-packs/
"""

import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from collections import Counter
from pathlib import Path

# ──────────────────────────────────────────────
# PC XT scan code → macOS Carbon virtual keycode
# ──────────────────────────────────────────────
SCANCODE_TO_MAC_VK: dict[int, int] = {
    1:  53,  # Escape
    2:  18,  # 1
    3:  19,  # 2
    4:  20,  # 3
    5:  21,  # 4
    6:  23,  # 5
    7:  22,  # 6
    8:  26,  # 7
    9:  28,  # 8
    10: 25,  # 9
    11: 29,  # 0
    12: 27,  # - (minus)
    13: 24,  # = (equal)
    14: 51,  # Backspace / Delete
    15: 48,  # Tab
    16: 12,  # Q
    17: 13,  # W
    18: 14,  # E
    19: 15,  # R
    20: 17,  # T
    21: 16,  # Y
    22: 32,  # U
    23: 34,  # I
    24: 31,  # O
    25: 35,  # P
    26: 33,  # [
    27: 30,  # ]
    28: 36,  # Return / Enter
    29: 59,  # Left Control
    30: 0,   # A
    31: 1,   # S
    32: 2,   # D
    33: 3,   # F
    34: 5,   # G
    35: 4,   # H
    36: 38,  # J
    37: 40,  # K
    38: 37,  # L
    39: 41,  # ;
    40: 39,  # '
    41: 50,  # ` (grave)
    42: 56,  # Left Shift
    43: 42,  # \ (backslash)
    44: 6,   # Z
    45: 7,   # X
    46: 8,   # C
    47: 9,   # V
    48: 11,  # B
    49: 45,  # N
    50: 46,  # M
    51: 43,  # , (comma)
    52: 47,  # . (period)
    53: 44,  # / (slash)
    54: 60,  # Right Shift
    55: 67,  # Numpad *
    56: 58,  # Left Alt / Option
    57: 49,  # Space
    58: 57,  # Caps Lock
    59: 122, # F1
    60: 120, # F2
    61: 99,  # F3
    62: 118, # F4
    63: 96,  # F5
    64: 97,  # F6
    65: 98,  # F7
    66: 100, # F8
    67: 101, # F9
    68: 109, # F10
    69: 71,  # Num Lock / Keypad Clear
    71: 89,  # Numpad 7
    72: 91,  # Numpad 8
    73: 92,  # Numpad 9
    74: 78,  # Numpad -
    75: 86,  # Numpad 4
    76: 87,  # Numpad 5
    77: 88,  # Numpad 6
    78: 69,  # Numpad +
    79: 83,  # Numpad 1
    80: 84,  # Numpad 2
    81: 85,  # Numpad 3
    82: 82,  # Numpad 0
    83: 65,  # Numpad .
    87: 103, # F11
    88: 111, # F12
    # Extended iohook codes (Windows E0 prefix)
    3597: 59,  # Right Control
    3612: 58,  # Right Alt / Option
    3637: 75,  # Numpad /
    3640: 61,  # Right Alt (AltGr)
    3653: 117, # Forward Delete
    3655: 119, # End
    3657: 115, # Home
    3663: 123, # Left Arrow
    3665: 124, # Right Arrow
    3666: 126, # Up Arrow
    3667: 125, # Down Arrow
    3675: 54,  # Right Command
    3676: 55,  # Left Command
    57416: 126, # Up Arrow
    57419: 123, # Left Arrow
    57421: 124, # Right Arrow
    57424: 125, # Down Arrow
}

# Modifier VKs — skip as overrides (not useful as individual sounds)
SKIP_MAC_VK = {56, 60, 59, 62, 58, 61, 55, 54, 57}


def convert_to_wav(src: Path, dst: Path) -> bool:
    """Convert any audio file to 16-bit PCM WAV using afconvert. Returns True on success."""
    if src.suffix.lower() == ".wav":
        shutil.copy2(src, dst)
        return True
    result = subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16", str(src), str(dst)],
        capture_output=True,
    )
    if result.returncode != 0:
        print(f"  Warning: afconvert failed for {src.name}: {result.stderr.decode().strip()}")
        return False
    return True


def pick_default(vk_to_wav: dict[int, str]) -> str:
    """Most-common WAV across regular alpha/digit keys → safest default."""
    alpha_vks = set(range(0, 50)) - SKIP_MAC_VK
    alpha_wavs = [w for vk, w in vk_to_wav.items() if vk in alpha_vks]
    if not alpha_wavs:
        return next(iter(vk_to_wav.values()))
    return Counter(alpha_wavs).most_common(1)[0][0]


def safe_wav_name(original: str) -> str:
    """Normalize filename to be safe + always .wav extension."""
    stem = Path(original).stem
    safe = re.sub(r"[^\w\-]", "_", stem)
    return f"{safe}.wav"


def convert_pack(src_dir: Path, out_dir: Path) -> Path | None:
    config_path = src_dir / "config.json"
    if not config_path.exists():
        print(f"Skipping {src_dir.name}: no config.json")
        return None

    config = json.loads(config_path.read_text(encoding="utf-8"))
    defines: dict[str, str | None] = config.get("defines", {})

    # Build VK → original-filename mapping (skip nulls and unknown scancodes)
    vk_to_orig: dict[int, str] = {}
    for scan_str, wav_file in defines.items():
        if not wav_file:
            continue
        scan = int(scan_str)
        mac_vk = SCANCODE_TO_MAC_VK.get(scan)
        if mac_vk is None or mac_vk in SKIP_MAC_VK:
            continue
        vk_to_orig[mac_vk] = wav_file

    if not vk_to_orig:
        print(f"Skipping {src_dir.name}: no usable keycodes after mapping")
        return None

    default_orig = pick_default(vk_to_orig)

    # Build pack ID + name
    raw_id = config.get("id", src_dir.name)
    # Prefer folder name over auto-generated IDs like "custom-sound-pack-16212..."
    if re.match(r"custom-sound-pack-\d+", raw_id):
        raw_id = src_dir.name
    pack_id = re.sub(r"[^a-z0-9.\-]", "-", raw_id.lower()).strip("-")
    pack_name = config.get("name", src_dir.name)

    pack_dir = out_dir / pack_id
    pack_dir.mkdir(parents=True, exist_ok=True)

    # Convert + copy all unique audio files needed
    orig_to_safe: dict[str, str] = {}
    needed = set(vk_to_orig.values())
    converted_count = 0
    for orig in needed:
        safe = safe_wav_name(orig)
        orig_to_safe[orig] = safe
        src_file = src_dir / orig
        dst_file = pack_dir / safe
        if not src_file.exists():
            print(f"  Warning: {orig} not found, skipping")
            continue
        if convert_to_wav(src_file, dst_file):
            converted_count += 1

    default_wav = orig_to_safe[default_orig]

    # Build keys map — only entries that differ from default
    keys: dict[str, dict] = {}
    for mac_vk, orig in sorted(vk_to_orig.items()):
        wav = orig_to_safe.get(orig)
        if wav and wav != default_wav:
            keys[str(mac_vk)] = {"down": wav}

    manifest = {
        "formatVersion": 1,
        "id": f"com.klinkmac.{pack_id}",
        "name": pack_name,
        "author": config.get("author", "Mechvibes Community"),
        "version": "1.0.0",
        "description": f"{pack_name} — converted from Mechvibes.",
        "defaults": {"down": default_wav},
        "keys": keys,
    }
    (pack_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # Zip → .klinkpack
    klinkpack_path = out_dir / f"{pack_id}.klinkpack"
    with zipfile.ZipFile(klinkpack_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(pack_dir.iterdir()):
            zf.write(f, f.name)

    print(f"  ✓ {pack_name}  →  {klinkpack_path.name}  ({converted_count} WAVs, {len(keys)} key overrides)")
    return klinkpack_path


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    batch = "--batch" in args
    args = [a for a in args if not a.startswith("--")]

    src = Path(args[0]).resolve()
    out = Path(args[1]).resolve() if len(args) > 1 else src.parent / "converted-packs"

    out.mkdir(parents=True, exist_ok=True)

    if batch:
        if not src.is_dir():
            sys.exit(f"Error: {src} is not a directory")
        packs = [d for d in sorted(src.iterdir()) if d.is_dir() and (d / "config.json").exists()]
        print(f"Batch converting {len(packs)} packs → {out}\n")
        for pack_dir in packs:
            convert_pack(pack_dir, out)
    else:
        if not src.is_dir():
            sys.exit(f"Error: {src} is not a directory")
        convert_pack(src, out)

    print(f"\nDone. Output: {out}")


if __name__ == "__main__":
    main()
