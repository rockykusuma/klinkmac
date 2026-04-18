// Loads sound packs from bundled resources or user's Application Support directory.
import AVFoundation
import Foundation
import os

public final class PackLoader {
    // MARK: - Public entry points

    /// Load a bundled pack by folder name (e.g. "cherry-mx-blue").
    public static func loadBundled(named folderName: String, sampleRate: Double = 48000) throws -> SampleBank {
        guard let resourcesURL = Bundle.main.resourceURL else {
            throw PackValidationError.missingManifest
        }
        let url = resourcesURL.appendingPathComponent("Packs/\(folderName)")
        return try loadFromDisk(at: url, sampleRate: sampleRate)
    }

    /// Load a pack from a directory URL (already unzipped). Validates the manifest.
    public static func loadFromDisk(at packURL: URL, sampleRate: Double = 48000) throws -> SampleBank {
        let manifest = try loadAndValidateManifest(at: packURL)
        return try decodeSamples(manifest: manifest, packURL: packURL, sampleRate: sampleRate)
    }

    // MARK: - Installation

    /// Installs a .klinkpack (ZIP) file into the user packs directory.
    /// Returns the installed pack's directory URL.
    public static func installPack(zipURL: URL) throws -> URL {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // Verify ZIP magic bytes before spawning a subprocess.
        guard let handle = FileHandle(forReadingAtPath: zipURL.path) else {
            throw PackValidationError.malformedManifest("Cannot open file for reading.")
        }
        let magic = handle.readData(ofLength: 4)
        handle.closeFile()
        guard magic.count == 4,
              magic[0] == 0x50, magic[1] == 0x4B,
              magic[2] == 0x03, magic[3] == 0x04 else {
            throw PackValidationError.malformedManifest("File is not a valid ZIP archive.")
        }

        // Unzip using system tool — no external dependencies needed.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", zipURL.path, "-d", tmpDir.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw PackValidationError.malformedManifest("ZIP extraction failed (exit code \(proc.terminationStatus)).")
        }

        // Locate the pack root — either a subdirectory or the tmp dir itself.
        let packRoot = try locatePackRoot(in: tmpDir)

        // Validate the pack fully before touching the user's directory.
        let manifest = try loadAndValidateManifest(at: packRoot)

        // Enforce total size limit (100 MB uncompressed).
        let totalBytes = try directorySize(packRoot)
        if totalBytes > 100_000_000 {
            throw PackValidationError.packTooLarge(totalBytes)
        }

        // Install to user packs directory, keyed by pack ID.
        let destDir = try userPacksDirectory().appendingPathComponent(manifest.id)
        if fm.fileExists(atPath: destDir.path) {
            try fm.removeItem(at: destDir)
        }
        try fm.copyItem(at: packRoot, to: destDir)

