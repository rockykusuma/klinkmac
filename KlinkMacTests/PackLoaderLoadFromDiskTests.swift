// End-to-end tests for PackLoader.loadFromDisk — duration limit, happy path, missing audio.
import AVFoundation
import XCTest
@testable import KlinkMac

final class PackLoaderLoadFromDiskTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Tests

    func testLoadFromDiskHappyPath() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.happy","name":"Happy","author":"T",
         "version":"1.0","defaults":{"down":"d.wav"}}
        """)
        try writeWAV(named: "d.wav", durationMs: 50, sampleRate: 48000)

        let bank = try PackLoader.loadFromDisk(at: tmpDir, sampleRate: 48000)
        let sample = bank.sample(for: 36) // arbitrary keycode → falls back to defaults
        XCTAssertGreaterThan(sample.downFrameCount, 0,
                             "loadFromDisk should decode default down sample")
    }

    func testLoadFromDiskRejectsAudioLongerThan500ms() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.long","name":"Long","author":"T",
         "version":"1.0","defaults":{"down":"d.wav"}}
        """)
        try writeWAV(named: "d.wav", durationMs: 600, sampleRate: 48000)

        assertError({ _ = try PackLoader.loadFromDisk(at: self.tmpDir, sampleRate: 48000) }) {
            if case .audioDurationTooLong(file: "d.wav", durationMs: let ms) = $0 {
                return ms >= 500
            }
            return false
        }
    }

    func testLoadFromDiskResamplesAcrossSampleRates() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.rs","name":"RS","author":"T",
         "version":"1.0","defaults":{"down":"d.wav"}}
        """)
        try writeWAV(named: "d.wav", durationMs: 50, sampleRate: 44100)

        // Engine wants 48k — converter must resample without throwing.
        let bank = try PackLoader.loadFromDisk(at: tmpDir, sampleRate: 48000)
        XCTAssertGreaterThan(bank.sample(for: 36).downFrameCount, 0)
    }

    func testLoadFromDiskRejectsMissingAudioFile() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.gone","name":"Gone","author":"T",
         "version":"1.0","defaults":{"down":"missing.wav"}}
        """)
        // Manifest validation (called by loadFromDisk) catches missing files
        // before the audio decoder is ever reached.
        assertError({ _ = try PackLoader.loadFromDisk(at: self.tmpDir, sampleRate: 48000) }) {
            if case .missingAudioFile("missing.wav") = $0 { return true }
            return false
        }
    }

    // MARK: - Helpers

    private func writeManifest(_ json: String) throws {
        try json.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("manifest.json"))
    }

    private func writeWAV(named filename: String, durationMs: Int, sampleRate: Double) throws {
        let frameCount = Int(Double(durationMs) / 1000.0 * sampleRate)
        let url = tmpDir.appendingPathComponent(filename)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frameCount))!
        buf.frameLength = AVAudioFrameCount(frameCount)
        if let channel = buf.floatChannelData?[0] {
            for i in 0..<frameCount {
                channel[i] = 0.1 * sin(2.0 * .pi * Float(i) / 48.0)
            }
        }
        try file.write(from: buf)
    }

    private func assertError(_ block: () throws -> Void,
                              _ matcher: (PackValidationError) -> Bool) {
        do {
            try block()
            XCTFail("Expected a PackValidationError but no error was thrown")
        } catch let e as PackValidationError {
            XCTAssertTrue(matcher(e), "Unexpected error case: \(e)")
        } catch {
            XCTFail("Expected PackValidationError but got: \(error)")
        }
    }
}
