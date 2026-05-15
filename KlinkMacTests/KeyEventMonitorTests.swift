// Tests for KeyEventMonitor failure path and safe lifecycle behavior.
// CGEvent.tapCreate returns nil in sandboxed/no-permission test environments,
// exercising the tapCreationFailed branch that coverage showed uncovered.
import XCTest
@testable import KlinkMac

final class KeyEventMonitorTests: XCTestCase {

    // MARK: - Failure path

    func testStartThrowsTapCreationFailedWithoutPermission() {
        let monitor = KeyEventMonitor()
        XCTAssertThrowsError(try monitor.start()) { error in
            guard let e = error as? KeyEventMonitor.MonitorError,
                  case .tapCreationFailed = e else {
                XCTFail("Expected MonitorError.tapCreationFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Idempotency

    func testStartIsIdempotentWhenTapAlreadyCreated() throws {
        // In test env tap creation fails, so the first call throws and tap stays nil.
        // Calling start() again must not double-release selfUnmanaged or crash.
        let monitor = KeyEventMonitor()
        XCTAssertThrowsError(try monitor.start())
        XCTAssertThrowsError(try monitor.start())
    }

    // MARK: - Safe lifecycle

    func testStopBeforeStartDoesNotCrash() {
        let monitor = KeyEventMonitor()
        monitor.stop()  // should be a no-op, not a crash
    }

    func testStopAfterFailedStartDoesNotCrash() {
        let monitor = KeyEventMonitor()
        XCTAssertThrowsError(try monitor.start())
        monitor.stop()
    }

    func testDeinitAfterFailedStartDoesNotCrash() {
        var monitor: KeyEventMonitor? = KeyEventMonitor()
        XCTAssertThrowsError(try monitor!.start())
        monitor = nil  // triggers deinit → stop()
    }

    // MARK: - onEvent handler

    func testOnEventHandlerIsNotCalledAfterFailedStart() throws {
        let monitor = KeyEventMonitor()
        var called = false
        monitor.onEvent = { _ in called = true }
        XCTAssertThrowsError(try monitor.start())
        // No tap, so handler must never fire
        XCTAssertFalse(called)
    }

    func testOnEventHandlerCanBeSetBeforeStart() {
        let monitor = KeyEventMonitor()
        monitor.onEvent = { _ in }  // should not crash
        XCTAssertThrowsError(try monitor.start())
    }
}
