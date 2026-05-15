// Canonical on-disk format for KlinkMac sound packs — format version 1 contract.
import Foundation

// MARK: - Manifest types (must match SOUND-PACK-FORMAT.md exactly)

public struct PackManifest: Codable, Sendable {
    public let formatVersion: Int
    public let id: String
    public let name: String
    public let author: String
    public let version: String
    public let description: String?
    public let website: String?
    public let license: String?
    public let defaults: PackKeyMapping
    public let keys: [String: PackKeyMapping]?
}

public struct PackKeyMapping: Codable, Sendable {
    public let down: String?
    public let up: String?
    public let gain: Float?
}

// MARK: - Validation errors (user-facing via LocalizedError)

public enum PackValidationError: LocalizedError {
    case missingManifest
    case malformedManifest(String)
    case unsupportedFormatVersion(Int)
    case missingRequiredField(String)
    case missingAudioFile(String)
    case pathTraversalAttempt(String)
    case packTooLarge(Int64)
    case audioDurationTooLong(file: String, durationMs: Int)

    public var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Pack is missing manifest.json."
        case .malformedManifest(let detail):
            return "manifest.json is invalid: \(detail)"
        case .unsupportedFormatVersion(let v):
            return "Pack uses format version \(v). Please update KlinkMac to install this pack."
        case .missingRequiredField(let field):
            return "manifest.json is missing required field '\(field)'."
        case .missingAudioFile(let path):
            return "Pack is missing the audio file '\(path)' referenced in its manifest."
        case .pathTraversalAttempt(let path):
            return "Pack contains an invalid file path '\(path)'. Path traversal is not allowed."
        case .packTooLarge(let bytes):
            return "Pack is \(bytes / 1_048_576) MB — maximum allowed size is 100 MB."
        case .audioDurationTooLong(let file, let ms):
            return "Audio file '\(file)' is \(ms) ms — maximum is 500 ms."
        }
    }
}

// MARK: - Supported format version

public let supportedPackFormatVersion = 1
