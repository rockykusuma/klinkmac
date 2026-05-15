// Permission + key-event monitor lifecycle — splits onboarding wiring out of AppState.swift.
import AppKit
import Foundation
import os
import SwiftUI

extension AppState {
    func ensureMonitorStarted() {
        guard accessibilityManager.isTrusted && !monitorStarted else { return }
        startMonitor()
    }

    func refreshTrustState() {
        accessibilityManager.checkTrust()
        isTrusted = accessibilityManager.isTrusted
    }

    func waitForPermissionThenStart() {
        accessibilityManager.onTrusted = { [weak self] in
            guard let self, !self.monitorStarted else { return }
            self.isTrusted = self.accessibilityManager.isTrusted
            self.startMonitor()
            // CGEventTap can fail transiently right after permission grant; keep polling to retry.
            if !self.monitorStarted {
                self.accessibilityManager.startPolling()
            }
        }
        accessibilityManager.startPolling()
    }

    func startMonitor() {
        monitorStarted = true
        do {
            try monitor.start()
            if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        } catch {
            monitorStarted = false
            permissionLogger.error("Key event monitor failed to start: \(error.localizedDescription)")
            guard localKeyMonitor == nil else { return }
            let q = audioEngine.eventQueue
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                _ = q.push(KeyEvent(keycode: UInt16(event.keyCode),
                                    isDown: event.type == .keyDown,
                                    timestamp: mach_absolute_time()))
                return event
            }
        }
    }

    func showPermissionWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to KlinkMac"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(appState: self))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = window
    }
}

private let permissionLogger = Logger(subsystem: "com.klinkmac", category: "AppState.PermissionFlow")
