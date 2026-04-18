// UserDefaults-backed settings. Observable from any SwiftUI view.
import Foundation
import os
import ServiceManagement

@MainActor
@Observable
final class SettingsStore {
    // MARK: - Persisted properties

    var volume: Float = 0.8 {
        didSet { UserDefaults.standard.set(Double(volume), forKey: Key.volume) }
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
            if !_suppressLaunchAtLoginService {
                applyLaunchAtLogin(launchAtLogin)
            }
        }
    }

    var hasCompletedOnboarding: Bool = false {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    var themeID: String = "jade" {
        didSet { UserDefaults.standard.set(themeID, forKey: Key.themeID) }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        let storedVolume = Float(d.double(forKey: Key.volume))
        volume   = storedVolume > 0 ? storedVolume : 0.8
        isPaused = d.bool(forKey: Key.isPaused)
        hasCompletedOnboarding = d.bool(forKey: Key.hasCompletedOnboarding)

        // Reflect actual SMAppService state rather than a possibly stale stored bool.
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if d.object(forKey: Key.launchAtLogin) == nil {
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
        }

        activePackID = d.string(forKey: Key.activePackID) ?? ""
        themeID = d.string(forKey: Key.themeID) ?? "jade"
    }

    // MARK: - Launch-at-login

    private var _suppressLaunchAtLoginService = false

    private func applyLaunchAtLogin(_ enable: Bool) {
        if enable {
            do {
                try SMAppService.mainApp.register()
            } catch {
                logger.error("Launch-at-login register failed: \(error.localizedDescription)")
                _suppressLaunchAtLoginService = true
                launchAtLogin = false
                _suppressLaunchAtLoginService = false
            }
        } else {
            Task {
                do {
                    try await SMAppService.mainApp.unregister()
                } catch {
                    logger.error("Launch-at-login unregister failed: \(error.localizedDescription)")
                    self._suppressLaunchAtLoginService = true
                    self.launchAtLogin = true
                    self._suppressLaunchAtLoginService = false
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
        static let themeID               = "themeID"
    }

    private let logger = Logger(subsystem: "com.klinkmac", category: "SettingsStore")
}
