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
     ┌────────────────┐   ┌────────────────────┐   ┌──────────────┐
     │  Event Tap     │   │  Audio Render      │   │  Main / UI   │
     │  thread        │──▶│  thread (RT)       │◀──│  thread      │
     │  (CFRunLoop)   │   │  (CoreAudio)       │   │  (AppKit)    │
     ├────────────────┤   ├────────────────────┤   ├──────────────┤
     │  CGEventTap    │   │  Voice allocator   │   │  Menu bar UI │
     │  Enqueue event │   │  Sample mixer      │   │  Pack loader │
     └────────────────┘   └────────────────────┘   └──────────────┘
                                   │
                                   ▼
                             Hardware output

     Channels between threads:
     ① Event Tap → Audio Render: lock-free SPSC ring buffer
     ② Main → Audio Render:       atomic pointer swap of SampleBank
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
  2. Drain the SPSC event queue
  3. For each event: look up the sample, allocate a voice, kick off playback
  4. Advance all active voices, accumulate their samples into the output buffer
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
- Fill rate analysis: at 150 WPM we produce ~12 key-down events/sec. 256 slots = 20+ seconds of headroom — overflow never happens in practice
- Drop policy: if full, the producer silently discards the event (never blocks)

### ② Atomic SampleBank swap (Main → Audio Render)

- `Atomic<UnsafeRawPointer>` global pointing at the current immutable `SampleBank`
- Main thread: dispatch pack load to background thread → decoded SampleBank is constructed → atomic store of new pointer
- Audio thread: atomic load at the top of every render callback
- The previously active bank is kept alive in a deferred-release queue for ~5 seconds to let in-flight voices finish cleanly; then it's released

## Voice allocator

- Fixed pool of 24 voices, pre-allocated at engine start
- Each voice: `{ samplePtr, frameCount, position, gainL, gainR, pitchRatio, active }`
- Allocation: linear scan for an inactive voice. If all active, steal the one with the smallest `frameCount - position` (nearly done anyway — theft is imperceptible)
- Per-voice pitch randomization (±2–3% on `pitchRatio`) prevents the "same sound on a loop" feel
- Voice render loop advances `position` by `pitchRatio` per output frame, using linear interpolation between sample frames

## Sample format

- All samples pre-decoded during pack load to match the output device's native format
- Typical: 48kHz, float32, mono or stereo (non-interleaved)
- Conversion lives on the background thread during pack load. Never in the render callback
- Stored as raw PCM buffers owned by the SampleBank. Freed when the bank is released

## Accessibility permission

CGEventTap requires user-granted Accessibility access in System Settings → Privacy & Security → Accessibility.

- First-launch flow must clearly explain why (we capture keycodes, not keystroke content)
- Handle runtime revocation gracefully — don't crash, re-prompt
- Provide a "Re-request Permission" affordance in settings

## Latency budget

| Stage | Expected time | Notes |
|---|---|---|
| Physical press → CGEventTap fires | ~500 µs | macOS kernel + tap overhead |
| Tap callback → enqueue | ~80 µs | single atomic store |
| Wait for next audio render callback | 0–3 ms | depends on buffer size (128 frames @ 48kHz = 2.67ms) |
| Render processing for ~20 active voices | <500 µs | tight loop, no allocation |
| CoreAudio → DAC → physical output | ~2–3 ms | hardware-fixed |
| **Total end-to-end** | **~6 ms** | well below ~10ms perception threshold |

## Build-time / runtime invariants

- `SampleBank` is immutable after construction
- `EventQueue` capacity is fixed at compile time (power of 2)
- `VoiceAllocator` pool size is fixed at compile time
- Nothing on the audio thread holds a strong reference to a Swift class (pointers only)
- The render callback is re-entrant-safe (though in practice CoreAudio serializes calls)

## What's intentionally not in this architecture

- No plugin system (no third-party code loaded at runtime, reduces attack surface + complexity)
- No network calls during typing. Pack downloads are explicit user actions
- No telemetry or analytics on the audio path
- No MIDI (could be added later, but out of scope)
