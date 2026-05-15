// Microphone recorder for building custom sound packs — per-key and auto-record modes.
import AppKit
import AVFoundation
import Foundation
import os

@MainActor
@Observable
final class PackRecorder {
    enum RecordState: Equatable {
        case idle
        case autoRecording
        case awaitingPress(keycode: UInt32, label: String)
        case recording(keycode: UInt32, label: String)
    }

    private(set) var state: RecordState = .idle
    private(set) var recordedKeys: Set<UInt32> = []
    private(set) var micPermissionDenied: Bool = false

    private var recordings: [UInt32: URL] = [:]
    private let recEngine = AVAudioEngine()
    private var tapSampleRate: Double = 48000
    private var accumSamples: [Float] = []
    private var isCapturing = false
    private var tailTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var previewPlayer: AVAudioPlayer?
    private var upRecordings: [UInt32: URL] = [:]
    private var splitIndex: Int = 0
    private var recordingStartTime = Date()
    private var isAutoMode = false
    private static let modifierKeycodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private let tempDir: URL
    private let logger = Logger(subsystem: "com.klinkmac", category: "PackRecorder")

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.klinkmac.recorder-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func startListening(forKey keycode: UInt32, label: String) {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        if s == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] g in
                Task { @MainActor [weak self] in
                    self?.micPermissionDenied = !g
                    if g { self?.startListening(forKey: keycode, label: label) }
                }
            }
            return
        }
        guard s == .authorized else { micPermissionDenied = true; return }
        isAutoMode = false
        if case .recording = state { cancelCurrentRecording() }
        tailTask?.cancel(); tailTask = nil
        startKeyMonitors()
        state = .awaitingPress(keycode: keycode, label: label)
    }

    func startAutoRecording() {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        if s == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] g in
                Task { @MainActor [weak self] in
                    self?.micPermissionDenied = !g
                    if g { self?.startAutoRecording() }
                }
            }
            return
        }
        guard s == .authorized else { micPermissionDenied = true; return }
        if case .recording = state { cancelCurrentRecording() }
        isAutoMode = true; startKeyMonitors(); state = .autoRecording
    }

    func stopAutoRecording() {
        isAutoMode = false; tailTask?.cancel(); tailTask = nil
        maxDurationTask?.cancel(); maxDurationTask = nil
        cancelCurrentRecording(); stopKeyMonitors(); state = .idle
    }

    func previewRecording(forKey keycode: UInt32) {
        guard let url = recordings[keycode] else { return }
        previewPlayer?.stop(); previewPlayer = try? AVAudioPlayer(contentsOf: url); previewPlayer?.play()
    }

    func cancelListening() {
        isAutoMode = false; tailTask?.cancel(); tailTask = nil
        maxDurationTask?.cancel(); maxDurationTask = nil
        cancelCurrentRecording(); stopKeyMonitors(); state = .idle
    }

    func deleteRecording(forKey keycode: UInt32) {
        if let url = recordings[keycode] { try? FileManager.default.removeItem(at: url) }
        if let url = upRecordings[keycode] { try? FileManager.default.removeItem(at: url) }
        recordings.removeValue(forKey: keycode); upRecordings.removeValue(forKey: keycode)
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
        var defaultEntry: [String: String] = ["down": defaultFile]
        if let f = try copyUpFile(kc: defaultKC, to: destDir, fm: fm) { defaultEntry["up"] = f }

        var keysDict: [String: [String: String]] = [:]
        for (kc, url) in recordings where kc != defaultKC {
            let fname = "key_\(kc).wav"
            try fm.copyItem(at: url, to: destDir.appendingPathComponent(fname))
            var entry: [String: String] = ["down": fname]
            if let f = try copyUpFile(kc: kc, to: destDir, fm: fm) { entry["up"] = f }
            keysDict["\(kc)"] = entry
        }

        var manifest: [String: Any] = [
            "formatVersion": 1, "id": packID, "name": name,
            "author": author.isEmpty ? "Me" : author,
            "version": "1.0.0", "defaults": defaultEntry
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
        isAutoMode = false; tailTask?.cancel(); tailTask = nil
        maxDurationTask?.cancel(); maxDurationTask = nil
        cancelCurrentRecording(); stopKeyMonitors()
        previewPlayer?.stop(); previewPlayer = nil
        recordings.values.forEach { try? FileManager.default.removeItem(at: $0) }
        upRecordings.values.forEach { try? FileManager.default.removeItem(at: $0) }
        recordings = [:]; upRecordings = [:]
        recordedKeys = []; state = .idle
        try? FileManager.default.removeItem(at: tempDir)
    }

    enum RecorderError: LocalizedError {
        case noRecordings
        var errorDescription: String? { "Record at least one key before saving." }
    }
}

