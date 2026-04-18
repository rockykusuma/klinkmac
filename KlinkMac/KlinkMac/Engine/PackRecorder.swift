// Microphone recorder for building custom sound packs one key at a time.
import AppKit
import AVFoundation
import Foundation
import os

@MainActor
@Observable
final class PackRecorder {
    // MARK: - State

    enum RecordState: Equatable {
        case idle
        case awaitingPress(keycode: UInt32, label: String)
        case recording(keycode: UInt32, label: String)
    }

    private(set) var state: RecordState = .idle
    private(set) var recordedKeys: Set<UInt32> = []

    // MARK: - Internals

    private var recordings: [UInt32: URL] = [:]
    private let recEngine = AVAudioEngine()
    private var tapSampleRate: Double = 48000
    private var accumSamples: [Float] = []
    private var isCapturing = false
    private var tailTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let tempDir: URL
    private let logger = Logger(subsystem: "com.klinkmac", category: "PackRecorder")

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.klinkmac.recorder-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func startListening(forKey keycode: UInt32, label: String) {
        if case .recording = state { cancelCurrentRecording() }
        tailTask?.cancel(); tailTask = nil
        startKeyMonitors()
        state = .awaitingPress(keycode: keycode, label: label)
    }

    func cancelListening() {
        tailTask?.cancel(); tailTask = nil
        maxDurationTask?.cancel(); maxDurationTask = nil
        cancelCurrentRecording()
        stopKeyMonitors()
        state = .idle
    }

    func deleteRecording(forKey keycode: UInt32) {
        if let url = recordings[keycode] { try? FileManager.default.removeItem(at: url) }
        recordings.removeValue(forKey: keycode)
        recordedKeys.remove(keycode)
    }

    /// Copies recorded WAVs + manifest into userPacksDirectory. Returns installed URL.
    func savePack(name: String, author: String) throws -> URL {
        guard !recordings.isEmpty else { throw RecorderError.noRecordings }

        let packID = sanitizeID(name)
        let fm = FileManager.default
        let destDir = try PackLoader.userPacksDirectory().appendingPathComponent(packID)
        if fm.fileExists(atPath: destDir.path) { try fm.removeItem(at: destDir) }
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let spaceKeycode: UInt32 = 49
        let defaultKC = recordings.keys.contains(spaceKeycode) ? spaceKeycode : recordings.keys.min()!
        let defaultFile = "key_\(defaultKC).wav"
        try fm.copyItem(at: recordings[defaultKC]!, to: destDir.appendingPathComponent(defaultFile))

        var keysDict: [String: [String: String]] = [:]
        for (kc, url) in recordings where kc != defaultKC {
            let fname = "key_\(kc).wav"
            try fm.copyItem(at: url, to: destDir.appendingPathComponent(fname))
            keysDict["\(kc)"] = ["down": fname]
        }

        var manifest: [String: Any] = [
            "formatVersion": 1,
            "id": packID,
            "name": name,
            "author": author.isEmpty ? "Me" : author,
            "version": "1.0.0",
            "defaults": ["down": defaultFile]
        ]
        if !keysDict.isEmpty { manifest["keys"] = keysDict }

        let json = try JSONSerialization.data(withJSONObject: manifest,
                                              options: [.prettyPrinted, .sortedKeys])
        try json.write(to: destDir.appendingPathComponent("manifest.json"))
        logger.info("Saved pack '\(packID)' — \(self.recordings.count) key(s)")
        return destDir
    }

    /// Must be called before releasing the recorder (stops monitors, cleans temp files).
    func cleanup() {
        tailTask?.cancel(); tailTask = nil
        maxDurationTask?.cancel(); maxDurationTask = nil
        cancelCurrentRecording()
        stopKeyMonitors()
        recordings.values.forEach { try? FileManager.default.removeItem(at: $0) }
        recordings = [:]
        recordedKeys = []
        state = .idle
        try? FileManager.default.removeItem(at: tempDir)
    }

    enum RecorderError: LocalizedError {
        case noRecordings
        var errorDescription: String? { "Record at least one key before saving." }
    }

    // MARK: - Key event monitors