        logger.info("Installed pack '\(manifest.id)' at \(destDir.path)")
        return destDir
    }

    // MARK: - Pack discovery

    /// Returns the user packs directory, creating it if needed.
    public static func userPacksDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("com.klinkmac.KlinkMac/Packs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns manifests for all user-installed packs (skips unreadable entries).
    public static func discoverUserPacks() -> [(manifest: PackManifest, url: URL)] {
        guard let dir = try? userPacksDirectory() else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []
        return entries.compactMap { url in
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else { return nil }
            guard let manifest = try? loadAndValidateManifest(at: url) else { return nil }
            return (manifest, url)
        }
    }

    // MARK: - Manifest loading + validation

    public static func loadAndValidateManifest(at packURL: URL) throws -> PackManifest {
        let manifestURL = packURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PackValidationError.missingManifest
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest: PackManifest
        do {
            manifest = try JSONDecoder().decode(PackManifest.self, from: data)
        } catch {
            throw PackValidationError.malformedManifest(error.localizedDescription)
        }
        guard manifest.formatVersion <= supportedPackFormatVersion else {
            throw PackValidationError.unsupportedFormatVersion(manifest.formatVersion)
        }
        try validateManifestIdentity(manifest)
        try validateFilePaths(collectReferencedPaths(from: manifest), in: packURL)
        return manifest
    }

    private static func validateManifestIdentity(_ manifest: PackManifest) throws {
        guard !manifest.id.isEmpty else { throw PackValidationError.missingRequiredField("id") }
        guard manifest.id.range(of: #"^[a-z0-9.\-]{1,128}$"#, options: .regularExpression) != nil else {
            throw PackValidationError.malformedManifest("id '\(manifest.id)' contains invalid characters.")
        }
        guard !(manifest.defaults.down ?? "").isEmpty else {
            throw PackValidationError.missingRequiredField("defaults.down")
        }
    }

    private static func collectReferencedPaths(from manifest: PackManifest) -> [String] {
        var paths: [String] = []
        if let d = manifest.defaults.down { paths.append(d) }
        if let u = manifest.defaults.up { paths.append(u) }
        for mapping in manifest.keys?.values ?? [:].values {
            if let d = mapping.down { paths.append(d) }
            if let u = mapping.up { paths.append(u) }
        }
        return paths
    }

    private static func validateFilePaths(_ paths: [String], in packURL: URL) throws {
        let packResolved = packURL.resolvingSymlinksInPath().standardized
        for path in paths {
            guard !path.contains(".."), !path.hasPrefix("/") else {
                throw PackValidationError.pathTraversalAttempt(path)
            }
            let fileURL = packURL.appendingPathComponent(path)
            // Resolve symlinks so a symlink pointing outside the pack directory is caught.
            let resolved = fileURL.resolvingSymlinksInPath().standardized
            guard resolved.path.hasPrefix(packResolved.path + "/") else {
                throw PackValidationError.pathTraversalAttempt(path)
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw PackValidationError.missingAudioFile(path)
            }
        }
    }

    // MARK: - Sample decoding

    private static func decodeSamples(manifest: PackManifest,
                                      packURL: URL,
                                      sampleRate: Double) throws -> SampleBank {
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        var allocations: [UnsafeMutablePointer<Float>] = []

        func wav(_ name: String, gain: Float = 1.0) throws -> (UnsafePointer<Float>, Int) {
            try decodeWAV(name, packURL: packURL, fmt: targetFormat, gain: gain, into: &allocations)
        }

        let defaultGain = manifest.defaults.gain ?? 1.0
        let (ddPtr, ddCount) = try wav(manifest.defaults.down!, gain: defaultGain)
        var duPtr: UnsafePointer<Float>?
        var duCount = 0
        if let upFile = manifest.defaults.up {
            let (p, c) = try wav(upFile, gain: defaultGain)
            duPtr = p; duCount = c
        }

        let defaultSample = PackSample(downFrames: ddPtr, downFrameCount: ddCount,
                                       upFrames: duPtr, upFrameCount: duCount, channelCount: 1)

        var samples: [UInt16: PackSample] = [:]
        for (kcStr, mapping) in manifest.keys ?? [:] {
            guard let kc = UInt16(kcStr) else { continue }
            let gain = mapping.gain ?? 1.0
            guard let downFile = mapping.down ?? manifest.defaults.down else { continue }
            let (dPtr, dCount) = try wav(downFile, gain: gain)
            var uPtr: UnsafePointer<Float>?
            var uCount = 0
            let upFile = mapping.up ?? (mapping.down == nil ? manifest.defaults.up : nil)
            if let f = upFile {
                let (p, c) = try wav(f, gain: gain)
                uPtr = p; uCount = c
            }
            samples[kc] = PackSample(downFrames: dPtr, downFrameCount: dCount,
                                     upFrames: uPtr, upFrameCount: uCount, channelCount: 1)
        }

        return SampleBank(name: manifest.name, defaultSample: defaultSample,
                          keySamples: samples, allocations: allocations)
    }

    // Decodes a WAV file to a raw Float buffer at the target sample rate and gain.
    // Appends the allocation to `allocations` so the caller retains ownership.
    private static func decodeWAV(
        _ filename: String,
        packURL: URL,
        fmt targetFormat: AVAudioFormat,
        gain: Float,
        into allocations: inout [UnsafeMutablePointer<Float>]
    ) throws -> (UnsafePointer<Float>, Int) {
        let file = try AVAudioFile(forReading: packURL.appendingPathComponent(filename))

        let durationMs = Int(Double(file.length) / file.fileFormat.sampleRate * 1000)
        if durationMs > 500 {
            throw PackValidationError.audioDurationTooLong(file: filename, durationMs: durationMs)
        }

        let srcFmt = file.processingFormat
        let srcFrames = AVAudioFrameCount(file.length)
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: srcFrames) else {
            throw PackValidationError.malformedManifest("Could not allocate buffer for '\(filename)'.")
        }
        try file.read(into: srcBuf)

        let dstCapacity = AVAudioFrameCount(
            Double(srcFrames) * targetFormat.sampleRate / srcFmt.sampleRate
        ) + 16
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: dstCapacity),
              let converter = AVAudioConverter(from: srcFmt, to: targetFormat) else {
            throw PackValidationError.malformedManifest("Format conversion setup failed for '\(filename)'.")
        }

        var convError: NSError?
        converter.convert(to: dstBuf, error: &convError) { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuf
        }
        if let e = convError { throw e }

        let count = Int(dstBuf.frameLength)
        let ptr = UnsafeMutablePointer<Float>.allocate(capacity: count)
        if let ch = dstBuf.floatChannelData?[0] {
            if gain == 1.0 {
                ptr.initialize(from: ch, count: count)
            } else {
                for i in 0..<count { ptr[i] = ch[i] * gain }
            }
        }
        allocations.append(ptr)
        return (UnsafePointer(ptr), count)
    }

    // MARK: - Helpers

    private static func locatePackRoot(in dir: URL) throws -> URL {
        let fm = FileManager.default
        // If manifest.json is directly in dir, use dir.
        if fm.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) {
            return dir
        }
        // Otherwise look for a single subdirectory.
        let entries = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        let subdirs = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        if let sub = subdirs.first,
           fm.fileExists(atPath: sub.appendingPathComponent("manifest.json").path) {
            return sub
        }
        throw PackValidationError.missingManifest
    }

    private static func directorySize(_ url: URL) throws -> Int64 {
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private static let logger = Logger(subsystem: "com.klinkmac", category: "PackLoader")
}
