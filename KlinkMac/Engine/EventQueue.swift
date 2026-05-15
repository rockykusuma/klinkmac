// Lock-free SPSC ring buffer: event tap thread produces, audio render thread consumes.
import Atomics
import Foundation
import os

// @unchecked Sendable: thread-safety guaranteed by SPSC contract + atomic indices.
public final class EventQueue: @unchecked Sendable {
    // Raw pointer needs nonisolated(unsafe) — accessed from tap + audio threads via SPSC contract.
    nonisolated(unsafe) private let buffer: UnsafeMutablePointer<KeyEvent>
    private let mask: UInt32
    private let capacity: UInt32
    private let writeIndex = ManagedAtomic<UInt32>(0)
    private let readIndex  = ManagedAtomic<UInt32>(0)
    private let logger = Logger(subsystem: "com.klinkmac", category: "EventQueue")

    public init(capacity: Int = 256) {
        var cap = 1
        while cap < capacity { cap <<= 1 }
        self.capacity = UInt32(cap)
        self.mask = UInt32(cap - 1)
        buffer = UnsafeMutablePointer<KeyEvent>.allocate(capacity: cap)
        buffer.initialize(repeating: KeyEvent(keycode: 0, isDown: false, timestamp: 0), count: cap)
    }

    /// Producer — called from event tap thread only.
    @discardableResult
    nonisolated public func push(_ event: KeyEvent) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read  = readIndex.load(ordering: .acquiring)
        guard write &- read < capacity else {
            logger.debug("EventQueue full — dropping keystroke event")
            return false
        }
        buffer[Int(write & mask)] = event
        writeIndex.store(write &+ 1, ordering: .releasing)
        return true
    }

    /// Consumer — called from audio render thread only.
    nonisolated public func pop() -> KeyEvent? {
        let read  = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read != write else { return nil }
        let event = buffer[Int(read & mask)]
        readIndex.store(read &+ 1, ordering: .releasing)
        return event
    }

    /// No-op — retained for call-site compatibility. Thread assertions removed because
    /// CoreAudio legitimately changes the I/O thread on device switch; correctness is
    /// guaranteed by atomic indices, not thread identity checks.
    public func resetThreadAssertions() {}

    deinit { buffer.deallocate() }
}
