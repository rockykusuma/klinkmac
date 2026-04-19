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

    var meetingMuteEnabled: Bool = false {
        didSet { UserDefaults.standard.set(meetingMuteEnabled, forKey: Key.meetingMuteEnabled) }
    }

    var outputDeviceName: String = "" {
        didSet { UserDefaults.standard.set(outputDeviceName, forKey: Key.outputDeviceName) }
    }

    var profiles: [AppProfile] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(profiles) {
                UserDefaults.standard.set(data, forKey: Key.profiles)
            }
        }
    }

    var visualizerEnabled: Bool = false {
        didSet { UserDefaults.standard.set(visualizerEnabled, forKey: Key.visualizerEnabled) }
    }

    var velocityDynamicsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(velocityDynamicsEnabled, forKey: Key.velocityDynamicsEnabled) }
    }

    /// One of: "tl", "tr", "bl", "br"
    var visualizerPosition: String = "br" {
        didSet { UserDefaults.standard.set(visualizerPosition, forKey: Key.visualizerPosition) }
    }

    var visualizerOpacity: Double = 0.95 {
        didSet { UserDefaults.standard.set(visualizerOpacity, forKey: Key.visualizerOpacity) }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        let storedVolume = Float(d.double(forKey: Key.volume))
        volume   = storedVolume > 0 ? storedVolume : 0.8
        isPaused = d.bool(forKey: Key.isPaused)
        hasCompletedOnboarding = d.bool(forKey: Key.hasCompletedOnboarding)
        meetingMuteEnabled = d.bool(forKey: Key.meetingMuteEnabled)
        outputDeviceName = d.string(forKey: Key.outputDeviceName) ?? ""
        if let data = d.data(forKey: Key.profiles),
           let decoded = try? JSONDecoder().decode([AppProfile].self, from: data) {
            profiles = decoded
        }
        visualizerEnabled = d.bool(forKey: Key.visualizerEnabled)
        visualizerPosition = d.string(forKey: Key.visualizerPosition) ?? "br"
        let storedOpacity = d.double(forKey: Key.visualizerOpacity)
        visualizerOpacity = storedOpacity > 0 ? storedOpacity : 0.95
        // Default velocity dynamics to true on first launch, honor stored value afterwards.
        velocityDynamicsEnabled = d.object(forKey: Key.velocityDynamicsEnabled) as? Bool ?? true

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
        static let meetingMuteEnabled    = "meetingMuteEnabled"
        static let profiles              = "profiles"
        static let outputDeviceName      = "outputDeviceName"
        static let visualizerEnabled     = "visualizerEnabled"
        static let visualizerPosition    = "visualizerPosition"
        static let visualizerOpacity     = "visualizerOpacity"
        static let velocityDynamicsEnabled = "velocityDynamicsEnabled"
    }

    private let logger = Logger(subsystem: "com.klinkmac", category: "SettingsStore")
}
