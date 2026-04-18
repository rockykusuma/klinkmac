# Architecture

## Goals

- End-to-end latency under 10ms, consistent (low jitter)
- Zero audio dropouts at 150+ WPM typing
- Hot-swap sound packs without clicks or glitches
- CPU footprint small enough that it's irrelevant on any Mac from the last 5 years

## System overview

```
                      Hardware keyboard
                             │
                             ▼
     ┌────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
     │  Event Tap     │   │  Audio Render      │   │  Main / UI thread    │
     │  thread        │──▶│  thread (RT)       │◀──│  (AppKit / SwiftUI)  │
     │  (CFRunLoop)   │   │  (CoreAudio)       │   │                      │
     ├────────────────┤   ├────────────────────┤   ├──────────────────────┤
     │  CGEventTap    │   │  Voice allocator   │   │  Menu bar UI         │
     │  Enqueue event │   │  Sample mixer      │   │  Preferences UI      │
     └────────────────┘   └────────────────────┘   │  Pack loader         │
                                   │                │  ProfileManager      │
                                   ▼                │  MeetingMuteMonitor  │
                             Hardware output        │  PackRecorder        │
                                                    └──────────────────────┘

     Channels between threads:
     ① Event Tap → Audio Render: lock-free SPSC ring buffer (EventQueue)
     ② Main → Audio Render:      atomic pointer swap of SampleBank
     ③ Main → Audio Render:      atomic bool for mute/enable flag
```

## Threads

### Event Tap thread

- Runs its own CFRunLoop on a dedicated pthread
- Single responsibility: capture system-wide keystrokes via CGEventTap
- Translates each `CGEvent` into `KeyEvent { keycode: UInt16, isDown: Bool, timestamp: UInt64 }`
- Pushes onto the SPSC event queue
- Never touches audio, UI, or the main thread

### Audio Render thread

- Owned by CoreAudio. We don't create it — we provide a render callback via `AVAudioSourceNode`
- Real-time scheduling priority. Any blocking causes audio dropouts
- Inside the callback on each invocation:
  1. Atomic load of the active `SampleBank` pointer
  2. Check atomic enabled flag — if false, drain queue and skip render
  3. Drain the SPSC event queue
  4. For each event: look up the sample, allocate a voice, kick off playback
  5. Advance all active voices, accumulate their samples into the output buffer
- **Forbidden on this thread:** `malloc`, locks, `DispatchQueue`, Swift class ARC, `print`, Obj-C message sends to non-audio objects

### Main / UI thread

- Menu bar, preferences UI, launch-at-login, permissions, pack management
- Spawns background threads for pack loading and audio decoding
- Communicates with the audio thread only via the two defined channels — never directly

## Communication channels

### ① SPSC event queue (Event Tap → Audio Render)

Lock-free single-producer single-consumer ring buffer.

- Power-of-two capacity (256 slots)
- Holds `KeyEvent` structs (16 bytes each)
- Producer (event tap) owns `writeIndex`: relaxed load of own index, acquire load of consumer index, store `KeyEvent`, release store of incremented `writeIndex`
- Consumer (audio render) owns `readIndex`: mirrors the pattern
- Fill rate: at 150 WPM ~12 key-down events/sec. 256 slots = 20+ seconds of headroom
- Drop policy: if full, the producer silently discards (never blocks)

### ② Atomic SampleBank swap (Main → Audio Render)

- `AtomicBankPointer` wraps an `UnsafeRawPointer` to the current immutable `SampleBank`
- Main thread: dispatch pack load to background → decoded `SampleBank` constructed → atomic store
- Audio thread: atomic load at the top of every render callback
- Previously active bank kept alive ~5 seconds via deferred release to let in-flight voices finish

### ③ Atomic enabled flag (Main → Audio Render)

- `ManagedAtomic<Bool>` in `AudioEngine`
- Set `false` by: user pause toggle, Meeting Mute trigger, app profile with no pack
- Audio render callback checks this with `.relaxed` ordering before rendering

## Voice allocator

- Fixed pool of 24 voices, pre-allocated at engine start
- Each voice: `{ samplePtr, frameCount, position, gainL, gainR, pitchRatio, active }`
- Allocation: linear scan for an inactive voice. If all active, steal the one closest to completion
- Per-voice pitch randomization (±2–3% on `pitchRatio`) prevents robotic loop feel
- Voice render loop advances `position` by `pitchRatio` per output frame using linear interpolation

