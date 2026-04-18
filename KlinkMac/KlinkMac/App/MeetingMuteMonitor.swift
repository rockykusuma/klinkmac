// Watches foreground app changes; flags when a known video-conferencing app is active.
import AppKit
import Foundation

@MainActor
final class MeetingMuteMonitor {
    private(set) var isMeetingActive = false
    var onChanged: ((Bool) -> Void)?

    private var observer: NSObjectProtocol?

    private static let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.discord.Mac",
        "com.apple.FaceTime",
        "com.skype.skype",
        "com.cisco.webex.meetings",
        "com.webex.meetingmanager",
        "com.loom.desktop",
        "com.slack.slack",
        "com.whereby.Whereby"
    ]

    func start() {
        update(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in self?.update(bundleID: bundleID) }
        }
    }

    func stop() {
        guard let obs = observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(obs)
        observer = nil
    }

    private func update(bundleID: String?) {
        let active = Self.meetingBundleIDs.contains(bundleID ?? "")
        guard active != isMeetingActive else { return }
        isMeetingActive = active
        onChanged?(active)
    }
}
