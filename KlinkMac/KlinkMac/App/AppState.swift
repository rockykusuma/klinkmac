// Observable wiring: permissions, event monitor → SPSC queue → audio engine.
import AppKit
import Foundation
import os
import SwiftUI

// MARK: - Pack model

struct InstalledPack: Identifiable, Sendable {
    let id: String          // manifest id (e.g. "com.klinkmac.cherry-mx-blue")
    let name: String        // display name from manifest
    let author: String
    let description: String?
    let url: URL
    let isBundled: Bool
}

// MARK: - AppState

@MainActor
@Observable
final class AppState {
    // MARK: Settings (persisted)

    var settings = SettingsStore()

    var isEnabled: Bool {
        get { !settings.isPaused }
        set {
            settings.isPaused = !newValue
            updateEngineEnabled()
        }
    }

    func setMeetingMuteEnabled(_ enabled: Bool) {
        settings.meetingMuteEnabled = enabled
        updateEngineEnabled()
    }

    func addProfile(_ profile: AppProfile) {
        settings.profiles.append(profile)
        profileManager.reevaluate()
    }

    func deleteProfile(_ profile: AppProfile) {
        settings.profiles.removeAll { $0.id == profile.id }
        profileManager.reevaluate()
    }

    var volume: Float {
        get { settings.volume }
        set {
            settings.volume = newValue
            audioEngine.volume = newValue
        }
    }

    // MARK: Pack state

    var installedPacks: [InstalledPack] = []
    var activePack: InstalledPack?

    // MARK: Permission state

    var isTrusted: Bool = false

    // MARK: Phase 4 features

    private(set) var isMeetingMuted: Bool = false

    // MARK: Engine + monitor

    let accessibilityManager = AccessibilityManager()
    let audioEngine = AudioEngine()
    private let monitor = KeyEventMonitor()
    private let meetingMuteMonitor = MeetingMuteMonitor()
    private let profileManager = ProfileManager()
    private var defaultPackID: String = ""
    private var permissionWindow: NSWindow?
    private var permissionTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.klinkmac", category: "AppState")

    // MARK: - Init

    init() {
        audioEngine.volume = settings.volume
        try? audioEngine.start()

        discoverPacks()

        let savedID = settings.activePackID
        let startPack = installedPacks.first { $0.id == savedID }
                     ?? installedPacks.first { $0.id == "com.klinkmac.classic-keyboard" }
                     ?? installedPacks.first
        if let pack = startPack {
            loadPack(pack)
        }

        let q = audioEngine.eventQueue
        monitor.onEvent = { [q] (event: KeyEvent) in _ = q.push(event) }

        meetingMuteMonitor.onChanged = { [weak self] _ in self?.updateEngineEnabled() }
        meetingMuteMonitor.start()

        profileManager.onMatch = { [weak self] packID in self?.handleProfileMatch(packID) }
        profileManager.start { [weak self] in self?.settings.profiles ?? [] }

        updateEngineEnabled()

        if !accessibilityManager.isTrusted {
            showPermissionWindow()
            waitForPermissionThenStart()
        } else {
            isTrusted = true
            startMonitor()
        }
    }

    // MARK: - Pack management

    func selectPack(_ pack: InstalledPack) {
        loadPack(pack)
    }

    func installFromURL(_ url: URL) {
        Task.detached(priority: .userInitiated) {
            do {
                let installedURL = try await PackLoader.installPack(zipURL: url)
                await MainActor.run {
                    self.discoverPacks()
                    if let newPack = self.installedPacks.first(where: { $0.url == installedURL }) {
                        self.loadPack(newPack)
                    }
                }
            } catch {
                await MainActor.run { self.showInstallError(error) }
            }
        }
    }

    func deletePack(_ pack: InstalledPack) {
        guard !pack.isBundled else { return }
        try? FileManager.default.removeItem(at: pack.url)
        discoverPacks()
        if activePack?.id == pack.id {
            if let fallback = installedPacks.first {
                loadPack(fallback)
            }
        }
    }

    // MARK: - Pack discovery

    func discoverPacks() {
        var packs: [InstalledPack] = []

        // Bundled packs from Resources/Packs/
        if let resourcesURL = Bundle.main.resourceURL {
            let packsDir = resourcesURL.appendingPathComponent("Packs")
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: packsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )) ?? []
            for url in entries {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if let manifest = try? PackLoader.loadAndValidateManifest(at: url) {
                    packs.append(InstalledPack(id: manifest.id,
                                               name: manifest.name,
                                               author: manifest.author,
                                               description: manifest.description,
                                               url: url,
                                               isBundled: true))
                }
            }
        }

        // User-installed packs
        for (manifest, url) in PackLoader.discoverUserPacks() {
            packs.append(InstalledPack(id: manifest.id,
                                       name: manifest.name,
                                       author: manifest.author,
                                       description: manifest.description,
                                       url: url,
                                       isBundled: false))
        }

        installedPacks = packs
    }

    // MARK: - Private

    private func loadPack(_ pack: InstalledPack) {
        defaultPackID = pack.id
        swapBank(to: pack, persistID: true)
    }

    private func loadPackForProfile(_ pack: InstalledPack) {
        swapBank(to: pack, persistID: false)
    }

    private func swapBank(to pack: InstalledPack, persistID: Bool) {
        let url = pack.url
        let sr  = audioEngine.sampleRate
        Task.detached(priority: .userInitiated) {
            guard let bank = try? await PackLoader.loadFromDisk(at: url, sampleRate: sr) else { return }
            await MainActor.run {
                self.audioEngine.setBank(bank)
                self.activePack = pack
                if persistID { self.settings.activePackID = pack.id }
            }
        }
    }

    private func updateEngineEnabled() {
        let muted = settings.meetingMuteEnabled && meetingMuteMonitor.isMeetingActive
        isMeetingMuted = muted
        audioEngine.setEnabled(!settings.isPaused && !muted)
    }

    private func handleProfileMatch(_ packID: String?) {
        if let packID, let pack = installedPacks.first(where: { $0.id == packID }) {
            loadPackForProfile(pack)
        } else {
            let fallback = installedPacks.first { $0.id == defaultPackID } ?? installedPacks.first
            if let pack = fallback { loadPackForProfile(pack) }
        }
    }

    private func showInstallError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Pack installation failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func waitForPermissionThenStart() {
        accessibilityManager.startPolling()
        permissionTask = Task { [weak self] in
            guard let self else { return }
            while !self.accessibilityManager.isTrusted {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            self.isTrusted = true
            self.settings.hasCompletedOnboarding = true
            self.permissionWindow?.close()
            self.permissionWindow = nil
            self.startMonitor()
        }
    }

    private func startMonitor() {
        do {
            try monitor.start()
        } catch {
            logger.error("Key event monitor failed to start: \(error.localizedDescription)")
        }
    }

    private func showPermissionWindow() {
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