## Sample format

- All samples pre-decoded during pack load to the output device's native format
- Typical: 48kHz, float32, mono (non-interleaved)
- Conversion on background thread during pack load — never in the render callback
- Stored as raw PCM buffers owned by `SampleBank`. Freed when the bank is released

## Sound pack format (.klinkpack)

A `.klinkpack` file is a ZIP archive containing:
- `manifest.json` — pack metadata and key→file mappings
- WAV files — one per key (down sound) + optional `_up` variants

`PackLoader` resolves the fallback chain: specific keycode → `defaults` entry → first available sample.

User packs install to `~/Library/Application Support/com.klinkmac.KlinkMac/Packs/`.

See `SOUND-PACK-FORMAT.md` for the full manifest spec.

## Phase 4 subsystems

### Meeting Mute (`MeetingMuteMonitor`)

- Polls `NSRunningApplication` every 3 seconds for known conferencing apps (Zoom, Teams, Meet, Discord, FaceTime, WebEx)
- When a monitored app becomes frontmost or is running with mic access, sets `AudioEngine.setEnabled(false)`
- Configurable per-app in Preferences → General. User can disable the feature entirely

### App-aware profiles (`ProfileManager`)

- `AppProfile`: `{ appBundleID: String, packID: String }`
- Observes `NSWorkspace.didActivateApplicationNotification`
- On app switch: looks up profile for the new frontmost app, calls `AppState.selectPack` if matched
- Falls back to the user's default pack if no rule matches
- Profiles persisted via `SettingsStore` (UserDefaults)

### Output device routing (`AudioEngine.setOutputDevice`)

- CoreAudio `kAudioOutputUnitProperty_CurrentDevice` set on the `AVAudioEngine` output node's audio unit
- Changing device stops the engine, detaches the source node, reinitializes, and restarts
- Device list discovered via `AudioObjectGetPropertyData(kAudioHardwarePropertyDevices)`, filtered to output-capable devices

### Record your own pack (`PackRecorder`)

- `AVAudioEngine` input tap captures mic audio into `accumSamples: [Float]`
- Two recording modes:
  - **Manual** — user clicks a key in the on-screen keyboard, types it, recording starts/stops on key-down/up
  - **Auto-record** — monitors all keystrokes; any non-modifier key triggers an automatic capture cycle
- Split at `timeIntervalSince(recordingStartTime) * sampleRate` to separate down/up sounds
- 100ms tail window after key-up captures the release transient
- 380ms max-duration cap prevents unbounded recordings
- `savePack(name:author:)` writes WAV files + `manifest.json` to `userPacksDirectory`, ready to use instantly

## Accessibility permission

CGEventTap requires user-granted Accessibility access in System Settings → Privacy & Security → Accessibility.

- First-launch flow explains why (keycodes only, not keystroke content)
- Runtime revocation handled gracefully — tap stops, app prompts to re-grant
- "Re-request Permission" affordance in Preferences → General

## Latency budget

| Stage | Expected time | Notes |
|---|---|---|
| Physical press → CGEventTap fires | ~500 µs | macOS kernel + tap overhead |
| Tap callback → enqueue | ~80 µs | single atomic store |
| Wait for next audio render callback | 0–3 ms | 128 frames @ 48kHz = 2.67ms |
| Render processing (~20 active voices) | <500 µs | tight loop, no allocation |
| CoreAudio → DAC → physical output | ~2–3 ms | hardware-fixed |
| **Total end-to-end** | **~6 ms** | well below ~10ms perception threshold |

## Build-time / runtime invariants

- `SampleBank` is immutable after construction
- `EventQueue` capacity fixed at compile time (power of 2)
- `VoiceAllocator` pool size fixed at compile time
- Nothing on the audio thread holds a strong Swift class reference (pointers only)
- The render callback is re-entrant-safe (CoreAudio serializes calls in practice)

## What's intentionally not in this architecture

- No plugin system (no third-party code at runtime)
- No network calls during typing — pack downloads are explicit user actions
- No telemetry or analytics on the audio path
- No MIDI (could be added, out of scope)
