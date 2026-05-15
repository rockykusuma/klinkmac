// Audio render path — AVAudioSourceNode drains EventQueue and renders voices. No locks, no ARC.
import Atomics
import AVFoundation
import CoreAudio
import Foundation
import os

/// Audio-thread-private state for velocity-aware sound modulation.
/// Heap-allocated once at engine start, mutated only from the render callback.
struct VelocityState {
    var avgIKI: Double
    var lastDownTimestamp: UInt64
}

/// Updates velocity state from a key-down event and returns (gain, pitchBias) for sample allocation.
/// Called only from the audio render thread — no allocations, no locks, no ARC.
@inline(__always)
func velocityModulation(for event: KeyEvent,
                        state: UnsafeMutablePointer<VelocityState>,
                        machToSec: Double) -> (gain: Float, pitchBias: Float) {
    // EWMA of inter-key-interval in seconds. alpha 0.35 responds in ~3 keys.
    if state.pointee.lastDownTimestamp != 0 {
        let delta = event.timestamp &- state.pointee.lastDownTimestamp
        let iki = Double(delta) * machToSec
        state.pointee.avgIKI = 0.35 * iki + 0.65 * state.pointee.avgIKI
    }
    state.pointee.lastDownTimestamp = event.timestamp

    // Map IKI → intensity ∈ [0, 1].
    //   0.08s (≈150 WPM) → 0.0 (fast, light)
    //   0.40s (≈30 WPM)  → 1.0 (slow, heavy)
    let raw = (state.pointee.avgIKI - 0.08) / 0.32
    let intensity = Float(min(1.0, max(0.0, raw)))
    // gain range 0.55–1.0 (~5dB swing), pitch range 0.94–1.06 (~one semitone).
    return (gain: 0.55 + 0.45 * intensity,
            pitchBias: 1.06 - 0.12 * intensity)
}

public final class AudioEngine {
    private let engine       = AVAudioEngine()
    private let allocator    = VoiceAllocator(poolSize: 24)
    let eventQueue           = EventQueue(capacity: 256)
    private let bankPointer  = AtomicBankPointer()
    private let enabledFlag  = ManagedAtomic<Bool>(true)
    private let velocityFlag = ManagedAtomic<Bool>(true)
    // Audio-thread-private mutable state. Allocated once, reused across engine restarts.
    private let velocityState: UnsafeMutablePointer<VelocityState> = {
        let p = UnsafeMutablePointer<VelocityState>.allocate(capacity: 1)
        p.initialize(to: VelocityState(avgIKI: 0.25, lastDownTimestamp: 0))
        return p
    }()
    private var sourceNode: AVAudioSourceNode?
    private var targetDeviceID: AudioDeviceID?
    private var configChangeObserver: Any?

    // Updated in start() from the actual output device format.
    private(set) var sampleRate: Double = 48000

    var volume: Float {
        get { allocator.volume }
        set { allocator.volume = newValue }
    }

    public init() {}

    deinit {
        velocityState.deinitialize(count: 1)
        velocityState.deallocate()
    }

