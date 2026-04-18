// Checks and polls Accessibility permission state.
import AppKit
import ApplicationServices
import Foundation

@MainActor
@Observable
final class AccessibilityManager {
    private(set) var isTrusted: Bool = false
    private var pollingTask: Task<Void, Never>?

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        startPolling()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        startPolling()
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                let trusted = AXIsProcessTrusted()
                self.isTrusted = trusted
                if trusted {
                    self.pollingTask = nil
                    break
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
