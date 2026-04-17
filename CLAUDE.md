# Project context

This file is automatically loaded by Claude Code. It sets global context for the KlinkMac project. Read this before every task.

## Project

**KlinkMac** — ultra-low-latency mechanical keyboard sound app for macOS.

## Philosophy

- Native macOS only. No Electron, no web views, no cross-platform layers.
- **Latency is the product.** Every architectural decision must preserve it. When in doubt, choose the option that removes overhead.
- Ship small, iterate. Phase 0 should be usable within a day or two of work.
- No premature abstraction. Classes and protocols only when there's a real reason.

## Non-negotiables

1. **The audio thread is sacred.** Inside the audio render callback there must be no allocations, no locks, no ARC class ref-count operations, no `print`, no `DispatchQueue` dispatches, no Objective-C message sends to non-essential objects. Violations cause audible dropouts.
2. **Pre-allocate everything.** Audio buffers, voice pool, event queue — fixed size, set up at launch. Never `malloc` on a hot path.
3. **Lock-free inter-thread comms.** Use an SPSC ring buffer for events (producer = event tap thread, consumer = audio thread). Use atomic pointer swap for pack hot-swap. Never take a lock that the audio thread could touch.
4. **Measure with Instruments, don't guess.** Audio System Trace is the source of truth for latency. Time Profiler is the source of truth for CPU.

## Tech stack

- **Language:** Swift 5.9+
- **Deployment target:** macOS 13.0
- **UI:** SwiftUI (prefer `MenuBarExtra`), with AppKit interop where SwiftUI falls short
- **Audio:** AVAudioEngine + custom `AVAudioSourceNode` (render callback is the hot path from Phase 2 onward)
- **Input:** CGEventTap via `CGEvent.tapCreate` on a dedicated CFRunLoop thread
- **Concurrency primitives:** `swift-atomics` package from Apple for lock-free atomics
- **Logging:** `os.Logger` unified logging only. Never `print()`.

## Code style

- SwiftLint defaults, 120 columns
- Prefer structs + protocols to classes. Use classes when we need reference semantics or to hold unsafe pointers across an object lifetime
- `UnsafeMutablePointer`, `UnsafeBufferPointer`, and raw pointers are first-class citizens in the audio engine — do not avoid them for style reasons
- Single-sentence file-header comment describing the file's purpose
- Inside the audio render path: avoid Swift arrays, strings, dictionaries, optionals of classes, or any type that could allocate. Work with raw buffers.

## Directory layout (target)

```
KlinkMac/
├── KlinkMac.xcodeproj
├── KlinkMac/
│   ├── App/                   # App lifecycle, menu bar
│   ├── Engine/                # Audio engine (never import UI code from here)
│   │   ├── AudioEngine.swift
│   │   ├── VoiceAllocator.swift
│   │   ├── SampleBank.swift
│   │   ├── EventQueue.swift
│   │   └── KeyEventMonitor.swift
│   ├── Packs/                 # Sound pack loading and data model
│   ├── Permissions/           # Accessibility permission flow
│   ├── Settings/              # Preferences, persistence
│   ├── UI/                    # SwiftUI views
│   └── Resources/
│       └── Packs/             # Bundled sound packs
└── KlinkMacTests/             # Unit tests for engine
```

## Where to find the plan

- Architecture overview: `ARCHITECTURE.md`
- Current phase: check `ROADMAP.md` for the active phase
- Phase details: `phases/phase-N-*.md`
- Sound pack file format: `specs/sound-pack-format.md`

## Running the app

Open `KlinkMac.xcodeproj` in Xcode, select the KlinkMac scheme, hit ⌘R. Grant Accessibility permission when prompted.

## Before making changes, ask

1. Does this change touch the audio render path? If yes, re-read the no-allocation rule above.
2. Is this the right phase for this change? Don't pull Phase 2 work into Phase 0. If it belongs later, leave a `// TODO(phase-N):` comment and move on.
3. Are tests needed? Engine components (VoiceAllocator, EventQueue, SampleBank) need unit tests. UI can skip tests for now.
4. Does this require a new dependency? Prefer adding nothing. If needed, it must be a well-maintained Apple-authored or widely-used package.
