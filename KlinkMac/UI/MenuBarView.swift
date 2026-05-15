// Menu bar floating panel: waveform, pack list, volume slider, quick actions.
import SwiftUI

struct MenuBarView: View {
    var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismissPanel
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            waveSection
            Divider().background(Color.klinkSurfaceHigh)
            packsSection
            Divider().background(Color.klinkSurfaceHigh)
            volumeSection
            Divider().background(Color.klinkSurfaceHigh)
            footerSection
        }
        .frame(width: 340)
        .background(Color.klinkBackground)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.isEnabled ? "keyboard.fill" : "keyboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.accent)
            Text("KlinkMac")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.klinkText)
            Spacer()
            KlinkToggle(isOn: Binding(
                get: { appState.isEnabled },
                set: { appState.isEnabled = $0 }
            ))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Waveform

    private var waveSection: some View {
        WaveformView(isActive: appState.isEnabled)
            .frame(height: 60)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.klinkSurface.opacity(0.5))
    }

    // MARK: - Packs

    private var packsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SOUND PACKS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.klinkTextSecondary)
                    .tracking(1.2)
                Spacer()
                Text("\(appState.installedPacks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.klinkTextSecondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            ScrollView(.vertical, showsIndicators: appState.installedPacks.count > 5) {
                VStack(spacing: 1) {
                    ForEach(appState.installedPacks) { pack in
                        PackRow(
                            pack: pack,
                            isActive: appState.activePack?.id == pack.id
                        )
                        .onTapGesture { appState.selectPack(pack) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 190)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Volume

    private var volumeSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(Color.klinkTextSecondary)
                .frame(width: 14)

            KlinkSlider(value: Binding(
                get: { Double(appState.volume) },
                set: { appState.volume = Float($0) }
            ))

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(Color.klinkTextSecondary)
                .frame(width: 14)

            Text("\(Int(appState.volume * 100))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.klinkTextSecondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.klinkSurface.opacity(0.5))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            footerButton(icon: "gearshape.fill", label: "Preferences") {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dismissPanel()
                    // Activate + explicitly front the settings window.
                    // On macOS 14+, activate(ignoringOtherApps:) alone no longer
                    // steals focus after a panel dismissal — makeKeyAndOrderFront is required.
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows
                        .first { !($0 is NSPanel) && $0.isVisible }?
                        .makeKeyAndOrderFront(nil)
                }
            }

            if !appState.isTrusted {
                footerButton(icon: "lock.shield.fill", label: "Permission",
                             tint: .klinkWarning) {
                    appState.accessibilityManager.openSystemSettings()
                }
            }

            Spacer()

            footerButton(icon: "power", label: "Quit",
                         tint: Color.klinkTextSecondary.opacity(0.8)) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func footerButton(icon: String, label: String,
                              tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        let color = tint ?? theme.accent
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pack row

private struct PackRow: View {
    let pack: InstalledPack
    let isActive: Bool
    @Environment(\.klinkTheme) private var theme

    @State private var isHovered = false

    private var accentColor: Color {
        let h = Double(abs(pack.id.hashValue) % 270 + 20) / 360.0
        return Color(hue: h, saturation: 0.65, brightness: 0.85)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: 7, height: 7)

            Text(pack.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.klinkText : Color.klinkTextSecondary)
                .lineLimit(1)

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive
                      ? theme.accent.opacity(0.12)
                      : (isHovered ? Color.klinkSurface : .clear))
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isActive)
        .onHover { isHovered = $0 }
    }
}
