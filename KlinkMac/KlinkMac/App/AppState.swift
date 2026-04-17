// Observable wiring: permissions, event monitor → SPSC queue → audio engine.
import AppKit
import Foundation
import SwiftUI
import os

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
            audioEngine.setEnabled(newValue)
        }
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
    var activePack: InstalledPack? = nil

    // MARK: Permission state

    var isTrusted: Bool = false

    // MARK: Engine + monitor

    let accessibilityManager = AccessibilityManager()
    let audioEngine = AudioEngine()
    private let monitor = KeyEventMonitor()
    private var permissionWindow: NSWindow?

    // MARK: - Init

    init() {
        audioEngine.volume = settings.volume
        try? audioEngine.start()

        discoverPacks()

        let savedID = settings.activePackID
        let startPack = installedPacks.first(where: { $0.id == savedID })
                     ?? installedPacks.first
        if let pack = startPack {
            loadPack(pack)
        }

        let q = audioEngine.eventQueue
        monitor.onEvent = { [q] (event: KeyEvent) in _ = q.push(event) }

        audioEngine.setEnabled(!settings.isPaused)

        if !accessibilityManager.isTrusted {
            showPermissionWindow()
            waitForPermissionThenStart()
        } else {
            isTrusted = true
            try? monitor.start()
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
        let url = pack.url
        let sr  = audioEngine.sampleRate
        Task.detached(priority: .userInitiated) {
            guard let bank = try? await PackLoader.loadFromDisk(at: url, sampleRate: sr) else {
                return
            }
            await MainActor.run {
                self.audioEngine.setBank(bank)
                self.activePack = pack
                self.settings.activePackID = pack.id
            }
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
        Task { [weak self] in
            guard let self else { return }
            while !self.accessibilityManager.isTrusted {
                try? await Task.sleep(for: .milliseconds(300))
            }
            self.isTrusted = true
            self.settings.hasCompletedOnboarding = true
            self.permissionWindow?.close()
            self.permissionWindow = nil
            try? self.monitor.start()
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