    public func setVelocityDynamics(_ enabled: Bool) {
        velocityFlag.store(enabled, ordering: .releasing)
    }
    // swiftlint:disable:next function_body_length
    public func start() throws {
        // Stop FIRST — AudioOutputUnitStop is synchronous; blocks until the current
        // I/O cycle finishes so the render thread cannot call pop() after the reset.
        // Call unconditionally: safe no-op if already stopped, but needed when the
        // engine is still running (e.g. setOutputDevice path, or if isRunning lags
        // behind the internal stopped state after AVAudioEngineConfigurationChange).
        engine.stop()
        // Detach old source node after stop — render callbacks are guaranteed done.
        if let old = sourceNode { engine.detach(old); sourceNode = nil }
        // Reset thread assertions now — I/O thread is fully quiesced.
        eventQueue.resetThreadAssertions()

        // Re-register on every start so we don't stack observers across restarts.
        if let obs = configChangeObserver { NotificationCenter.default.removeObserver(obs) }
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // Delay restart: gives the old I/O thread time to fully quiesce before
            // we reset thread assertions and bring up a new render thread.
            // Do NOT call resetThreadAssertions() here — the old render thread may
            // still be active on the notification thread; resetting early causes it
            // to re-store its ID, which then races the new thread → SPSC crash.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                try? self?.start()
            }
        }

        applyOutputDevice(targetDeviceID)
        let outputNode = engine.outputNode
        let deviceRate = outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = deviceRate > 0 ? deviceRate : 48000

        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let alloc     = allocator
        let q         = eventQueue
        let bp        = bankPointer
        let enabled   = enabledFlag
        let velocity  = velocityFlag

        // Velocity-aware state pointer — owned by the engine instance, reused across restarts.
        // Reset at each start so IKI history doesn't carry over a paused/resumed session.
        let state = velocityState
        state.pointee = VelocityState(avgIKI: 0.25, lastDownTimestamp: 0)
        let machToSec = Self.machTimebaseToSeconds()

        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl   = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let outData = abl.first?.mData else { return noErr }
            let count = Int(frameCount)
            let out   = outData.bindMemory(to: Float.self, capacity: count)

            // Zero fill.
            for i in 0..<count { out[i] = 0 }

            // Atomic bank load — no ARC, no retain on this thread.
            guard let bankRef = bp.load() else { return noErr }

            // _withUnsafeGuaranteedRef: access SampleBank without ARC retain/release.
            // AtomicBankPointer holds the +1 retain; deferred release waits 5s after swap.
            bankRef._withUnsafeGuaranteedRef { bank in
                let isEnabled     = enabled.load(ordering: .relaxed)
                let velocityOn    = velocity.load(ordering: .relaxed)

                // Drain event queue into voice allocator.
                while let event = q.pop() {
                    guard isEnabled else { continue }
                    let s = bank.sample(for: event.keycode)
                    if event.isDown {
                        let mod = velocityOn
                            ? velocityModulation(for: event, state: state, machToSec: machToSec)
                            : (gain: Float(1.0), pitchBias: Float(1.0))
                        alloc.allocate(samplePtr: s.downFrames, frames: s.downFrameCount,
                                       gain: mod.gain, pitchBias: mod.pitchBias)
                    } else if let up = s.upFrames, s.upFrameCount > 0 {
                        alloc.allocate(samplePtr: up, frames: s.upFrameCount)
                    }
                }

                guard isEnabled else { return }

                // Render active voices.
                alloc.render(into: UnsafeMutableBufferPointer(start: out, count: count),
                             frameCount: count)
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        try engine.start()
        // Set after engine start so the HAL device is active. Targets the default
        // output device via CoreAudio — affects all apps, but 128 frames is benign.
        setHardwareBufferSize(128)
    }

    public func stop() { engine.stop() }

    /// CGEvent.timestamp is in nanoseconds since boot, NOT mach_absolute_time ticks.
    /// Using mach_timebase (125/3 on Apple Silicon) over-scales by ~42×. Always divide by 1e9.
    private static func machTimebaseToSeconds() -> Double { 1e-9 }

    public func setBank(_ bank: SampleBank) { bankPointer.store(bank) }

    public func setEnabled(_ enabled: Bool) { enabledFlag.store(enabled, ordering: .releasing) }

    public func setOutputDevice(_ deviceID: AudioDeviceID?) throws {
        targetDeviceID = deviceID
        guard engine.isRunning else { return }
        if let node = sourceNode { engine.detach(node); sourceNode = nil }
        engine.stop()
        try start()
    }

    // MARK: - Output device discovery

    public static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propSize = UInt32(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sysObj, &addr, 0, nil, &propSize) == noErr else { return [] }
        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &propSize, &ids) == noErr else { return [] }
        return ids.compactMap { devID -> (AudioDeviceID, String)? in
            guard hasOutputStream(devID), let name = deviceDisplayName(devID) else { return nil }
            return (devID, name)
        }
    }

    // MARK: - Hardware buffer configuration

    private func setHardwareBufferSize(_ frames: UInt32) {
        var deviceID = AudioDeviceID(0)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
        ) == noErr else { return }

        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var frameSize = frames
        let status = AudioObjectSetPropertyData(
            deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frameSize
        )
        if status != noErr {
            logger.warning("Could not set hardware buffer size to \(frames) frames (OSStatus \(status))")
        }
    }

    private func applyOutputDevice(_ deviceID: AudioDeviceID?) {
        guard let audioUnit = engine.outputNode.audioUnit else { return }
        var target: AudioDeviceID
        if let deviceID, deviceID != 0 {
            target = deviceID
        } else {
            var defaultID = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultID
            ) == noErr, defaultID != 0 else { return }
            target = defaultID
        }
        var dev = target
        let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0,
                                          &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            logger.warning("Could not set output device \(target): OSStatus \(status)")
        }
    }

    private static func hasOutputStream(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func deviceDisplayName(_ deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private let logger = Logger(subsystem: "com.klinkmac", category: "AudioEngine")
}
