# Phase 1 — Feel

## Goal

Move from "it makes noise" to "it sounds like a real mechanical keyboard." Different sounds per key, distinct down/up, natural pitch variation, multiple bundled packs with live switching.

## Ship criteria

- Spacebar, enter, backspace, and alphanumerics produce distinct sounds
- Each keypress has both a down sound (on press) and up sound (on release) where the pack provides one
- Natural variation between identical keystrokes — no robotic "looped sample" feel
- Three bundled packs: clicky (Cherry MX Blue-style), tactile (Cherry MX Brown-style), thocky (Topre-style)
- Switching packs from the menu bar is instant and produces no clicks, pops, or dropouts
- Rapid typing (sustained 120+ WPM) does not drop keystrokes

## Out of scope

- Custom `AVAudioSourceNode` render callback (Phase 2)
- Low-latency optimization (Phase 2)
- Loading packs from disk — packs remain bundled in the app (Phase 3 adds loading)
- Formal pack file format — Phase 3 defines the shipping format
- Recording custom packs (Phase 4)

## Deliverables

### 1. SampleBank (v1)

File: `Engine/SampleBank.swift`.

```swift
public struct PackSample {
    public let downFrames: UnsafePointer<Float>
    public let downFrameCount: Int
    public let upFrames: UnsafePointer<Float>?     // optional
    public let upFrameCount: Int                   // 0 if no up sound
    public let channelCount: Int                   // 1 or 2
}

public final class SampleBank {
    public let name: String
    public let samples: [UInt16: PackSample]      // key = macOS virtual keycode
    public let defaultSample: PackSample           // fallback for unmapped keys
    // owns the underlying PCM memory, frees on deinit
}
```

- Immutable after construction
- Allocates raw `Float` buffers via `UnsafeMutablePointer<Float>.allocate(capacity:)`; frees in `deinit`
- Built by the pack loader (see below), not by the audio thread

### 2. Pack loader (v1 — bundled packs only)

File: `Packs/PackLoader.swift`.

```swift
public final class PackLoader {
    public static func loadBundled(named: String) throws -> SampleBank
    // Phase 3 will add loadFromDisk(url:)
}
```

Implementation:
- Each bundled pack is a directory in `Resources/Packs/` with a `manifest.json` and a set of WAVs
- Load `manifest.json` — see `specs/sound-pack-format.md` for the schema (v1 subset is acceptable here)
- For each entry, load the WAV with `AVAudioFile`, read into a temporary `AVAudioPCMBuffer`
- Convert to the output device's native format (48kHz typically) using `AVAudioConverter`
- Copy the converted samples into heap-allocated `UnsafeMutablePointer<Float>` buffers
- Build the `SampleBank` and return

Load on a background `DispatchQueue.global(qos: .userInitiated)`, not the main thread.

### 3. Voice allocator

File: `Engine/VoiceAllocator.swift`.

```swift
struct Voice {
    var samplePtr: UnsafePointer<Float>?
    var frameCount: Int
    var position: Double            // fractional for pitch shift
    var pitchRatio: Float            // 1.0 = normal
    var gainL: Float
    var gainR: Float
    var active: Bool
}

public final class VoiceAllocator {
    public init(poolSize: Int = 24)
    public func allocate(samplePtr: UnsafePointer<Float>, frames: Int, pitchRatio: Float)
    public func render(into output: UnsafeMutableBufferPointer<Float>, frameCount: Int, channelCount: Int)
}
```

- `voices` is a `[Voice]` of fixed size, pre-allocated at init
- `allocate`: linear scan for `active == false`. If none, steal the voice with the smallest `frameCount - Int(position)` remaining
- `render`: iterate voices; for each active one, advance `position` by `pitchRatio` per output frame, linear-interpolate between consecutive sample frames, accumulate into the output buffer. Deactivate when `position >= frameCount`

Pitch randomization: at allocation time, set `pitchRatio = 1.0 + Float.random(in: -0.025 ... 0.025)`. This is the single biggest trick to avoid the "loop" feel.

### 4. Audio engine (still using AVAudioPlayerNode, last time)

File: `Engine/AudioEngine.swift`. This version uses `AVAudioEngine` with a `AVAudioSourceNode` wrapping our `VoiceAllocator.render()`. This is actually the shape we want in Phase 2, but we're allowed a simpler implementation here if it ships faster — the critical thing is that per-key sound dispatch lives inside the render callback.

```swift
public final class AudioEngine {
    public init()
    public func start() throws
    public func stop()
    public func setBank(_ bank: SampleBank)
    public func handleEvent(_ event: KeyEvent)
}
```

- `handleEvent` looks up the sample in the current bank, picks the right down/up buffer, and calls `allocator.allocate(...)`
- The render callback (inside the source node) calls `allocator.render(...)` into the provided buffers
- Keep the current bank as a property for now — Phase 2 replaces this with atomic pointer swap

### 5. Bundled packs

Three packs in `Resources/Packs/`:

- `cherry-mx-blue/` — clicky, high-pitched, sharp
- `cherry-mx-brown/` — tactile, rounded, softer
- `topre-silent/` — deep "thock" with muted release

Each pack has (minimum):

```
pack-name/
├── manifest.json
├── default-down.wav          # fallback for any unmapped key
├── default-up.wav
├── space-down.wav             # stabilized space is distinct
├── space-up.wav
├── enter-down.wav
├── enter-up.wav
├── backspace-down.wav
└── backspace-up.wav
```

Source samples from licensed / permissively-licensed sources. The mechvibes-lite GitHub org has some CC0 packs that can be adapted, or record your own.

### 6. Pack picker in the menu bar

- Menu bar submenu: "Pack →"
  - Cherry MX Blue ✓ (checkmark for active)
  - Cherry MX Brown
  - Topre Silent
- Selecting swaps the active bank via `AudioEngine.setBank(_:)`
- The swap happens on the main thread; Phase 2 formalizes this with atomic pointer swap

### 7. Volume slider

- Add a SwiftUI `Slider` (0.0 – 1.0) inside the menu bar dropdown content
- Apply as a global gain multiplier in `VoiceAllocator.render()` — single `Float` read, no allocation

## Acceptance checklist

- [ ] Typing a paragraph sounds natural and non-robotic
- [ ] Spacebar, enter, and backspace each sound distinctly different from letter keys
- [ ] Key-up sounds are present and audible
- [ ] Switching packs mid-type produces no click, pop, or brief silence
- [ ] Sustained 150 WPM typing has no dropped sounds
- [ ] Volume slider is audible and smooth (no zippering)
- [ ] Three packs all sound unambiguously different from each other
- [ ] No warnings in Release build
- [ ] Unit tests cover `VoiceAllocator` (allocation under pressure, stealing correctness) and `SampleBank` (lookup, fallback behavior)

## Notes for Claude Code

- Do NOT optimize for latency in this phase. Focus on correctness of the polyphony and pack switching. Phase 2 handles latency holistically.
- Voice stealing correctness matters — write tests for it. The easiest test: allocate 30 voices into a pool of 24, assert that the 6 oldest were overwritten.
- If `AVAudioSourceNode` setup feels too complex for this phase, it's acceptable to use `AVAudioPlayerNode` pool as a stepping stone. The important thing is the `VoiceAllocator` API shape — that becomes the core of Phase 2.
