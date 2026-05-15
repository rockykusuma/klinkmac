// Unit tests for velocity-aware sound modulation.
import XCTest
@testable import KlinkMac

final class VelocityModulationTests: XCTestCase {

    // mach_absolute_time ticks-per-second; we use an arbitrary but consistent conversion.
    // Tests use a fake timebase where 1 tick == 1 microsecond (machToSec = 1e-6).
    private let machToSec: Double = 1e-6

    private func makeState(avgIKI: Double = 0.25, lastTs: UInt64 = 0)
        -> UnsafeMutablePointer<VelocityState> {
        let p = UnsafeMutablePointer<VelocityState>.allocate(capacity: 1)
        p.initialize(to: VelocityState(avgIKI: avgIKI, lastDownTimestamp: lastTs))
        return p
    }

    private func event(ts: UInt64, down: Bool = true, keycode: UInt16 = 1) -> KeyEvent {
        KeyEvent(keycode: keycode, isDown: down, timestamp: ts)
    }

    // MARK: - Basic modulation mapping

    func testSlowTypingProducesFullGainAndPitch() {
        // Seed avgIKI to a slow typing value (0.5s = ~24 WPM) — above the 0.40s cap, so intensity 1.
        let state = makeState(avgIKI: 0.5, lastTs: 1_000_000)
        defer { state.deinitialize(count: 1); state.deallocate() }

        // Second keypress 500ms later — keeps avgIKI high.
        let mod = velocityModulation(for: event(ts: 1_500_000),
                                     state: state,
                                     machToSec: machToSec)

        XCTAssertEqual(mod.gain, 1.0, accuracy: 0.01)
        XCTAssertEqual(mod.pitchBias, 0.94, accuracy: 0.01)
    }

    func testFastTypingProducesReducedGainAndHigherPitch() {
        // Seed avgIKI to fast typing (50ms = 240 WPM) — well below 0.08s, so intensity 0.
        let state = makeState(avgIKI: 0.05, lastTs: 1_000_000)
        defer { state.deinitialize(count: 1); state.deallocate() }

        let mod = velocityModulation(for: event(ts: 1_050_000),
                                     state: state,
                                     machToSec: machToSec)

        XCTAssertEqual(mod.gain, 0.55, accuracy: 0.01)
        XCTAssertEqual(mod.pitchBias, 1.06, accuracy: 0.01)
    }

    // MARK: - EWMA behavior

    func testFirstEventDoesNotUpdateAvgIKI() {
        // When lastDownTimestamp == 0 (fresh state), no IKI can be computed.
        let state = makeState(avgIKI: 0.25, lastTs: 0)
        defer { state.deinitialize(count: 1); state.deallocate() }

        _ = velocityModulation(for: event(ts: 999_999),
                               state: state,
                               machToSec: machToSec)

        // avgIKI unchanged; lastDownTimestamp now stamped.
        XCTAssertEqual(state.pointee.avgIKI, 0.25, accuracy: 0.001)
        XCTAssertEqual(state.pointee.lastDownTimestamp, 999_999)
    }

    func testEWMAConvergesTowardNewIKI() {
        // Start at avgIKI 0.25, feed 5 events 100ms apart → avgIKI should trend toward 0.10.
        let state = makeState(avgIKI: 0.25, lastTs: 0)
        defer { state.deinitialize(count: 1); state.deallocate() }

        var ts: UInt64 = 0
        // First event just stamps the timestamp.
        _ = velocityModulation(for: event(ts: ts), state: state, machToSec: machToSec)

        for _ in 0..<5 {
            ts += 100_000   // 100ms later (at 1 tick = 1µs)
            _ = velocityModulation(for: event(ts: ts), state: state, machToSec: machToSec)
        }

        // After 5 events at 100ms IKI, avgIKI should be between the initial 0.25 and target 0.10,
        // closer to target.
        XCTAssertLessThan(state.pointee.avgIKI, 0.20)
        XCTAssertGreaterThan(state.pointee.avgIKI, 0.10)
    }

    // MARK: - Output bounds

    func testGainAndPitchStayWithinBounds() {
        // Exhaustive: sweep avgIKI from 0 to 1 second, gain/pitch must remain in expected ranges.
        let state = makeState(avgIKI: 0, lastTs: 1_000_000)
        defer { state.deinitialize(count: 1); state.deallocate() }

        for iki in stride(from: 0.0, through: 1.0, by: 0.01) {
            state.pointee.avgIKI = iki
            state.pointee.lastDownTimestamp = 1_000_000   // reset so EWMA updates once
            let mod = velocityModulation(for: event(ts: 1_000_000 + UInt64(iki * 1_000_000)),
                                         state: state,
                                         machToSec: machToSec)
            XCTAssertGreaterThanOrEqual(mod.gain, 0.55 - 0.001)
            XCTAssertLessThanOrEqual(mod.gain, 1.0 + 0.001)
            XCTAssertGreaterThanOrEqual(mod.pitchBias, 0.94 - 0.001)
            XCTAssertLessThanOrEqual(mod.pitchBias, 1.06 + 0.001)
        }
    }
}
