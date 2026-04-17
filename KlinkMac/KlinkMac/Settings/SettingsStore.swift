// UserDefaults-backed settings. Observable from any SwiftUI view.
import Foundation
import ServiceManagement
import os

@MainActor
@Observable
final class SettingsStore {

    // MARK: - Persisted properties

    var volume: Float = 0.8 {
        didSet { UserDefaults.standard.set(volume, forKey: Key.volume) }
    }

    var activePackID: String = "" {
        didSet { UserDefaults.standard.set(activePackID, forKey: Key.activePackID) }
    }

    var isPaused: Bool = false {
        didSet { UserDefaults.standard.set(isPaused, forKey: Key.isPaused) }
    }

    var launchAtLogin: Bool = false {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    var hasCompletedOnboarding: Bool = false {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        let storedVolume = d.float(forKey: Key.volume)
        volume   = storedVolume > 0 ? storedVolume : 0.8
        isPaused = d.bool(forKey: Key.isPaused)
        hasCompletedOnboarding = d.bool(forKey: Key.hasCompletedOnboarding)

        // Reflect actual SMAppService state rather than a possibly stale stored bool.
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if d.object(forKey: Key.launchAtLogin) == nil {
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
        }

        activePackID = d.string(forKey: Key.activePackID) ?? ""
    }

    // MARK: - Launch-at-login

    private func applyLaunchAtLogin(_ enable: Bool) {
        if enable {
            do {
                try SMAppService.mainApp.register()
            } catch {
                logger.error("Launch-at-login register failed: \(error.localizedDescription)")
            }
        } else {
            Task {
                do {
                    try await SMAppService.mainApp.unregister()
                } catch {
                    logger.error("Launch-at-login unregister failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Internals

    private enum Key {
        static let volume                = "volume"
        static let activePackID          = "activePackID"
        static let isPaused              = "isPaused"
        static let launchAtLogin         = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let logger = Logger(subsystem: "com.klinkmac", category: "SettingsStore")
}
