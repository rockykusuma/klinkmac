# Phase 0 — Foundation

## Goal

Prove the entire pipeline works end-to-end. Ugly UI, single hardcoded sound, no latency optimization. The purpose is to eliminate integration risk before building anything fancy — at the end of this phase, every boundary (CGEventTap, CoreAudio, permissions, menu bar) is known to function.

## Ship criteria

- Run app → see a menu bar icon
- On first launch, show a clear explanation of why Accessibility permission is needed
- Once permission is granted, typing in any app (Safari, Xcode, TextEdit, Terminal) produces a sound
- Menu bar dropdown has a working on/off toggle
- Quit from the menu bar terminates cleanly

## Out of scope (save for later phases)

- Multiple sounds per key — all keys play the same sound in Phase 0
- Voice polyphony — overlapping keystrokes may clip each other; fine for now
- Custom AVAudioSourceNode render callback — use `AVAudioPlayerNode` for ease
- Sound pack format — bundle one WAV as a resource
- Settings persistence — the app forgets everything on quit
- Launch at login
- Distinct key-down / key-up sounds

## Deliverables

### 1. Xcode project setup

- New macOS app project, Swift, SwiftUI lifecycle
- Deployment target: **macOS 13.0**
- **Disable App Sandbox** for now — CGEventTap + Accessibility is easier without it. Phase 3 will revisit this
- **Enable Hardened Runtime** — required for later notarization
- Add to `Info.plist`:
  - `NSAppleEventsUsageDescription`: "KlinkMac needs Apple Events for the Accessibility permission flow."
  - A key explaining Accessibility usage in the onboarding UI text
- Set `LSUIElement` = `YES` in `Info.plist` so it's a menu-bar-only app (no Dock icon)
- Add the `swift-atomics` Swift package (we'll use it in Phase 1 — add it now so we don't churn the project file)

### 2. Menu bar app scaffold

- Use SwiftUI `MenuBarExtra` with `.menu` style
- Status item icon: SF Symbol `keyboard.fill`
- Menu contents:
  - A section header showing current state: "KlinkMac — Active" or "KlinkMac — Paused"
  - "Pause" / "Resume" toggle (Space shortcut optional)
  - Divider
  - "Grant Accessibility Permission…" — only visible when not granted
  - Divider
  - "Quit KlinkMac" with Cmd+Q shortcut
- No main window
- App class: `@main struct KlinkMacApp: App`

### 3. Accessibility permission flow

- File: `Permissions/AccessibilityManager.swift`
- Responsibilities:
  - Check current permission state using `AXIsProcessTrusted()` (read-only check) and `AXIsProcessTrustedWithOptions(...)` (with prompt option)
  - Publish the state via `@Published var isTrusted: Bool` for SwiftUI bindings
  - Poll permission state every 1 second while a permission window is open (`Timer.publish`), since macOS doesn't send a notification when permission changes
  - Method `openSystemSettings()` that opens the Accessibility settings pane: `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
- File: `UI/PermissionWindow.swift`
- Explanatory text:
  > "KlinkMac plays mechanical keyboard sounds as you type. To do that, it needs Accessibility permission to detect keystrokes system-wide. KlinkMac only sees which key was pressed — never what you type. Nothing ever leaves your Mac."
- Two buttons: "Open System Settings" and "I've Granted It"
- Automatically dismisses when permission is detected as granted

### 4. CGEventTap wrapper

File: `Engine/KeyEventMonitor.swift`.

```swift
// Public API surface — Claude Code can adjust internal implementation
public struct KeyEvent {
    public let keycode: UInt16
    public let isDown: Bool
    public let timestamp: UInt64   // mach_absolute_time
}

public final class KeyEventMonitor {
    public typealias Handler = (KeyEvent) -> Void
    public var onEvent: Handler?
    public init()
    public func start() throws
    public func stop()
}
```

Implementation notes:
- Create the tap with `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(...keydown|keyup...), callback: ..., userInfo: ...)`
- Create a `CFRunLoopSource` and add it to a dedicated pthread's run loop. Do NOT add it to `CFRunLoop.main` — we want the tap on its own thread from day one
- In the tap callback, extract keycode via `event.getIntegerValueField(.keyboardEventKeycode)`, type from `CGEventType`, timestamp from `event.timestamp`
- Build `KeyEvent`, call `onEvent?(event)` synchronously on the tap thread
- **Document the threading contract** in a comment: "The handler is called on the event tap thread. Do not block."

### 5. Simple audio playback (temporary)

File: `Engine/NaiveAudioPlayer.swift`. Name it `Naive` intentionally — we're replacing it in Phase 2.

```swift
public final class NaiveAudioPlayer {
    public init(resourceName: String, resourceExtension: String) throws
    public func play()
    public func stop()
}
```

Implementation:
- Load the WAV into an `AVAudioPCMBuffer` at init
- Build an `AVAudioEngine` with a single `AVAudioPlayerNode` connected to main mixer
- Start the engine
- `play()` schedules the buffer on the player node with `.interrupts` policy (so rapid presses cut off the previous sound — we'll do real polyphony in Phase 1)

Source one default click sound for this phase. Any short (~50–150ms) mechanical keyboard sample works. Place it at `Resources/Packs/default/keydown.wav`.

### 6. Wiring

In `KlinkMacApp.swift` or a wiring class:

- Instantiate `AccessibilityManager`, `KeyEventMonitor`, and `NaiveAudioPlayer` at app launch
- When `isTrusted` becomes true, call `monitor.start()`
- `monitor.onEvent = { event in if event.isDown { DispatchQueue.main.async { player.play() } } }`
  - Yes, this main-queue hop adds latency. Phase 0 doesn't care. Phase 2 removes it.
- Respect the pause/resume toggle — gate the `player.play()` call on a `@Published var isEnabled`

## File map

```
KlinkMac/
├── KlinkMacApp.swift
├── App/
│   └── AppState.swift                    (observable wiring: paused, isTrusted, etc.)
├── Engine/
│   ├── KeyEventMonitor.swift
│   └── NaiveAudioPlayer.swift            (deleted in Phase 2)
├── Permissions/
│   └── AccessibilityManager.swift
├── UI/
│   ├── MenuBarView.swift
│   └── PermissionWindow.swift
└── Resources/
    └── Packs/default/keydown.wav
```

## Acceptance checklist

- [ ] Project builds with no warnings in Release config
- [ ] App launches to a menu bar icon, no Dock icon, no main window
- [ ] First launch shows permission explainer window
- [ ] Clicking "Open System Settings" opens the correct Accessibility pane
- [ ] Granting permission is detected within ~1 second and the explainer dismisses
- [ ] After permission granted, pressing any key in Safari/Xcode/TextEdit produces audible output
- [ ] Menu bar Pause toggle silences the sound; Resume restarts it
- [ ] Revoking permission at runtime (from System Settings) doesn't crash the app
- [ ] Quit from menu bar terminates the process cleanly (no lingering tap)

## Known issues to ignore until later phases

- End-to-end latency will be ~30–50ms due to `AVAudioPlayerNode` and main-queue dispatch. Phase 2 fixes.
- All keys sound identical. Phase 1 fixes.
- No settings persistence. Phase 3 fixes.
- No sandbox. Phase 3 reconsiders.