    private func startKeyMonitors() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            self?.handleNSEvent(e)
            return e
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            self?.handleNSEvent(e)
        }
    }

    private func stopKeyMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    private func handleNSEvent(_ event: NSEvent) {
        let kc = UInt32(event.keyCode)
        let isDown = event.type == .keyDown
        switch state {
        case .awaitingPress(let expected, let label):
            if kc == expected && isDown { beginRecording(keycode: expected, label: label) }
        case .recording(let expected, _):
            if kc == expected && !isDown { scheduleStop(keycode: expected) }
        case .idle:
            break
        }
    }

    // MARK: - Recording lifecycle

    private func cancelCurrentRecording() {
        isCapturing = false
        if recEngine.isRunning {
            recEngine.inputNode.removeTap(onBus: 0)
            recEngine.stop()
        }
        accumSamples = []
    }

    private func beginRecording(keycode: UInt32, label: String) {
        accumSamples = []
        isCapturing = true
        state = .recording(keycode: keycode, label: label)

        let inputNode = recEngine.inputNode
        let fmt = inputNode.inputFormat(forBus: 0)
        tapSampleRate = fmt.sampleRate
        let channels = Int(fmt.channelCount)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let chan = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            var mono = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                var s: Float = 0
                for ch in 0..<channels { s += chan[ch][i] }
                mono[i] = channels > 1 ? s / Float(channels) : s
            }
            Task { @MainActor [weak self] in
                guard let self, self.isCapturing else { return }
                self.accumSamples.append(contentsOf: mono)
            }
        }

        do {
            try recEngine.start()
        } catch {
            logger.error("RecordEngine start failed: \(error.localizedDescription)")
            cancelCurrentRecording()
            stopKeyMonitors()
            state = .idle
            return
        }

        // Auto-stop after 380ms so total recording stays under 500ms limit
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            if case .recording(let kc, _) = self?.state, kc == keycode {
                self?.scheduleStop(keycode: keycode)
            }
        }
    }

    private func scheduleStop(keycode: UInt32) {
        guard case .recording(let kc, _) = state, kc == keycode, tailTask == nil else { return }
        maxDurationTask?.cancel(); maxDurationTask = nil
        tailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.finalizeRecording(keycode: keycode)
        }
    }

    private func finalizeRecording(keycode: UInt32) {
        tailTask = nil
        let samples = accumSamples
        isCapturing = false
        if recEngine.isRunning {
            recEngine.inputNode.removeTap(onBus: 0)
            recEngine.stop()
        }
        accumSamples = []
        stopKeyMonitors()

        guard !samples.isEmpty else { state = .idle; return }

        let monoFmt = AVAudioFormat(standardFormatWithSampleRate: tapSampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buf = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: frameCount),
              let dst = buf.floatChannelData else { state = .idle; return }
        buf.frameLength = frameCount
        for i in 0..<samples.count { dst[0][i] = samples[i] }

        normalize(buffer: buf, targetPeak: 0.5)

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: tapSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let fileURL = tempDir.appendingPathComponent("\(keycode).wav")
        do {
            if let old = recordings[keycode] { try? FileManager.default.removeItem(at: old) }
            let file = try AVAudioFile(forWriting: fileURL, settings: wavSettings)
            try file.write(from: buf)
            recordings[keycode] = fileURL
            recordedKeys.insert(keycode)
            logger.info("Recorded key \(keycode): \(samples.count) samples @ \(self.tapSampleRate)Hz")
        } catch {
            logger.error("WAV write failed for key \(keycode): \(error.localizedDescription)")
        }
        state = .idle
    }

    // MARK: - Helpers

    private func normalize(buffer: AVAudioPCMBuffer, targetPeak: Float) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(data[0][i])) }
        guard peak > 1e-6 else { return }
        let gain = targetPeak / peak
        for i in 0..<n { data[0][i] *= gain }
    }

    private func sanitizeID(_ name: String) -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let slug = name.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let trimmed = slug.isEmpty ? "pack" : String(slug.prefix(40))
        return "com.klinkmac.user.\(trimmed)-\(ts)"
    }
}
