// Immutable PCM sample bank — flat 256-slot lookup table for O(1) RT-safe keycode access.
import Foundation

public struct PackSample {
    public let downFrames: UnsafePointer<Float>
    public let downFrameCount: Int
    public let upFrames: UnsafePointer<Float>?
    public let upFrameCount: Int
    public let channelCount: Int
}

// @unchecked Sendable: immutable after construction, raw pointers owned exclusively.
public final class SampleBank: @unchecked Sendable {
    public let name: String
    public let defaultSample: PackSample

    // 256-slot flat table — pre-filled with defaultSample, overridden per keycode.
    // Direct pointer indexing on the audio thread: no dictionary, no ARC.
    private let table: UnsafeMutablePointer<PackSample>
    private static let tableSize = 256
    private let allocations: [UnsafeMutablePointer<Float>]

    public init(name: String,
                defaultSample: PackSample,
                keySamples: [UInt16: PackSample],
                allocations: [UnsafeMutablePointer<Float>]) {
        self.name = name
        self.defaultSample = defaultSample
        self.allocations = allocations
        table = UnsafeMutablePointer<PackSample>.allocate(capacity: Self.tableSize)
        table.initialize(repeating: defaultSample, count: Self.tableSize)
        for (kc, s) in keySamples where Int(kc) < Self.tableSize {
            table[Int(kc)] = s
        }
    }

    /// RT-safe: direct table read, no allocation, no ARC.
    @inline(__always)
    public func sample(for keycode: UInt16) -> PackSample {
        table[min(Int(keycode), Self.tableSize - 1)]
    }

    deinit {
        table.deallocate()
        for ptr in allocations { ptr.deallocate() }
    }
}
