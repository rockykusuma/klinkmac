// Profiles tab: app-aware sound pack rules management UI.
import AppKit
import SwiftUI

// MARK: - Profiles tab

struct ProfilesContent: View {
    var appState: AppState
    @State private var showAddSheet = false
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if appState.settings.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
            Divider().background(Color.klinkSurfaceHigh)
            addBar
        }
        .sheet(isPresented: $showAddSheet) {
            AddProfileSheet(appState: appState, isPresented: $showAddSheet)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.system(size: 36))
                .foregroundStyle(theme.accent.opacity(0.5))
            Text("No app profiles yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.klinkText)
            Text("Automatically switch sound packs\nwhen specific apps are in focus.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.klinkTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profileList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(appState.settings.profiles) { profile in
                    let packName = appState.installedPacks
                        .first { $0.id == profile.packID }?.name ?? profile.packID
                    ProfileRow(profile: profile, packName: packName) {
                        appState.deleteProfile(profile)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
    }

    private var addBar: some View {
        HStack {
            Spacer()
            Button("Add Profile") { showAddSheet = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.accent.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
    }
}

// MARK: - Profile row

struct ProfileRow: View {
    let profile: AppProfile
    let packName: String
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            appIconView
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.klinkText)
                Text(profile.bundleID)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.klinkTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(Color.klinkTextSecondary)
            Text(packName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.red.opacity(0.7))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? Color.klinkSurface : .clear))
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var appIconView: some View {
        let runningIcon = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == profile.bundleID }?.icon
        if let icon = runningIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.klinkTextSecondary)
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Add profile sheet

struct AddProfileSheet: View {
    var appState: AppState
    @Binding var isPresented: Bool

    @State private var step: Step = .pickApp
    @State private var selectedApp: RunningAppInfo?
    @Environment(\.klinkTheme) private var theme

    enum Step { case pickApp, pickPack }

    private let runningApps: [RunningAppInfo] = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .compactMap { app in
            guard let bid = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return RunningAppInfo(bundleID: bid, name: name, icon: app.icon)
        }
        .sorted { $0.name < $1.name }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().background(Color.klinkSurfaceHigh)
            if step == .pickApp { appPickerList } else { packPickerList }
        }
        .frame(width: 400, height: 460)
        .background(Color.klinkBackground)
        .environment(\.colorScheme, .dark)
    }

    private var sheetHeader: some View {
        HStack {
            Text(step == .pickApp ? "Choose App" : "Choose Pack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.klinkText)
            Spacer()
            Button("Cancel") { isPresented = false }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.klinkTextSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var appPickerList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(runningApps) { app in
                    AppPickerRow(app: app) {
                        selectedApp = app
                        step = .pickPack
                    }
                }
            }
            .padding(12)
        }
    }

    private var packPickerList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(appState.installedPacks) { pack in
                        packRow(for: pack)
                    }
                }
                .padding(.vertical, 8)
            }
            Divider().background(Color.klinkSurfaceHigh)
            HStack {
                Button("Back") { step = .pickApp }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.klinkTextSecondary)
                Spacer()
            }
            .padding(16)
        }
    }

    private func packRow(for pack: InstalledPack) -> some View {
        Button {
            if let app = selectedApp {
                appState.addProfile(AppProfile(bundleID: app.bundleID,
                                               packID: pack.id,
                                               appName: app.name))
            }
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.accent)
                    .frame(width: 20)
                Text(pack.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.klinkText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting types

struct RunningAppInfo: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage?
}

private struct AppPickerRow: View {
    let app: RunningAppInfo
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Color.klinkTextSecondary)
                }
                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.klinkText)
                Spacer()
                Text(app.bundleID)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.klinkTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? Color.klinkSurface : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
