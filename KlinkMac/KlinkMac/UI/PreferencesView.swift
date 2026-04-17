// Three-tab Preferences window: General, Packs, About.
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    var appState: AppState

    var body: some View {
        TabView {
            GeneralTab(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }

            PacksTab(appState: appState)
                .tabItem { Label("Packs", systemImage: "music.note.list") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 380)
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    var appState: AppState

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Volume")
                    Slider(
                        value: Binding(
                            get: { Double(appState.volume) },
                            set: { appState.volume = Float($0) }
                        ),
                        in: 0...1
                    )
                    Text("\(Int(appState.volume * 100))%")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                Toggle("Pause", isOn: Binding(
                    get: { !appState.isEnabled },
                    set: { appState.isEnabled = !$0 }
                ))

                Toggle("Launch at login", isOn: Binding(
                    get: { appState.settings.launchAtLogin },
                    set: { appState.settings.launchAtLogin = $0 }
                ))
            }

            if !appState.isTrusted {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility permission is required.")
                        Spacer()
                        Button("Open Settings…") {
                            appState.accessibilityManager.openSystemSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Packs tab

private struct PacksTab: View {
    var appState: AppState
    @State private var isDropTargeted = false
    @State private var installError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(appState.installedPacks) { pack in
                    PackRowView(pack: pack, appState: appState)
                }
            }
            .listStyle(.bordered)

            Divider()

            // Drag-drop zone + buttons
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
                    .frame(height: 52)
                    .overlay {
                        Label("Drop .klinkpack here to install",
                              systemImage: "tray.and.arrow.down")
                            .font(.callout)
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else { return false }
                        appState.installFromURL(url)
                        return true
                    } isTargeted: { isDropTargeted = $0 }

                Button("Open Packs Folder") {
                    if let dir = try? PackLoader.userPacksDirectory() {
                        NSWorkspace.shared.open(dir)
                    }
                }
                .fixedSize()
            }
            .padding(12)

            if let err = installError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct PackRowView: View {
    let pack: InstalledPack
    var appState: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pack.name).fontWeight(.medium)
                    if pack.isBundled {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(pack.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.activePack?.id == pack.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
            if !pack.isBundled {
                Button {
                    appState.deletePack(pack)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove this pack")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { appState.selectPack(pack) }
        .padding(.vertical, 4)
    }
}

// MARK: - About tab

private struct AboutTab: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("KlinkMac")
                    .font(.title2).bold()
                Text("Version \(version) (\(build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Ultra-low-latency mechanical keyboard sounds for macOS.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            HStack(spacing: 24) {
                Link("Website", destination: URL(string: "https://klinkmac.com")!)
                Link("GitHub", destination: URL(string: "https://github.com/")!)
                Link("Support", destination: URL(string: "mailto:support@klinkmac.com")!)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
