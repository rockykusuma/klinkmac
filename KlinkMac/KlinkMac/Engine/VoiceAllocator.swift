// Fixed-pool polyphonic voice allocator — called exclusively from audio render thread, no locking.
import Foundation

struct Voice {
    var samplePtr: UnsafePointer<Float>?
    var frameCount: Int = 0
    var position: Double = 0
    var pitchRatio: Float = 1.0
    var gain: Float = 1.0
    var active: Bool = false
}

public final class VoiceAllocator {
    private var voices: [Voice]
    var volume: Float = 1.0
    // Fast LCG — RT-safe pitch randomization (no system calls, no locks).
    private var rngState: UInt64 = 6364136223846793005

    public init(poolSize: Int = 24) {
        voices = [Voice](repeating: Voice(), count: poolSize)
    }

    // Swift 6 infers an actor-isolated deinit for types transitively owned by @MainActor classes.
    // Explicitly opt out — VoiceAllocator is audio-thread-only; its cleanup is trivially thread-safe.
    nonisolated deinit {}

    public func allocate(samplePtr: UnsafePointer<Float>,
                         frames: Int,
                         gain: Float = 1.0,
                         pitchBias: Float = 1.0) {
        rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
        let jitter = 1.0 + (Float(UInt32(rngState >> 32)) / Float(UInt32.max)) * 0.05 - 0.025
        let pitchRatio = jitter * pitchBias

        var idx = voices.firstIndex { !$0.active }
        if idx == nil {
            var minRemaining = Int.max
            for i in 0..<voices.count {
                let remaining = voices[i].frameCount - Int(voices[i].position)
                if remaining < minRemaining { minRemaining = remaining; idx = i }
            }
        }
        guard let i = idx else { return }
        voices[i] = Voice(samplePtr: samplePtr, frameCount: frames,
                          position: 0, pitchRatio: pitchRatio, gain: gain, active: true)
    }

    public func render(into output: UnsafeMutableBufferPointer<Float>, frameCount: Int) {
        let vol = volume
        for i in 0..<voices.count {
            guard voices[i].active, let ptr = voices[i].samplePtr else { continue }
            let fc = voices[i].frameCount
            var pos = voices[i].position
            let ratio = Double(voices[i].pitchRatio)
            let gain = voices[i].gain * vol

            for f in 0..<frameCount {
                let ipos = Int(pos)
                guard ipos < fc - 1 else { voices[i].active = false; break }
                let frac = Float(pos - Double(ipos))
                output[f] += (ptr[ipos] + frac * (ptr[ipos + 1] - ptr[ipos])) * gain
                pos += ratio
            }
            voices[i].position = pos
            if Int(pos) >= fc { voices[i].active = false }
        }
    }
}