// MARK: - Key event monitors

private extension PackRecorder {
    func startKeyMonitors() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            self?.handleNSEvent(e)
            return e
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            self?.handleNSEvent(e)
        }
    }

    func stopKeyMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    func handleNSEvent(_ event: NSEvent) {
        let kc = UInt32(event.keyCode)
        let isDown = event.type == .keyDown
        switch state {
        case .autoRecording:
            guard !Self.modifierKeycodes.contains(kc), isDown else { break }
            beginRecording(keycode: kc, label: label(for: kc))
        case .awaitingPress(let expected, let lbl):
            if kc == expected && isDown { beginRecording(keycode: expected, label: lbl) }
        case .recording(let expected, _):
            if kc == expected && !isDown { scheduleStop(keycode: expected) }
        case .idle:
            break
        }
    }
}

// MARK: - Recording lifecycle

private extension PackRecorder {
    func cancelCurrentRecording() {
        isCapturing = false
        if recEngine.isRunning { recEngine.inputNode.removeTap(onBus: 0); recEngine.stop() }
        accumSamples = []
    }

    func beginRecording(keycode: UInt32, label: String) {
        accumSamples = []
        isCapturing = true
        recordingStartTime = Date()
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

        do { try recEngine.start() } catch {
            logger.error("RecordEngine start failed: \(error.localizedDescription)")
            cancelCurrentRecording(); stopKeyMonitors(); state = .idle; return
        }

        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled, case .recording(let kc, _) = self?.state, kc == keycode else { return }
            self?.scheduleStop(keycode: keycode)
        }
    }

    func scheduleStop(keycode: UInt32) {
        guard case .recording(let kc, _) = state, kc == keycode, tailTask == nil else { return }
        maxDurationTask?.cancel(); maxDurationTask = nil
        splitIndex = Int(Date().timeIntervalSince(recordingStartTime) * tapSampleRate)
        tailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.finalizeRecording(keycode: keycode)
        }
    }

    func finalizeRecording(keycode: UInt32) {
        tailTask = nil
        let all = accumSamples
        let split = min(splitIndex, all.count)
        isCapturing = false
        if recEngine.isRunning { recEngine.inputNode.removeTap(onBus: 0); recEngine.stop() }
        accumSamples = []
        let next: RecordState = isAutoMode ? .autoRecording : .idle
        if !isAutoMode { stopKeyMonitors() }
        guard !all.isEmpty else { state = next; return }

        let sr = tapSampleRate
        let downURL = tempDir.appendingPathComponent("\(keycode).wav")
        let upURL   = tempDir.appendingPathComponent("\(keycode)_up.wav")
        do {
            if let old = recordings[keycode] { try? FileManager.default.removeItem(at: old) }
            if let old = upRecordings[keycode] { try? FileManager.default.removeItem(at: old) }
            try writeWAV(samples: Array(all[..<split]), sampleRate: sr, to: downURL)
            recordings[keycode] = downURL
            if split < all.count {
                try writeWAV(samples: Array(all[split...]), sampleRate: sr, to: upURL)
                upRecordings[keycode] = upURL
            }
            recordedKeys.insert(keycode)
            logger.info("Recorded key \(keycode): \(split) down + \(all.count - split) up samples")
        } catch {
            logger.error("WAV write failed for key \(keycode): \(error.localizedDescription)")
        }
        state = next
    }
}

// MARK: - Helpers

private extension PackRecorder {
    func writeWAV(samples: [Float], sampleRate sr: Double, to url: URL) throws {
        guard !samples.isEmpty else { return }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)),
              let dst = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { dst[0][i] = samples[i] }
        let n = Int(buf.frameLength); var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(dst[0][i])) }
        if peak > 1e-6 { let g = 0.5 / peak; for i in 0..<n { dst[0][i] *= g } }
        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        try AVAudioFile(forWriting: url, settings: wavSettings).write(from: buf)
    }

    @discardableResult
    func copyUpFile(kc: UInt32, to dir: URL, fm: FileManager) throws -> String? {
        guard let u = upRecordings[kc] else { return nil }
        let f = "key_\(kc)_up.wav"
        try fm.copyItem(at: u, to: dir.appendingPathComponent(f)); return f
    }

    func label(for kc: UInt32) -> String {
        let m: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫"
        ]
        return m[kc] ?? "#\(kc)"
    }

    func sanitizeID(_ name: String) -> String {
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
