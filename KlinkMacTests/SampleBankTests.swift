// Unit tests for the 256-slot flat-table SampleBank.
import XCTest
@testable import KlinkMac

final class SampleBankTests: XCTestCase {

    // MARK: - Helpers

    /// Allocates a float buffer and returns both the PackSample (owns the pointer via the
    /// bank's allocations array) and the raw mutable pointer to pass to allocations.
    private func makeSample(value: Float, frames: Int) -> (PackSample, UnsafeMutablePointer<Float>) {
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        buf.initialize(repeating: value, count: frames)
        return (PackSample(downFrames: UnsafePointer(buf), downFrameCount: frames,
                           upFrames: nil, upFrameCount: 0, channelCount: 1), buf)
    }

    // MARK: - Tests

    func testUnmappedKeycodeReturnsDefault() {
        let (def, buf) = makeSample(value: 1.0, frames: 4)
        let bank = SampleBank(name: "Test", defaultSample: def, keySamples: [:], allocations: [buf])
        let s = bank.sample(for: 50)
        XCTAssertEqual(s.downFrameCount, 4)
        XCTAssertEqual(s.downFrames[0], 1.0)
    }

    func testMappedKeycodeReturnsSpecificSample() {
        let (def, defBuf) = makeSample(value: 0.0, frames: 2)
        let (specific, specBuf) = makeSample(value: 2.0, frames: 8)
        let bank = SampleBank(name: "Test", defaultSample: def,
                              keySamples: [42: specific],
                              allocations: [defBuf, specBuf])

        XCTAssertEqual(bank.sample(for: 42).downFrameCount, 8)
        XCTAssertEqual(bank.sample(for: 42).downFrames[0], 2.0)
        XCTAssertEqual(bank.sample(for: 99).downFrameCount, 2)   // unmapped → default
    }

    func testKeycodeZeroMappable() {
        let (def, defBuf) = makeSample(value: 1.0, frames: 4)
        let (s0, buf0) = makeSample(value: 9.0, frames: 4)
        let bank = SampleBank(name: "Test", defaultSample: def,
                              keySamples: [0: s0],
                              allocations: [defBuf, buf0])

        XCTAssertEqual(bank.sample(for: 0).downFrames[0], 9.0)
        XCTAssertEqual(bank.sample(for: 1).downFrames[0], 1.0)  // unmapped → default
    }

    func testKeycode255Accessible() {
        let (def, defBuf) = makeSample(value: 0.0, frames: 2)
        let (s255, buf255) = makeSample(value: 5.0, frames: 2)
        let bank = SampleBank(name: "Test", defaultSample: def,
                              keySamples: [255: s255],
                              allocations: [defBuf, buf255])

        XCTAssertEqual(bank.sample(for: 255).downFrames[0], 5.0)
    }

    func testKeycodeAbove255ClampedToTableMax() {
        let (def, buf) = makeSample(value: 3.0, frames: 2)
        let bank = SampleBank(name: "Test", defaultSample: def,
                              keySamples: [:], allocations: [buf])
        // UInt16(300) clamped to 255 → default sample at index 255
        XCTAssertEqual(bank.sample(for: 300).downFrames[0], 3.0)
    }

    func testAllUnmappedSlotsUseDefault() {
        let (def, buf) = makeSample(value: 7.0, frames: 1)
        let bank = SampleBank(name: "Test", defaultSample: def,
                              keySamples: [:], allocations: [buf])
        for kc: UInt16 in 0...255 {
            XCTAssertEqual(bank.sample(for: kc).downFrames[0], 7.0,
                           "Slot \(kc) should return default sample")
        }
    }
}
