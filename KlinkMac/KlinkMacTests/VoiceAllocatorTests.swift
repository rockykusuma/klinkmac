// Unit tests for the fixed-pool voice allocator.
import XCTest
@testable import KlinkMac

final class VoiceAllocatorTests: XCTestCase {

    // MARK: - Helpers

    private func sampleBuffer(value: Float, frames: Int) -> UnsafeMutablePointer<Float> {
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        buf.initialize(repeating: value, count: frames)
        return buf
    }

    // MARK: - Tests

    func testRenderSilentWithNoActiveVoices() {
        let allocator = VoiceAllocator(poolSize: 4)
        var output = [Float](repeating: 0, count: 4)
        output.withUnsafeMutableBufferPointer { allocator.render(into: $0, frameCount: 4) }
        XCTAssertEqual(output, [0, 0, 0, 0])
    }

    func testRenderProducesNonZeroOutputAfterAllocate() {
        let allocator = VoiceAllocator(poolSize: 4)
        let buf = sampleBuffer(value: 1.0, frames: 16)
        defer { buf.deallocate() }

        allocator.allocate(samplePtr: UnsafePointer(buf), frames: 16)

        var output = [Float](repeating: 0, count: 2)
        output.withUnsafeMutableBufferPointer { allocator.render(into: $0, frameCount: 2) }
        XCTAssertGreaterThan(output[0], 0.0)
        XCTAssertGreaterThan(output[1], 0.0)
    }

    func testVoiceGoesInactiveAfterSampleEnd() {
        let allocator = VoiceAllocator(poolSize: 4)
        let buf = sampleBuffer(value: 1.0, frames: 4)
        defer { buf.deallocate() }

        allocator.allocate(samplePtr: UnsafePointer(buf), frames: 4)

        // Render past end of sample to drain the voice.
        var sink = [Float](repeating: 0, count: 32)
        sink.withUnsafeMutableBufferPointer { allocator.render(into: $0, frameCount: 32) }

        // Voice should now be inactive — next render is silent.
        var output = [Float](repeating: 0, count: 2)
        output.withUnsafeMutableBufferPointer { allocator.render(into: $0, frameCount: 2) }
        XCTAssertEqual(output[0], 0.0)
        XCTAssertEqual(output[1], 0.0)
    }

    func testVolumeZeroProducesSilentOutput() {
        let allocator = VoiceAllocator(poolSize: 4)
        allocator.volume = 0.0
        let buf = sampleBuffer(value: 1.0, frames: 8)
        defer { buf.deallocate() }

        allocator.allocate(samplePtr: UnsafePointer(buf), frames: 8)

        var output = [Float](repeating: 0, count: 2)
        output.withUnsafeMutableBufferPointer { allocator.render(into: $0, frameCount: 2) }
        XCTAssertEqual(output[0], 0.0)
        XCTAssertEqual(output[1], 0.0)
    }

    func testTwoVoicesMixAdditively() {
        // All-ones samples: interpolation = 1.0 at every position regardless of pitch ratio,
        // so two simultaneous voices should produce approximately double the output.
        let buf = sampleBuffer(value: 1.0, frames: 16)
        defer { buf.deallocate() }

        let single = VoiceAllocator(poolSize: 4)
        single.allocate(samplePtr: UnsafePointer(buf), frames: 16)

        let doubled = VoiceAllocator(poolSize: 4)
        doubled.allocate(samplePtr: UnsafePointer(buf), frames: 16)
        doubled.allocate(samplePtr: UnsafePointer(buf), frames: 16)

        var out1 = [Float](repeating: 0, count: 1)
        var out2 = [Float](repeating: 0, count: 1)
        out1.withUnsafeMutableBufferPointer { single.render(into: $0, frameCount: 1) }
        out2.withUnsafeMutableBufferPointer { doubled.render(into: $0, frameCount: 1) }

        XCTAssertGreaterThan(out2[0], out1[0] * 1.5,
                             "Two voices should produce at least 1.5× a single voice")
    }

    func testVoiceStealingDoesNotCrashOrProduceNaN() {
        let poolSize = 3
        let allocator = VoiceAllocator(poolSize: poolSize)
        let buf = sampleBuffer(value: 0.5, frames: 1000)
        defer { buf.deallocate() }

        // Fill pool then steal one slot — must not crash.
        for _ in 0..<poolSize { allocator.allocate(samplePtr: UnsafePointer(buf), frames: 1000) }
        allocator.allocate(samplePtr: UnsafePointer(buf), frames: 1000)

        var output = [Float](repeating: 0, count: 1)
        output.withUnsafeMutableBufferPointer { allocator.render(into: $0, frameCount: 1) }
        XCTAssertFalse(output[0].isNaN)
        XCTAssertFalse(output[0].isInfinite)
    }
}
