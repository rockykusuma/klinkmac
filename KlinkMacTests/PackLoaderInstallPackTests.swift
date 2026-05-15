// Smoke tests for PackLoader.installPack — ZIP validation, manifest checks, install + replace.
import AVFoundation
import XCTest
@testable import KlinkMac

final class PackLoaderInstallPackTests: XCTestCase {

    private var workDir: URL!
    private var installedPackIDs: [String] = []

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        installedPackIDs = []
    }

    override func tearDownWithError() throws {
        // Clean up anything we installed under the real user packs directory.
        let userPacks = try? PackLoader.userPacksDirectory()
        for id in installedPackIDs {
            if let dir = userPacks?.appendingPathComponent(id) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - ZIP magic-byte validation

    func testRejectsFileWithoutZipMagic() throws {
        let fakeZip = workDir.appendingPathComponent("not-a-zip.klinkpack")
        try Data("this is plain text, not a zip".utf8).write(to: fakeZip)

        assertError({ _ = try PackLoader.installPack(zipURL: fakeZip) }) {
            if case .malformedManifest = $0 { return true }
            return false
        }
    }

    func testRejectsShortFile() throws {
        // < 4 bytes — fails the magic byte length check.
        let tiny = workDir.appendingPathComponent("tiny.klinkpack")
        try Data([0x50, 0x4B]).write(to: tiny)

        assertError({ _ = try PackLoader.installPack(zipURL: tiny) }) {
            if case .malformedManifest = $0 { return true }
            return false
        }
    }

    // MARK: - Content validation

    func testRejectsZipWithoutManifest() throws {
        let payloadDir = workDir.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: payloadDir.appendingPathComponent("random.txt"))
        let zipURL = try makeZip(from: payloadDir, named: "no-manifest.klinkpack")

        assertError({ _ = try PackLoader.installPack(zipURL: zipURL) }) {
            if case .missingManifest = $0 { return true }
            return false
        }
    }

    // MARK: - Happy path

    func testInstallsValidPackAtRoot() throws {
        let packID = "com.test.install.\(UUID().uuidString.lowercased().prefix(8))"
        let packDir = try makeValidPackDir(id: String(packID))
        let zipURL = try makeZip(from: packDir, named: "valid-root.klinkpack")

        let installedURL = try PackLoader.installPack(zipURL: zipURL)
        installedPackIDs.append(String(packID))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installedURL.appendingPathComponent("manifest.json").path
        ))
        XCTAssertEqual(installedURL.lastPathComponent, String(packID))
    }

    func testInstallsValidPackNestedInSubdirectory() throws {
        let packID = "com.test.install.\(UUID().uuidString.lowercased().prefix(8))"
        let outer = workDir.appendingPathComponent("outer", isDirectory: true)
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        // Real pack lives one level deeper — exercises locatePackRoot.
        let nested = try makeValidPackDir(id: String(packID), inside: outer.appendingPathComponent("nested"))
        _ = nested
        let zipURL = try makeZip(from: outer, named: "valid-nested.klinkpack")

        let installedURL = try PackLoader.installPack(zipURL: zipURL)
        installedPackIDs.append(String(packID))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installedURL.appendingPathComponent("manifest.json").path
        ))
    }

    func testReinstallReplacesExistingPack() throws {
        let packID = "com.test.install.\(UUID().uuidString.lowercased().prefix(8))"
        let firstDir = try makeValidPackDir(id: String(packID), authorName: "Original")
        let zipA = try makeZip(from: firstDir, named: "first.klinkpack")
        _ = try PackLoader.installPack(zipURL: zipA)
        installedPackIDs.append(String(packID))

        // Same ID, different author — second install must wipe and replace.
        let secondDir = try makeValidPackDir(id: String(packID), authorName: "Updated",
                                             into: workDir.appendingPathComponent("v2"))
        let zipB = try makeZip(from: secondDir, named: "second.klinkpack")
        let installedURL = try PackLoader.installPack(zipURL: zipB)

        let manifest = try PackLoader.loadAndValidateManifest(at: installedURL)
        XCTAssertEqual(manifest.author, "Updated",
                       "Second install should overwrite the first pack on disk")
    }

    // MARK: - Helpers

    private func makeValidPackDir(id: String,
                                   authorName: String = "Tester",
                                   into parent: URL? = nil) throws -> URL {
        return try makeValidPackDir(id: id, authorName: authorName,
                                    inside: parent ?? workDir.appendingPathComponent("pack-\(UUID().uuidString)"))
    }

    private func makeValidPackDir(id: String,
                                   authorName: String = "Tester",
                                   inside dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        {"formatVersion":1,"id":"\(id)","name":"Test Pack","author":"\(authorName)",
         "version":"1.0","defaults":{"down":"d.wav"}}
        """
        try manifest.data(using: .utf8)!
            .write(to: dir.appendingPathComponent("manifest.json"))
        try writeShortWAV(to: dir.appendingPathComponent("d.wav"))
        return dir
    }

    private func writeShortWAV(to url: URL) throws {
        let sr: Double = 48000
        let frames = 480 // 10ms
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        if let ch = buf.floatChannelData?[0] {
            for i in 0..<frames { ch[i] = 0.1 }
        }
        try file.write(from: buf)
    }

    private func makeZip(from sourceDir: URL, named filename: String) throws -> URL {
        let zipURL = workDir.appendingPathComponent(filename)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = sourceDir
        proc.arguments = ["-rq", zipURL.path, "."]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, "zip helper failed (\(filename))")
        return zipURL
    }

    private func assertError(_ block: () throws -> Void,
                              _ matcher: (PackValidationError) -> Bool) {
        do {
            try block()
            XCTFail("Expected PackValidationError but no error thrown")
        } catch let e as PackValidationError {
            XCTAssertTrue(matcher(e), "Unexpected error case: \(e)")
        } catch {
            XCTFail("Expected PackValidationError but got: \(error)")
        }
    }
}
