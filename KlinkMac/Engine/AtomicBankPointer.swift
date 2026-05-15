// Atomic SampleBank pointer swap with deferred release — lock-free, ARC-free on the audio thread.
import Atomics
import Foundation

public final class AtomicBankPointer {
    // Bit pattern of Unmanaged<SampleBank> reference. 0 = nil.
    private let bits = ManagedAtomic<UInt>(0)
    // Old banks released after 5s — long enough for any in-flight voice to finish.
    private let releaseQueue = DispatchQueue(label: "com.klinkmac.bankrelease", qos: .utility)

    public init() {}

    /// Called from main thread when a new pack loads.
    public func store(_ bank: SampleBank) {
        let newBits = UInt(bitPattern: Unmanaged.passRetained(bank).toOpaque())
        let oldBits = bits.exchange(newBits, ordering: .releasing)
        if oldBits != 0, let ptr = UnsafeRawPointer(bitPattern: oldBits) {
            let old = Unmanaged<SampleBank>.fromOpaque(ptr)
            // 5 s >> max voice duration (500 ms cap in PackLoader) + worst-case audio callback.
            releaseQueue.asyncAfter(deadline: .now() + 5) { old.release() }
        }
    }

    /// Called from audio render thread — acquiring load only, no retain/release.
    public func load() -> Unmanaged<SampleBank>? {
        let b = bits.load(ordering: .acquiring)
        guard b != 0, let ptr = UnsafeRawPointer(bitPattern: b) else { return nil }
        return Unmanaged.fromOpaque(ptr)
    }

    deinit {
        let b = bits.load(ordering: .relaxed)
        if b != 0, let ptr = UnsafeRawPointer(bitPattern: b) {
            Unmanaged<SampleBank>.fromOpaque(ptr).release()
        }
    }
}
