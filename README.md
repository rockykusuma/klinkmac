# KlinkMac

Ultra-low-latency mechanical keyboard sound emulation for macOS.

## What it is

KlinkMac makes any Mac keyboard sound like a premium mechanical keyboard. Each keystroke triggers a pre-recorded sample from the active pack. The goal is imperceptible latency (sub-10ms end-to-end) with rock-solid consistency — better than any existing option.

**Why it's different:**
- Existing options: Mechvibes (Electron, ~30–50ms), Klack (~15ms, $4.99, closed-source)
- KlinkMac: native Swift, lock-free audio pipeline, sub-10ms target

## Requirements

- macOS 13.0+ (Apple Silicon or Intel)
- Xcode 16+
- Accessibility permission (required to capture system-wide keystrokes)

## Running

```
open KlinkMac/KlinkMac.xcodeproj
```

Select the **KlinkMac** scheme and hit ⌘R. Grant Accessibility permission when prompted. The app lives in the menu bar — no Dock icon.

## Architecture

- **Audio thread:** `AVAudioSourceNode` render callback — zero allocations, zero locks, zero ARC
- **Event pipeline:** CGEventTap → SPSC ring buffer (`EventQueue`) → audio thread
- **Pack hot-swap:** atomic pointer swap (`AtomicBankPointer`) with deferred release
- **Voice pool:** 24-voice `VoiceAllocator`, pre-allocated at launch
- **UI:** SwiftUI `MenuBarExtra` + `Settings` scene, AppKit interop for onboarding window

See `ARCHITECTURE.md` for full threading model and design decisions.

## Sound packs

Bundled packs: **Cherry MX Blue**, **Cherry MX Brown**, **Topre Silent**

User packs install to `~/Library/Application Support/com.klinkmac.KlinkMac/Packs/`. Drag a `.klinkpack` file onto the Packs tab in Preferences to install.

Pack format spec: `specs/sound-pack-format.md`

## Directory structure

```
klinkmac/
├── KlinkMac/                          Xcode project
│   ├── KlinkMac.xcodeproj
│   ├── KlinkMac.entitlements
│   └── KlinkMac/                      Source target
│       ├── App/                       AppState, AppDelegate
│       ├── Engine/                    Audio engine (no UI imports)
│       │   ├── AudioEngine.swift
│       │   ├── AtomicBankPointer.swift
│       │   ├── EventQueue.swift
│       │   ├── KeyEventMonitor.swift
│       │   ├── SampleBank.swift
│       │   └── VoiceAllocator.swift
│       ├── Packs/                     Pack loading and format model
│       ├── Permissions/               Accessibility permission flow
│       ├── Settings/                  UserDefaults-backed settings store
│       ├── UI/                        SwiftUI views
│       └── Resources/Packs/           Bundled sound packs
├── KlinkMacTests/                     Unit tests (EventQueue, etc.)
├── Tools/                             Release script, latency tools
├── phases/                            Phase planning docs
├── specs/                             Sound pack format spec
├── ARCHITECTURE.md
├── ROADMAP.md
└── CLAUDE.md                          Claude Code project context
```

## Status

| Phase | Goal | Status |
|-------|------|--------|
| 0 — Foundation | End-to-end pipeline, menu bar toggle | ✅ Done |
| 1 — Feel | Multiple sounds, key-up, pitch variation, 3 packs | ✅ Done |
| 2 — Latency | Sub-10ms measured, 150 WPM stress-tested | ✅ Done |
| 3 — Usable | Pack format, preferences UI, onboarding, settings persistence | ✅ Done |
| 4A — Meeting mute | Auto-silence during Zoom/Meet/Teams calls | ✅ Done |
| 4B — App-aware profiles | Different pack per foreground app | ✅ Done |
| 4C — Output routing | Route sounds to specific audio device | ✅ Done |
| 4D — Record your own pack | Mic recording → instant custom pack | ✅ Done |

## Contributing

1. Fork and clone the repo.
2. Open `KlinkMac/KlinkMac.xcodeproj` in Xcode.
3. In **Signing & Capabilities**, set your own Apple Developer team (required to run on device).
4. Hit ⌘R. Grant Accessibility permission when prompted.

Issues and PRs are welcome. See `ARCHITECTURE.md` before touching the audio engine — the render callback has strict no-allocation / no-lock rules.

## No sandbox

KlinkMac runs outside the macOS App Sandbox. `CGEventTap` with Accessibility inside the sandbox is possible but finicky; direct DMG distribution sidesteps it entirely. This is documented in `phases/phase-3-usable.md`.
