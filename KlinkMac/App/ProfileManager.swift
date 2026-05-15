// Watches foreground app changes; triggers pack swaps when a profile rule matches.
import AppKit
import Foundation

@MainActor
final class ProfileManager {
    var onMatch: ((String?) -> Void)?

    private var observer: NSObjectProtocol?
    private var getProfiles: (() -> [AppProfile])?
    private var lastBundleID: String?

    func start(profiles: @escaping () -> [AppProfile]) {
        getProfiles = profiles
        lastBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        evaluate(bundleID: lastBundleID)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.lastBundleID = bundleID
                self?.evaluate(bundleID: bundleID)
            }
        }
    }

    func stop() {
        guard let obs = observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(obs)
        observer = nil
    }

    func reevaluate() {
        evaluate(bundleID: lastBundleID)
    }

    private func evaluate(bundleID: String?) {
        let profiles = getProfiles?() ?? []
        let match = profiles.first { $0.bundleID == (bundleID ?? "") }
        onMatch?(match?.packID)
    }
}
