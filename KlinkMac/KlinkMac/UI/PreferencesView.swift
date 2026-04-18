// Dark sidebar preferences window: General, Packs, About.
import SwiftUI

struct PreferencesView: View {
    var appState: AppState
    @State private var selectedTab: PrefTab = .general
    @Environment(\.klinkTheme) private var theme

    enum PrefTab: CaseIterable {
        case general, packs, profiles, about

        var title: String {
            switch self {
            case .general:  "General"
            case .packs:    "Packs"
            case .profiles: "Profiles"
            case .about:    "About"
            }
        }

        var icon: String {
            switch self {
            case .general:  "gearshape.fill"
            case .packs:    "music.note.list"
            case .profiles: "app.connected.to.app.below.fill"
            case .about:    "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
            Divider()
                .background(Color.klinkSurfaceHigh)
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 520)
        .background(Color.klinkBackground)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PREFERENCES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.klinkTextSecondary)
                .tracking(1.0)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 8)

            ForEach(PrefTab.allCases, id: \.title) { tab in
                SidebarItem(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                }
            }

            Spacer()
        }
        .frame(width: 180)
        .background(Color.klinkBackground)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if selectedTab == .general {
            GeneralContent(appState: appState)
                .transition(.opacity)
        } else if selectedTab == .packs {
            PacksContent(appState: appState)
                .transition(.opacity)
        } else if selectedTab == .profiles {
            ProfilesContent(appState: appState)
                .transition(.opacity)
        } else {
            AboutContent()
                .transition(.opacity)
        }
    }
}

// MARK: - Sidebar item

private struct SidebarItem: View {
    let tab: PreferencesView.PrefTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.klinkTheme) private var theme

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? theme.accent : Color.klinkTextSecondary)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.klinkText : Color.klinkTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.accent.opacity(0.15))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.klinkSurface)
                    }
                }
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - General

private struct GeneralContent: View {
    var appState: AppState
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Theme picker
                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Accent Color", systemImage: "paintpalette.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.klinkText)
                        HStack(spacing: 10) {
                            ForEach(KlinkTheme.all) { t in
                                ThemeSwatch(
                                    t: t,
                                    isSelected: appState.settings.themeID == t.id
                                ) {
                                    appState.settings.themeID = t.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                // Volume
                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Volume", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.klinkText)
                        HStack(spacing: 12) {
                            KlinkSlider(value: Binding(
                                get: { Double(appState.volume) },
                                set: { appState.volume = Float($0) }
                            ))
                            Text("\(Int(appState.volume * 100))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Color.klinkTextSecondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                // Toggles
                settingsCard {
                    VStack(spacing: 0) {
                        settingsRow(label: "Sound enabled", icon: "keyboard.fill") {
                            KlinkToggle(isOn: Binding(
                                get: { appState.isEnabled },
                                set: { appState.isEnabled = $0 }
                            ))
                        }
                        Divider().background(Color.klinkSurfaceHigh).padding(.leading, 46)
                        settingsRow(label: "Meeting mute", icon: "mic.slash.fill") {
                            KlinkToggle(isOn: Binding(
                                get: { appState.settings.meetingMuteEnabled },
                                set: { appState.setMeetingMuteEnabled($0) }
                            ))
                        }
                        Divider().background(Color.klinkSurfaceHigh).padding(.leading, 46)
                        settingsRow(label: "Launch at login", icon: "arrow.up.circle.fill") {
                            KlinkToggle(isOn: Binding(
                                get: { appState.settings.launchAtLogin },
                                set: { appState.settings.launchAtLogin = $0 }
                            ))
                        }
                    }
                }

                if !appState.isTrusted {
                    accessibilityWarningCard
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func settingsRow<T: View>(label: String, icon: String,
                                      @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.klinkText)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func settingsCard<T: View>(@ViewBuilder content: () -> T) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.klinkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.klinkSurfaceHigh, lineWidth: 1)
                    )
            )
    }

    private var accessibilityWarningCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.klinkWarning)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility permission required")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.klinkText)
                Text("KlinkMac needs this to detect keystrokes.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.klinkTextSecondary)
            }
            Spacer()
            Button("Open Settings") {
                appState.accessibilityManager.openSystemSettings()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.accent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.klinkWarning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.klinkWarning.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Theme swatch

private struct ThemeSwatch: View {
    let t: KlinkTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [t.accent, t.secondary],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .help(t.name)
    }
}
