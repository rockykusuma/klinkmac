// CGEventTap wrapper — calls handler directly on tap thread for minimum latency.
import CoreGraphics
import Foundation

public struct KeyEvent: Sendable {
    public let keycode: UInt16
    public let isDown: Bool
    public let timestamp: UInt64
}

public final class KeyEventMonitor {
    public typealias Handler = @Sendable (KeyEvent) -> Void
    /// Called on the event tap thread — do not block, do not allocate, do not ARC.
    public var onEvent: Handler?

    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var selfUnmanaged: Unmanaged<KeyEventMonitor>?

    public init() {}

    public func start() throws {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let unmanaged = Unmanaged.passRetained(self)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let m = Unmanaged<KeyEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let ts = UInt64(bitPattern: Int64(event.timestamp))
                m.onEvent?(KeyEvent(keycode: keycode, isDown: type == .keyDown, timestamp: ts))
                return Unmanaged.passRetained(event)
            },
            userInfo: unmanaged.toOpaque()
        ) else {
            unmanaged.release()
            throw MonitorError.tapCreationFailed
        }

        selfUnmanaged = unmanaged
        tap = newTap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)!
        var capturedRunLoop: CFRunLoop?
        let sema = DispatchSemaphore(value: 0)

        let thread = Thread {
            capturedRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(capturedRunLoop!, source, .defaultMode)
            sema.signal()
            CFRunLoopRun()
        }
        thread.name = "com.klinkmac.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        sema.wait()
        tapRunLoop = capturedRunLoop
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        selfUnmanaged?.release()
        selfUnmanaged = nil
        tap = nil
        tapRunLoop = nil
    }

    public enum MonitorError: Error { case tapCreationFailed }
    deinit { stop() }
}
