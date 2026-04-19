# KlinkMac

Ultra-low-latency mechanical keyboard sound emulation for macOS.

## What it is

KlinkMac makes any Mac keyboard sound like a premium mechanical keyboard. Each keystroke triggers a pre-recorded sample from the active sound pack. The goal is imperceptible latency (sub-10ms end-to-end) with rock-solid consistency.

**Why it's different:**
- Mechvibes: Electron, ~30–50ms latency
- Klack: native, ~15ms, $4.99, closed-source
- KlinkMac: native Swift, lock-free audio pipeline, sub-10ms, open-source

## Features

- **15 bundled sound packs** — Cherry MX Blue/Brown/Red/Black (ABS + PBT variants), NK Cream, Topre, and more
- **Custom packs** — drag a `.klinkpack` file to install, or record your own from mic
- **Meeting mute** — auto-silences during Zoom, Meet, Teams, Discord, FaceTime calls
- **App-aware profiles** — different pack per foreground app (e.g. silent in Slack, clicky in Xcode)
- **Output routing** — route sounds to any audio device (headphones only, virtual loopback, etc.)
- **Export packs** — export any user-recorded pack as a shareable `.klinkpack` file
- **Typing visualizer overlay** — floating click-through keyboard that lights up as you type (streamer / tutorial use case)
- **Launch at login** — runs silently in the menu bar

## Requirements

- macOS 13.0+ (Apple Silicon or Intel)
- Xcode 16+ (to build from source)
- Accessibility permission (required to capture system-wide keystrokes)

## Building

```bash
open KlinkMac/KlinkMac.xcodeproj
```

1. In **Signing & Capabilities**, set your Apple Developer team
2. Select the **KlinkMac** scheme and hit ⌘R
3. Grant Accessibility permission when prompted

The app lives in the menu bar — no Dock icon.

## Sound packs

15 packs bundled. User packs install to:

```
~/Library/Application Support/com.klinkmac.KlinkMac/Packs/
```

**Install:** drag a `.klinkpack` file onto the Packs tab in Preferences.  
**Record:** Preferences → Packs → Record Pack — type naturally, pack is created from mic recording.  
**Export:** hover any user pack in Preferences → Packs → click the ↑ icon.  
**Format spec:** [`SOUND-PACK-FORMAT.md`](SOUND-PACK-FORMAT.md)

## Architecture

- **Audio thread:** `AVAudioSourceNode` render callback — zero allocations, zero locks, zero ARC
- **Event pipeline:** CGEventTap → SPSC ring buffer (`EventQueue`) → audio thread
- **Pack hot-swap:** atomic pointer swap (`AtomicBankPointer`) with ~5s deferred release
- **Voice pool:** 24-voice `VoiceAllocator`, pre-allocated at launch, with pitch randomization
- **Mute flag:** atomic bool checked at the top of every render callback
- **UI:** SwiftUI `MenuBarExtra` (.window style) + `Settings` scene

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full threading model, latency budget, and Phase 4 subsystem details.

## Directory structure

```
klinkmac/
├── KlinkMac/
│   ├── KlinkMac.xcodeproj
│   ├── KlinkMac.entitlements
│   └── KlinkMac/
│       ├── App/
│       │   ├── AppState.swift          central observable state
│       │   ├── AppDelegate.swift       NSApplication delegate
│       │   ├── AppProfile.swift        app-aware profile model
│       │   ├── MeetingMuteMonitor.swift detects active calls
│       │   └── ProfileManager.swift    profile switching logic
│       ├── Engine/                     audio engine — no UI imports
│       │   ├── AudioEngine.swift
│       │   ├── AtomicBankPointer.swift
│       │   ├── EventQueue.swift        lock-free SPSC ring buffer
│       │   ├── KeyEventMonitor.swift   CGEventTap wrapper
│       │   ├── PackRecorder.swift      mic recording → pack
│       │   ├── SampleBank.swift
│       │   └── VoiceAllocator.swift
│       ├── Packs/
│       │   ├── PackFormat.swift        manifest model
│       │   └── PackLoader.swift        bundled + user pack loading
│       ├── Permissions/
│       │   └── AccessibilityManager.swift
│       ├── Settings/
│       │   └── SettingsStore.swift     UserDefaults-backed persistence
│       ├── UI/
│       │   ├── DesignSystem.swift           color tokens, shared components
│       │   ├── MenuBarView.swift            menu bar panel
│       │   ├── OnboardingView.swift         first-launch flow
│       │   ├── PreferencesView.swift        preferences window shell
│       │   ├── PreferencesPackViews.swift   pack grid, export, drop zone
│       │   ├── PreferencesProfileViews.swift app profile rules UI
│       │   ├── PreferencesOverlayView.swift visualizer overlay settings
│       │   ├── KeyboardLayoutView.swift     on-screen keyboard for recording
│       │   ├── RecordPackView.swift         record-your-own-pack UI
│       │   ├── VisualizerView.swift         floating keyboard visualizer
│       │   └── VisualizerWindow.swift       borderless click-through NSWindow
│       └── Resources/Packs/            15 bundled sound packs
├── KlinkMacTests/                      unit tests
├── release.sh                          sign + notarize + DMG script
├── ARCHITECTURE.md
├── SOUND-PACK-FORMAT.md
└── LICENSE
```

## Status

| Phase | Goal | Status |
|-------|------|--------|
| 0 — Foundation | End-to-end pipeline, menu bar toggle | ✅ |
| 1 — Feel | Multiple sounds, key-up, pitch variation, 3 packs | ✅ |
| 2 — Latency | Sub-10ms measured, 150 WPM stress-tested | ✅ |
| 3 — Usable | Pack format, preferences UI, onboarding, settings persistence | ✅ |
| 4A — Meeting mute | Auto-silence during calls | ✅ |
| 4B — App-aware profiles | Per-app pack switching | ✅ |
| 4C — Output routing | Route to specific audio device | ✅ |
| 4D — Record your own pack | Mic recording → instant custom pack | ✅ |
| 4E — Typing visualizer overlay | Floating keyboard that lights up as you type | ✅ |

## Contributing

1. Fork and clone the repo
2. Open `KlinkMac/KlinkMac.xcodeproj` in Xcode
3. Set your Apple Developer team in **Signing & Capabilities**
4. Hit ⌘R — grant Accessibility permission when prompted

Before touching the audio engine, read `ARCHITECTURE.md`. The render callback has strict no-allocation / no-lock rules — violations cause audible dropouts.

Issues and PRs welcome.

## No sandbox

KlinkMac runs outside the macOS App Sandbox. `CGEventTap` requires Accessibility permission and works more reliably outside the sandbox for direct DMG distribution.

## License

MIT — see [`LICENSE`](LICENSE).
