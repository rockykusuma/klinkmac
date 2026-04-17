# Sound pack format specification (v1)

This is the authoritative reference for the `.klinkpack` file format. Once Phase 3 ships, this format is a stable contract and breaking changes must go through a version bump.

## Overview

A KlinkMac sound pack is a directory containing:
- A `manifest.json` describing the pack
- A set of `.wav` audio files for individual key sounds

For distribution, the directory is zipped and renamed to `.klinkpack`. The app unzips `.klinkpack` files on install.

## Directory layout

```
my-pack/
├── manifest.json
├── default-down.wav
├── default-up.wav
├── space-down.wav
├── space-up.wav
├── enter-down.wav
├── enter-up.wav
├── backspace-down.wav
├── backspace-up.wav
└── ...
```

File naming is convention, not a hard requirement — what matters is what the manifest references.

## Manifest schema

`manifest.json` is UTF-8 encoded JSON.

```json
{
  "formatVersion": 1,
  "id": "com.yourname.cherry-blue",
  "name": "Cherry MX Blue",
  "author": "Your Name",
  "version": "1.0.0",
  "description": "Clicky, high-pitched, sharp — the classic Cherry Blue sound.",
  "website": "https://example.com/packs",
  "license": "CC-BY-4.0",
  "defaults": {
    "down": "default-down.wav",
    "up": "default-up.wav"
  },
  "keys": {
    "49": {
      "down": "space-down.wav",
      "up": "space-up.wav"
    },
    "36": {
      "down": "enter-down.wav",
      "up": "enter-up.wav"
    },
    "51": {
      "down": "backspace-down.wav"
    }
  }
}
```

### Field reference

| Field | Type | Required | Notes |
|---|---|---|---|
| `formatVersion` | integer | yes | Always `1` for this spec |
| `id` | string | yes | Reverse-DNS style unique identifier. Used for internal pack management. Lowercase, no spaces |
| `name` | string | yes | Human-readable display name (≤60 chars) |
| `author` | string | yes | Pack creator name |
| `version` | string | yes | Semver string (e.g., `"1.0.0"`) |
| `description` | string | no | Short description (≤200 chars). Shown in the packs UI |
| `website` | string | no | URL for more info or purchase |
| `license` | string | no | SPDX license identifier (e.g., `"CC0-1.0"`, `"CC-BY-4.0"`). Affects redistribution rights |
| `defaults` | object | yes | Fallback sounds for keys not mapped in `keys`. At minimum `down` is required |
| `keys` | object | no | Map from macOS virtual keycode (as string) to per-key overrides |

### Per-key mapping

Each entry in `keys` (and the `defaults` object) has this shape:

| Field | Type | Required | Notes |
|---|---|---|---|
| `down` | string | yes (in defaults) | Relative path to the key-down WAV file |
| `up` | string | no | Relative path to the key-up WAV file. If absent, no sound plays on release |
| `gain` | number | no | Per-key gain multiplier (default `1.0`). Useful for quieting overly-loud space bars |

Values are paths relative to the pack directory root. No `..` allowed.

## Audio file requirements

- **Format:** WAV (RIFF/WAVE) — this is the only supported format in v1
- **Bit depth:** 16-bit or 24-bit PCM (32-bit float accepted but not required)
- **Sample rate:** any; the loader converts to the device's native rate at load time
- **Channels:** 1 (mono) or 2 (stereo)
- **Duration:** should be between 20ms and 500ms per sample. Longer is rejected with a warning
- **File size:** individual files should be under 500KB. Pack total size should be under 20MB

## macOS virtual keycodes

The `keys` map uses decimal string keys corresponding to macOS virtual keycodes (from `Carbon/HIToolbox/Events.h`). Common ones:

| Key | Keycode |
|---|---|
| Space | 49 |
| Return/Enter | 36 |
| Delete/Backspace | 51 |
| Tab | 48 |
| Escape | 53 |
| Left arrow | 123 |
| Right arrow | 124 |
| A | 0 |
| S | 1 |
| D | 2 |

Full reference: search for "kVK_ANSI_A" etc. in Apple's documentation, or use the `Carbon` framework's constants directly.

## Validation rules

On pack install, the loader validates:

1. `manifest.json` exists and parses as valid JSON
2. `formatVersion` is `1`
3. All required fields are present
4. `id` matches `^[a-z0-9.-]+$` and is at most 128 characters
5. Every referenced WAV file exists and decodes without error
6. No file path in the manifest contains `..` or an absolute path
7. All audio files meet the format requirements above
8. Pack total uncompressed size is under 100MB

Validation failures produce a clear, actionable error shown to the user (e.g., "Pack 'Cherry Blue' is missing the file 'space-down.wav' referenced in its manifest").

## Versioning

- `formatVersion`: increment only when the format itself changes incompatibly (new required fields, renamed fields, etc.). KlinkMac commits to reading all past `formatVersion`s forever
- `version`: the pack author's own versioning. KlinkMac uses it only for display and update detection

## Backwards compatibility policy

- A pack with `formatVersion` greater than the app supports is rejected with a "please update KlinkMac" message
- A pack with a lower `formatVersion` must always load — older packs never break

## Example: minimal pack

```json
{
  "formatVersion": 1,
  "id": "com.example.minimal",
  "name": "Minimal",
  "author": "Example",
  "version": "1.0.0",
  "defaults": {
    "down": "click.wav"
  }
}
```

This pack plays `click.wav` on every key down, nothing on up. Perfectly valid.

## Example: stereo pack with per-key gain

```json
{
  "formatVersion": 1,
  "id": "com.example.stereo",
  "name": "Stereo Pack",
  "author": "Example",
  "version": "2.1.0",
  "description": "Recorded in stereo for immersive typing",
  "license": "CC-BY-4.0",
  "defaults": {
    "down": "default-down.wav",
    "up": "default-up.wav"
  },
  "keys": {
    "49": {
      "down": "space-down.wav",
      "up": "space-up.wav",
      "gain": 0.75
    }
  }
}
```

## Distribution

Packs distribute as `.klinkpack` files, which are standard ZIP archives with the extension changed. Creating one:

```bash
cd my-pack/
zip -r ../my-pack.klinkpack ./*
```

Users double-click `.klinkpack` files to install (KlinkMac registers itself as the default handler for the extension on macOS).

## Future format versions (informative, not spec)

Possible additions for `formatVersion: 2`:
- Multiple sample variants per key (random selection for more natural variation)
- Velocity-sensitive samples (soft / hard press)
- Embedded thumbnail image for pack UI
- Digital signature for verified packs
