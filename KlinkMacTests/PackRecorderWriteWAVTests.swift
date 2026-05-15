// Unit tests for PackRecorder.writeWAV — peak normalization, format, empty-input no-op.
import AVFoundation
import XCTest
@testable import KlinkMac

@MainActor
final class PackRecorderWriteWAVTests: XCTestCase {

    private var tmpDir: URL!
    private var recorder: PackRecorder!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        recorder = PackRecorder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testEmptySamplesProducesNoFile() throws {
        let url = tmpDir.appendingPathComponent("empty.wav")
        try recorder.writeWAV(samples: [], sampleRate: 48000, to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "writeWAV should not create a file when given zero samples")
    }

    func testWritesReadableWAV() throws {
        let url = tmpDir.appendingPathComponent("tone.wav")
        let samples: [Float] = (0..<480).map { i in 0.3 * sin(2.0 * .pi * Float(i) / 48.0) }
        try recorder.writeWAV(samples: samples, sampleRate: 48000, to: url)

        let readBack = try AVAudioFile(forReading: url)
        XCTAssertEqual(readBack.length, AVAudioFramePosition(samples.count))
        XCTAssertEqual(readBack.fileFormat.sampleRate, 48000)
        XCTAssertEqual(readBack.fileFormat.channelCount, 1)
    }

    func testPeakNormalizationClampsLoudSamplesToHalf() throws {
        let url = tmpDir.appendingPathComponent("loud.wav")
        // Peak 2.0 — must normalize down so written peak ≤ 0.5.
        let samples: [Float] = [0.0, 2.0, -1.5, 1.0]
        try recorder.writeWAV(samples: samples, sampleRate: 48000, to: url)

        let readBack = try readSamples(from: url)
        let peak = readBack.map(abs).max() ?? 0
        // 16-bit quantization adds ~1/32768 noise; allow small slack.
        XCTAssertLessThanOrEqual(peak, 0.5 + 1.0 / 32768.0,
                                 "Peak should be normalized to ≤ 0.5, got \(peak)")
        XCTAssertGreaterThan(peak, 0.4, "Normalized peak should sit near 0.5, got \(peak)")
    }

    func testQuietSamplesAreNotAmplified() throws {
        let url = tmpDir.appendingPathComponent("quiet.wav")
        // Peak below 1e-6 — writeWAV skips normalization.
        let samples: [Float] = Array(repeating: 1e-8, count: 100)
        try recorder.writeWAV(samples: samples, sampleRate: 48000, to: url)

        let readBack = try readSamples(from: url)
        let peak = readBack.map(abs).max() ?? 0
        // After 16-bit quantization, sub-quantum signals round to 0.
        XCTAssertLessThan(peak, 1.0 / 32768.0,
                          "Sub-threshold samples must not be boosted; peak was \(peak)")
    }

    // MARK: - Helpers

    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: file.fileFormat.sampleRate,
                                   channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        guard let channel = buf.floatChannelData?[0] else { return [] }
        return (0..<Int(buf.frameLength)).map { channel[$0] }
    }
}
