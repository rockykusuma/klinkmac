// SPSC EventQueue unit tests — basic correctness + two-thread contention.
import Atomics
import XCTest
@testable import KlinkMac

final class EventQueueTests: XCTestCase {

    func testPushPopRoundtrip() {
        let q = EventQueue(capacity: 4)
        let e = KeyEvent(keycode: 42, isDown: true, timestamp: 100)
        XCTAssertTrue(q.push(e))
        let out = q.pop()
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.keycode, 42)
        XCTAssertEqual(out?.isDown, true)
        XCTAssertEqual(out?.timestamp, 100)
    }

    func testEmptyReturnsNil() {
        let q = EventQueue(capacity: 4)
        XCTAssertNil(q.pop())
    }

    func testFIFOOrdering() {
        let q = EventQueue(capacity: 8)
        for i in 0..<5 {
            _ = q.push(KeyEvent(keycode: UInt16(i), isDown: true, timestamp: 0))
        }
        for i in 0..<5 {
            XCTAssertEqual(q.pop()?.keycode, UInt16(i))
        }
        XCTAssertNil(q.pop())
    }

    func testDropsWhenFull() {
        let q = EventQueue(capacity: 4)
        for i in 0..<4 {
            XCTAssertTrue(q.push(KeyEvent(keycode: UInt16(i), isDown: true, timestamp: 0)))
        }
        XCTAssertFalse(q.push(KeyEvent(keycode: 99, isDown: false, timestamp: 0)))
    }

    func testCapacityRoundsUpToPowerOfTwo() {
        // capacity=5 → rounds to 8; must accept exactly 8 before dropping.
        let q = EventQueue(capacity: 5)
        for i in 0..<8 {
            XCTAssertTrue(q.push(KeyEvent(keycode: UInt16(i), isDown: false, timestamp: 0)))
        }
        XCTAssertFalse(q.push(KeyEvent(keycode: 99, isDown: false, timestamp: 0)))
    }

    func testWrapAround() {
        let q = EventQueue(capacity: 4)
        // Fill, drain, fill again — exercises index wrap-around.
        for pass in 0..<3 {
            for i in 0..<4 {
                _ = q.push(KeyEvent(keycode: UInt16(pass * 10 + i), isDown: false, timestamp: 0))
            }
            for i in 0..<4 {
                XCTAssertEqual(q.pop()?.keycode, UInt16(pass * 10 + i))
            }
        }
    }

    // Two real threads: producer pushes N events, consumer pops them.
    // Queue capacity > N so there are no drops; every produced event must be consumed.
    func testConcurrentProducerConsumer() {
        let eventCount = 1_000
        let q = EventQueue(capacity: 2048)
        let consumed = ManagedAtomic<Int>(0)
        let done = expectation(description: "consumer done")

        let producer = Thread {
            for i in 0..<eventCount {
                _ = q.push(KeyEvent(keycode: UInt16(i & 0xFF),
                                    isDown: i.isMultiple(of: 2),
                                    timestamp: UInt64(i)))
            }
        }

        let consumer = Thread {
            var n = 0
            while n < eventCount {
                if q.pop() != nil { n += 1 }
            }
            consumed.store(n, ordering: .releasing)
            done.fulfill()
        }

        producer.start()
        consumer.start()
        waitForExpectations(timeout: 10)
        XCTAssertEqual(consumed.load(ordering: .acquiring), eventCount)
    }

    // Consumer starts first; ensures it spins correctly waiting for producer.
    func testConsumerStartsBeforeProducer() {
        let q = EventQueue(capacity: 64)
        let received = ManagedAtomic<Int>(0)
        let done = expectation(description: "consumer done")

        let consumer = Thread {
            var n = 0
            while n < 10 {
                if q.pop() != nil { n += 1 }
            }
            received.store(n, ordering: .releasing)
            done.fulfill()
        }
        consumer.start()
        // Brief sleep so consumer is spinning before producer starts.
        Thread.sleep(forTimeInterval: 0.01)

        let producer = Thread {
            for i in 0..<10 {
                _ = q.push(KeyEvent(keycode: UInt16(i), isDown: true, timestamp: 0))
            }
        }
        producer.start()

        waitForExpectations(timeout: 5)
        XCTAssertEqual(received.load(ordering: .acquiring), 10)
    }
}
