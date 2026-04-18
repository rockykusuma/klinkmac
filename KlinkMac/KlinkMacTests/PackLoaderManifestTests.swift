// Unit tests for PackLoader manifest validation — path traversal, format checks, symlinks.
import XCTest
@testable import KlinkMac

final class PackLoaderManifestTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Helpers

    private func writeManifest(_ json: String) throws {
        try json.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("manifest.json"))
    }

    private func writeDummyFile(_ name: String) throws {
        // loadAndValidateManifest checks existence only — no audio content needed.
        try Data().write(to: tmpDir.appendingPathComponent(name))
    }

    private func assertError(_ block: () throws -> Void,
                              _ matcher: (PackValidationError) -> Bool,
                              _ label: String = "") {
        do {
            try block()
            XCTFail("Expected a PackValidationError but no error was thrown (\(label))")
        } catch let e as PackValidationError {
            XCTAssertTrue(matcher(e), "Unexpected error case: \(e). (\(label))")
        } catch {
            XCTFail("Expected PackValidationError but got: \(error) (\(label))")
        }
    }

    // MARK: - Tests

    func testMissingManifestFile() {
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .missingManifest = $0 { return true }; return false
        }
    }

    func testUnsupportedFormatVersion() throws {
        try writeManifest("""
        {"formatVersion":999,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"k.wav"}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .unsupportedFormatVersion(999) = $0 { return true }; return false
        }
    }

    func testEmptyIDRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"k.wav"}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .missingRequiredField("id") = $0 { return true }; return false
        }
    }

    func testInvalidIDCharactersRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"UPPERCASE_BAD!","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"k.wav"}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .malformedManifest = $0 { return true }; return false
        }
    }

    func testMissingDefaultDownRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .missingRequiredField("defaults.down") = $0 { return true }; return false
        }
    }

    func testDotDotPathTraversalRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"../secret.wav"}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .pathTraversalAttempt = $0 { return true }; return false
        }
    }

    func testAbsolutePathRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"/etc/passwd"}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .pathTraversalAttempt = $0 { return true }; return false
        }
    }

    func testSymlinkEscapeRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"link.wav"}}
        """)
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent("link.wav"),
            withDestinationURL: URL(fileURLWithPath: "/etc/passwd")
        )
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .pathTraversalAttempt = $0 { return true }; return false
        }
    }

    func testMissingAudioFileRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"nonexistent.wav"}}
        """)
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .missingAudioFile("nonexistent.wav") = $0 { return true }; return false
        }
    }

    func testPerKeyMappingPathTraversalRejected() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.p","name":"T","author":"T",
         "version":"1.0","defaults":{"down":"default.wav"},
         "keys":{"36":{"down":"../escape.wav"}}}
        """)
        try writeDummyFile("default.wav")
        assertError({ try PackLoader.loadAndValidateManifest(at: self.tmpDir) }) {
            if case .pathTraversalAttempt = $0 { return true }; return false
        }
    }

    func testValidManifestSucceeds() throws {
        try writeManifest("""
        {"formatVersion":1,"id":"com.test.valid","name":"Valid Pack","author":"Tester",
         "version":"1.0.0","defaults":{"down":"key-down.wav","up":"key-up.wav","gain":1.0}}
        """)
        try writeDummyFile("key-down.wav")
        try writeDummyFile("key-up.wav")
        let manifest = try PackLoader.loadAndValidateManifest(at: tmpDir)
        XCTAssertEqual(manifest.id, "com.test.valid")
        XCTAssertEqual(manifest.name, "Valid Pack")
        XCTAssertEqual(manifest.defaults.down, "key-down.wav")
        XCTAssertEqual(manifest.defaults.up, "key-up.wav")
    }
}
