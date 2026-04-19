// Overlay (typing visualizer) preferences tab.
import SwiftUI

struct OverlayContent: View {
    var appState: AppState
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                enableCard
                if appState.settings.visualizerEnabled {
                    positionCard
                    opacityCard
                }
                infoCard
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var enableCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.badge.waveform")
                .font(.system(size: 15))
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Typing overlay")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.klinkText)
                Text("Floating keyboard that lights up as you type. Great for streaming or tutorials.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.klinkTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            KlinkToggle(isOn: Binding(
                get: { appState.settings.visualizerEnabled },
                set: { appState.setVisualizerEnabled($0) }
            ))
        }
        .padding(16)
        .background(cardBackground)
    }

    private var positionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Position", systemImage: "rectangle.3.group.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.klinkText)

            HStack(spacing: 10) {
                ForEach(VisualizerWindowController.Position.allCases, id: \.rawValue) { pos in
                    positionButton(pos)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var opacityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Opacity", systemImage: "slider.horizontal.below.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.klinkText)

            HStack(spacing: 12) {
                KlinkSlider(value: Binding(
                    get: { appState.settings.visualizerOpacity },
                    set: { appState.settings.visualizerOpacity = $0 }
                ), range: 0.3...1.0)
                Text("\(Int(appState.settings.visualizerOpacity * 100))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.klinkTextSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func positionButton(_ pos: VisualizerWindowController.Position) -> some View {
        let isSelected = appState.settings.visualizerPosition == pos.rawValue
        return Button {
            appState.setVisualizerPosition(pos.rawValue)
        } label: {
            Text(pos.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.klinkTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? theme.accent : Color.klinkBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? theme.accent : Color.klinkSurfaceHigh,
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.klinkTextSecondary.opacity(0.7))
            Text("The overlay is click-through and always-on-top. "
                 + "It never steals keyboard focus — you keep typing into the active app.")
                .font(.system(size: 11))
                .foregroundStyle(Color.klinkTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.klinkBackground.opacity(0.4))
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.klinkSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.klinkSurfaceHigh, lineWidth: 1)
            )
    }
}
