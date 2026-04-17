# Phase 2 — Latency

## Goal

Drive end-to-end latency below 10ms with zero audible dropouts at sustained 150 WPM. This is where KlinkMac becomes measurably better than any competitor.

## Ship criteria

- Measured end-to-end latency under 10ms (mouth-to-ear test with a microphone, or Audio System Trace in Instruments)
- Audio System Trace shows render thread consistently hitting its deadline
- No dropped sounds at 150 WPM sustained typing for 60 seconds
- CPU usage on the audio thread stays under 5% on Apple Silicon at full polyphony
- No allocations, locks, `print`, or `DispatchQueue` calls on the audio render path (verified by reading the disassembly if needed)

## Out of scope

- New features — this phase is pure optimization and architectural hardening
- Pack loading changes — packs remain bundled, same as Phase 1
- UI changes — the pack picker, volume slider, and pause toggle all stay

## Deliverables

### 1. Lock-free SPSC event queue

Replace any main-queue dispatch or lock-based event passing with a proper SPSC ring buffer.

File: `Engine/EventQueue.swift`.

```swift
public final class EventQueue {
    public init(capacity: Int)                    // must be power of 2
    public func push(_ event: KeyEvent) -> Bool   // producer-only; returns false if full
    public func pop() -> KeyEvent?                // consumer-only
}
```

Implementation:
- Capacity rounded up to nearest power of 2; stored as mask (capacity - 1)
- Backing storage: `UnsafeMutablePointer<KeyEvent>` allocated once at init, freed in deinit
- `writeIndex` and `readIndex` as `ManagedAtomic<UInt32>` (from `swift-atomics`)
- Producer: relaxed load own index, acquire load consumer index, store slot, release store updated own index
- Consumer: mirrors producer pattern
- Overflow policy: silently drop. Log via `os.Logger` at `.debug` level (never at `.error` — overflows should never happen in practice)

Route the `KeyEventMonitor` callback to `queue.push(event)` directly, no main queue hop.

### 2. Custom AVAudioSourceNode render callback

Replace any `AVAudioPlayerNode`-based playback with a single `AVAudioSourceNode` owning the full render path.

File: `Engine/AudioEngine.swift` (rewrite).

```swift
public final class AudioEngine {
    public init(bankPointer: AtomicBankPointer, queue: EventQueue, allocator: VoiceAllocator)
    public func start() throws
    public func stop()
}
```

Inside the render callback (pseudocode):

```
func render(isSilence, timestamp, frameCount, audioBufferList):
    // 1. Load current bank atomically
    let bank = bankPointer.load(.acquiring)    // returns UnsafePointer<SampleBank>?
    if bank == nil { zeroFill(audioBufferList); return noErr }

    // 2. Drain event queue
    while let event = queue.pop() {
        dispatchEvent(event, bank: bank!)     // uses allocator.allocate
    }

    // 3. Render all active voices into output
    allocator.render(into: audioBufferList, frameCount: frameCount, channelCount: ...)

    return noErr
```

Constraints inside the callback:
- No Swift array/dictionary operations (lookups must be direct pointer dereferences)
- No `Optional` unwrapping on class types on the hot path — use `UnsafePointer<SampleBank>` directly
- No ARC operations — the `SampleBank` lifetime is managed by the retention mechanism described below, not by Swift's ref counting on this thread

### 3. Atomic SampleBank pointer with deferred release

File: `Engine/AtomicBankPointer.swift`.

- Global atomic pointer: `ManagedAtomic<UnsafeRawPointer?>`
- Main thread: when a new pack is loaded, construct `SampleBank`, `manuallyRetain()` it into a raw pointer, `atomicStore()` the pointer, add the old pointer to a deferred-release queue
- Deferred-release queue: a serial `DispatchQueue` that sleeps for 5 seconds and then `manuallyRelease()`s the old bank pointer. 5 seconds is more than enough for any in-flight voice to finish
- Audio thread: `atomicLoad(.acquiring)` at top of each render, cast back to `UnsafePointer<SampleBank>`, dereference as needed

### 4. Buffer size and format configuration

- Set the audio hardware buffer size to 128 frames via the `AudioUnit` underlying the engine:
  - `AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, ...)` after engine start
  - Or, if using the shared output device, set `kAudioDevicePropertyBufferFrameSize` on the device directly
- 128 frames at 48kHz = 2.67ms buffer latency
- Request a non-interleaved Float32 format matching the device's native sample rate
- In the pack loader, pre-convert all samples to this exact format at load time

### 5. Format pre-conversion in pack loader

Update `PackLoader` to query the current output device's sample rate before loading, then convert all samples to that rate once. Store conversions in a cache keyed by sample rate if switching output devices is a concern (not critical for Phase 2 — most users don't switch).

### 6. Remove all allocations from the hot path

Audit the render callback and every function it calls:
- No `[Float]`, `Array`, `Dictionary`, `String`
- No `Optional<SomeClass>` (which may involve retain/release)
- No `print`, `NSLog`, `os_log` at `.default` or higher (`.debug` is OK if it compiles out in Release)
- No `DispatchQueue.async`
- No Swift error `throw`/`catch` on the hot path

Verify by:
- Running in Instruments with the Allocations template and confirming no allocations during sustained typing
- Reading the generated Swift-to-LLVM-IR for the callback (`swiftc -emit-ir`) and confirming no unexpected `swift_retain` / `swift_release` calls

### 7. Measurement infrastructure

Create a measurement harness file: `Tools/latency-measurement.md`. Document the process for:
- Setting up a microphone near the keyboard and speakers
- Recording a "press → sound" capture using QuickTime or a similar tool
- Measuring sample-accurate latency from key press transient to sound onset in Audacity
- Expected result: under 10ms

Also document the Instruments Audio System Trace procedure:
- Launch Instruments, select "Audio System Trace"
- Attach to KlinkMac
- Type for 30 seconds at 150 WPM
- Confirm the render thread is hitting its deadline 100% of the time (no red "missed deadline" markers)

### 8. Stress test

Write a stress test script (can be a shell script using `osascript` to inject keystrokes, or a simple Swift CLI tool in `Tools/`) that simulates sustained 150 WPM for 5 minutes. Run it and confirm:
- Zero audio dropouts
- CPU on the audio thread stays in the 1–5% range
- No allocations appear in Instruments
- No warning logs

## Acceptance checklist

- [ ] SPSC `EventQueue` is unit-tested for push/pop correctness under contention (use two threads in the test)
- [ ] Audio render path has zero allocations as verified in Instruments
- [ ] Measured end-to-end latency is under 10ms (document the measurement in `LATENCY_LOG.md`)
- [ ] Stress test at 150 WPM for 5 minutes produces zero dropouts
- [ ] Pack switching during typing remains glitch-free with the new atomic swap
- [ ] CPU usage on audio thread is under 5% on Apple Silicon
- [ ] `NaiveAudioPlayer.swift` from Phase 0 is deleted
- [ ] Release build has no warnings

## Notes for Claude Code

- Read `ARCHITECTURE.md` carefully before starting. The latency budget table there is your target.
- Do not use `AVAudioPlayerNode` anywhere in the final code. The whole point of this phase is to own the render path.
- The `swift-atomics` package (added in Phase 0) is the source of atomic primitives. Don't roll your own.
- When in doubt, bias toward `UnsafeMutablePointer` and raw memory access. Swift's safety abstractions have costs that matter here.
- Any time you're tempted to add a lock, pause and ask: "could this be atomic-swap or a lock-free queue instead?" The answer is almost always yes.
