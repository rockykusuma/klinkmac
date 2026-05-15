// Checks and polls Accessibility permission state.
import AppKit
import ApplicationServices
import Foundation

@MainActor
@Observable
final class AccessibilityManager {
    private(set) var isTrusted: Bool = false
    var onTrusted: (() -> Void)?
    private var pollingTimer: Timer?
    private var distributedObserver: AnyObject?
    private var activateObserver: AnyObject?

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

    func forceCheckAndProceed() {
        let trusted = AXIsProcessTrusted()
        isTrusted = trusted
        if trusted {
            stopPolling()
            onTrusted?()
        } else {
            // Permission not yet detected — fire onTrusted anyway so app can proceed.
            // Background polling will start the monitor when trust is eventually detected.
            onTrusted?()
        }
    }

    func startPolling() {
        guard pollingTimer == nil else { return }

        // Distributed notification fires immediately when accessibility toggle changes.
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkTrust() }
        }

        // Timer in .common mode fires across all run loop modes (including modal/sheet).
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkTrust() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer

        // Check immediately when app regains focus (e.g. after system dialog dismisses).
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app == NSRunningApplication.current else { return }
            Task { @MainActor [weak self] in self?.checkTrust() }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let obs = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            distributedObserver = nil
        }
        if let obs = activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            activateObserver = nil
        }
    }

    private func checkTrust() {
        let trusted = AXIsProcessTrusted()
        isTrusted = trusted
        if trusted {
            stopPolling()
            onTrusted?()
        }
    }
}
