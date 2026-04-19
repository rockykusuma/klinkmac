// Observable wiring: permissions, event monitor → SPSC queue → audio engine.
import AppKit
import CoreAudio
import Foundation
import os
import SwiftUI

// MARK: - Output device model

struct AudioOutputDevice: Hashable, Identifiable, Sendable {
    let id: AudioDeviceID  // 0 = system default
    let name: String
}

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

    func setVelocityDynamicsEnabled(_ enabled: Bool) {
        settings.velocityDynamicsEnabled = enabled
        audioEngine.setVelocityDynamics(enabled)
    }

    func refreshOutputDevices() {
        let devices = AudioEngine.outputDevices().map { AudioOutputDevice(id: $0.id, name: $0.name) }
        outputDevices = devices
        let savedName = settings.outputDeviceName
        selectedOutputDevice = savedName.isEmpty ? nil : devices.first { $0.name == savedName }
        if let device = selectedOutputDevice {
            try? audioEngine.setOutputDevice(device.id)
        }
    }

    func selectOutputDevice(_ device: AudioOutputDevice?) {
        selectedOutputDevice = device
        settings.outputDeviceName = device?.name ?? ""
        try? audioEngine.setOutputDevice(device?.id)
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

    // MARK: Output routing state

    var outputDevices: [AudioOutputDevice] = []
    var selectedOutputDevice: AudioOutputDevice?

    // MARK: Permission state

    var isTrusted: Bool = false

    // MARK: Phase 4 features

    private(set) var isMeetingMuted: Bool = false

    // MARK: Phase 4D — Record pack

    private(set) var packRecorder: PackRecorder?
    private var recordPackWindow: NSWindow?

    // MARK: Phase 4E — Typing visualizer overlay

    private(set) var pressedKeys: Set<UInt16> = []
    private let visualizerController = VisualizerWindowController()
    private var pressedKeyReleaseTasks: [UInt16: Task<Void, Never>] = [:]

    // MARK: Engine + monitor

    let accessibilityManager = AccessibilityManager()
    let audioEngine = AudioEngine()
    private let monitor = KeyEventMonitor()
    private let meetingMuteMonitor = MeetingMuteMonitor()
    private let profileManager = ProfileManager()
    private var defaultPackID: String = ""
    private var permissionWindow: NSWindow?
    private var monitorStarted = false
    private var localKeyMonitor: Any?
    private let logger = Logger(subsystem: "com.klinkmac", category: "AppState")

    // MARK: - Init

    init() {
        audioEngine.volume = settings.volume
        audioEngine.setVelocityDynamics(settings.velocityDynamicsEnabled)
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
        monitor.onEvent = { [q, weak self] (event: KeyEvent) in
            _ = q.push(event)
            // Fan out to main thread for visualizer UI.
            // Check happens on main to avoid racing the @MainActor-isolated settings flag.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.settings.visualizerEnabled else { return }
                self.handleVisualizerEvent(event)
            }
        }

        refreshOutputDevices()

        meetingMuteMonitor.onChanged = { [weak self] _ in self?.updateEngineEnabled() }
        meetingMuteMonitor.start()

        profileManager.onMatch = { [weak self] packID in self?.handleProfileMatch(packID) }
        profileManager.start { [weak self] in self?.settings.profiles ?? [] }

        updateEngineEnabled()

        startMonitor()

        if !accessibilityManager.isTrusted {
            showPermissionWindow()
            waitForPermissionThenStart()
        } else {
            isTrusted = true
        }

        if settings.visualizerEnabled { visualizerController.show(appState: self) }
    }
}

// MARK: - Pack management

extension AppState {
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

    private func loadPack(_ pack: InstalledPack, persistID: Bool = true) {
        if persistID { defaultPackID = pack.id }
        swapBank(to: pack, persistID: persistID)
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
            loadPack(pack, persistID: false)
        } else {
            let fallback = installedPacks.first { $0.id == defaultPackID } ?? installedPacks.first
            if let pack = fallback { loadPack(pack, persistID: false) }
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
        accessibilityManager.onTrusted = { [weak self] in
            guard let self, !self.monitorStarted else { return }
            self.isTrusted = self.accessibilityManager.isTrusted
            self.startMonitor()
        }
        accessibilityManager.startPolling()
    }

    private func startMonitor() {
        monitorStarted = true
        do {
            try monitor.start()
            if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        } catch {
            monitorStarted = false
            logger.error("Key event monitor failed to start: \(error.localizedDescription)")
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

    func showRecordPackWindow() {
        if recordPackWindow?.isVisible == true {
            recordPackWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let recorder = PackRecorder()
        packRecorder = recorder
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Record Your Own Pack"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RecordPackView(appState: self))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        recordPackWindow = window
    }

    func closeRecordPackWindow() {
        packRecorder?.cleanup()
        packRecorder = nil
        let window = recordPackWindow
        recordPackWindow = nil
        window?.close()
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

// MARK: - Visualizer overlay

extension AppState {
    func setVisualizerEnabled(_ enabled: Bool) {
        settings.visualizerEnabled = enabled
        if enabled {
            visualizerController.show(appState: self)
        } else {
            visualizerController.hide()
            pressedKeyReleaseTasks.values.forEach { $0.cancel() }
            pressedKeyReleaseTasks.removeAll()
            pressedKeys.removeAll()
        }
    }

    func setVisualizerPosition(_ position: String) {
        settings.visualizerPosition = position
        if let pos = VisualizerWindowController.Position(rawValue: position) {
            visualizerController.reposition(for: pos)
        }
    }

    fileprivate func handleVisualizerEvent(_ event: KeyEvent) {
        let kc = event.keycode
        if event.isDown {
            pressedKeys.insert(kc)
            pressedKeyReleaseTasks[kc]?.cancel()
            // Auto-release after 180ms in case keyUp is swallowed by foreground app.
            pressedKeyReleaseTasks[kc] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.pressedKeys.remove(kc)
                    self?.pressedKeyReleaseTasks[kc] = nil
                }
            }
        } else {
            pressedKeyReleaseTasks[kc]?.cancel()
            pressedKeyReleaseTasks[kc] = nil
            pressedKeys.remove(kc)
        }
    }
}
