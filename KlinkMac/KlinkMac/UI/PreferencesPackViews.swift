// Pack grid and About tab content views used in PreferencesView.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Packs

struct PacksContent: View {
    var appState: AppState
    @State private var isDropTargeted = false
    @Environment(\.klinkTheme) private var theme

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(appState.installedPacks) { pack in
                        PackGridCard(
                            pack: pack,
                            isActive: appState.activePack?.id == pack.id,
                            onSelect: { appState.selectPack(pack) },
                            onDelete: pack.isBundled ? nil : { appState.deletePack(pack) },
                            onExport: pack.isBundled ? nil : { exportPack(pack) }
                        )
                    }
                }
                .padding(20)
            }

            Divider().background(Color.klinkSurfaceHigh)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? theme.accent : Color.klinkSurfaceHigh,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                        .frame(height: 46)
                        .overlay {
                            Label("Drop .klinkpack to install",
                                  systemImage: "tray.and.arrow.down")
                                .font(.system(size: 12))
                                .foregroundStyle(isDropTargeted
                                                 ? theme.accent : Color.klinkTextSecondary)
                        }
                        .dropDestination(for: URL.self) { urls, _ in
                            guard let url = urls.first else { return false }
                            appState.installFromURL(url)
                            return true
                        } isTargeted: { isDropTargeted = $0 }

                    Button("Record Pack") {
                        appState.showRecordPackWindow()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.accent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8))

                    Button("Open Packs Folder") {
                        if let dir = try? PackLoader.userPacksDirectory() {
                            NSWorkspace.shared.open(dir)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.accent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.klinkTextSecondary.opacity(0.7))
                    Text(".klinkpack is a ZIP archive containing WAV sounds + manifest.json.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.klinkTextSecondary.opacity(0.7))
                    Text("Record your own above, or export from any user pack.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.klinkTextSecondary.opacity(0.5))
                    Spacer()
                }
            }
            .padding(16)
        }
    }

    private func exportPack(_ pack: InstalledPack) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "\(pack.name).klinkpack"
        panel.message = "Export \(pack.name) as a .klinkpack file to share or back up."
        panel.begin { [pack] response in
            guard response == .OK, let dest = panel.url else { return }
            Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                task.arguments = ["-r", dest.path, "."]
                task.currentDirectoryURL = pack.url
                try? task.run()
                task.waitUntilExit()
            }
        }
    }
}

struct PackGridCard: View {
    let pack: InstalledPack
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    var onExport: (() -> Void)?

    @State private var isHovered = false

    private var accentColor: Color {
        let h = Double(abs(pack.id.hashValue) % 270 + 20) / 360.0
        return Color(hue: h, saturation: 0.65, brightness: 0.85)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.klinkText)
                        .lineLimit(2)
                    if !pack.isBundled && !pack.author.isEmpty {
                        Text(pack.author)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.klinkTextSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(spacing: 6) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accentColor)
                            .font(.system(size: 15))
                    }
                    if let exp = onExport {
                        Button(action: exp) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.klinkTextSecondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1 : 0)
                        .help("Export as .klinkpack")
                    }
                    if let del = onDelete {
                        Button(action: del) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1 : 0)
                        .help("Delete pack")
                    }
                }
            }

            accentColor
                .frame(height: 2)
                .clipShape(Capsule())
                .opacity(isActive ? 1.0 : 0.3)

            if pack.isBundled {
                Text("Built-in")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.klinkTextSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.klinkSurfaceHigh,
                                in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? accentColor.opacity(0.1) : Color.klinkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isActive ? accentColor.opacity(0.4) : Color.klinkSurfaceHigh,
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isHovered && !isActive ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - About

struct AboutContent: View {
    @Environment(\.klinkTheme) private var theme
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [theme.accent.opacity(0.2), theme.secondary.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 88, height: 88)
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(theme.accent)
            }

            VStack(spacing: 6) {
                Text("KlinkMac")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.klinkText)
                Text("Version \(version) (\(build))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.klinkTextSecondary)
            }

            Text("Ultra-low-latency mechanical keyboard sounds for macOS.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.klinkTextSecondary)
                .frame(maxWidth: 300)

            HStack(spacing: 14) {
                aboutLink("Website", url: "https://klinkmac.com")
                aboutLink("GitHub", url: "https://github.com/")
                aboutLink("Support", url: "mailto:support@klinkmac.com")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func aboutLink(_ label: String, url: String) -> some View {
        Link(label, destination: URL(string: url)!)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(theme.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}
