// Audio render path — AVAudioSourceNode drains EventQueue and renders voices. No locks, no ARC.
import Atomics
import AVFoundation
import CoreAudio
import Foundation
import os

public final class AudioEngine {
    private let engine      = AVAudioEngine()
    private let allocator   = VoiceAllocator(poolSize: 24)
    let eventQueue          = EventQueue(capacity: 256)
    private let bankPointer = AtomicBankPointer()
    private let enabledFlag = ManagedAtomic<Bool>(true)
    private var sourceNode: AVAudioSourceNode?
    private var targetDeviceID: AudioDeviceID?

    // Updated in start() from the actual output device format.
    private(set) var sampleRate: Double = 48000

    var volume: Float {
        get { allocator.volume }
        set { allocator.volume = newValue }
    }

    public init() {}

    public func start() throws {
        eventQueue.resetThreadAssertions()
        applyOutputDevice(targetDeviceID)
        let outputNode = engine.outputNode
        let deviceRate = outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = deviceRate > 0 ? deviceRate : 48000

        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let alloc   = allocator
        let q       = eventQueue
        let bp      = bankPointer
        let enabled = enabledFlag

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
                let isEnabled = enabled.load(ordering: .relaxed)

                // Drain event queue into voice allocator.
                while let event = q.pop() {
                    guard isEnabled else { continue }
                    let s = bank.sample(for: event.keycode)
                    if event.isDown {
                        alloc.allocate(samplePtr: s.downFrames, frames: s.downFrameCount)
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
