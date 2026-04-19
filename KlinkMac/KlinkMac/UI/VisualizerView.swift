// Floating typing visualizer: compact keyboard lights up on every keypress.
import SwiftUI

struct VisualizerView: View {
    var appState: AppState

    @Environment(\.klinkTheme) private var theme

    private let keyH: CGFloat = 26
    private let keyGap: CGFloat = 3
    private let unit: CGFloat = 26   // base width unit for a standard key

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            keyboardGrid
        }
        .padding(10)
        .background(backgroundLayer)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.klinkSurfaceHigh, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 24, y: 12)
        .opacity(appState.settings.visualizerOpacity)
        .environment(\.colorScheme, .dark)
    }

    private var backgroundLayer: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.klinkBackground.opacity(0.55)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.accent)
                .frame(width: 5, height: 5)
                .shadow(color: theme.accent, radius: 3)
            Text("KLINKMAC · TYPING")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.klinkTextSecondary.opacity(0.65))
        }
        .padding(.leading, 2)
    }

    private var keyboardGrid: some View {
        VStack(spacing: keyGap) {
            ForEach(VisualizerLayout.rows.indices, id: \.self) { idx in
                HStack(spacing: keyGap) {
                    ForEach(VisualizerLayout.rows[idx]) { key in
                        VisualizerKeyCell(
                            key: key,
                            isPressed: appState.pressedKeys.contains(UInt16(key.keycode)),
                            theme: theme
                        )
                        .frame(width: unit * CGFloat(key.widthUnits) - keyGap,
                               height: keyH)
                    }
                }
            }
        }
    }
}

// MARK: - Individual key cell

private struct VisualizerKeyCell: View {
    let key: KeyDef
    let isPressed: Bool
    let theme: KlinkTheme

    @State private var flashFade = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .shadow(color: isPressed ? theme.accent.opacity(0.7) : .clear,
                        radius: isPressed ? 8 : 0)

            Text(key.label)
                .font(.system(size: fontSize, weight: isPressed ? .semibold : .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .scaleEffect(isPressed ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .onChange(of: isPressed) { _, new in
            if !new {
                withAnimation(.easeOut(duration: 0.35)) { flashFade = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { flashFade = false }
            }
        }
    }

    private var backgroundColor: Color {
        if isPressed {
            return key.isModifier ? theme.secondary : theme.accent
        }
        if flashFade { return theme.accent.opacity(0.22) }
        return key.isModifier ? Color.klinkBackground.opacity(0.5) : Color.klinkSurfaceHigh.opacity(0.5)
    }

    private var borderColor: Color {
        if isPressed { return theme.secondary.opacity(0.7) }
        if flashFade { return theme.accent.opacity(0.35) }
        return Color.klinkSurfaceHigh.opacity(0.3)
    }

    private var labelColor: Color {
        if isPressed { return .white }
        if flashFade { return .white.opacity(0.95) }
        return key.isModifier ? Color.klinkTextSecondary.opacity(0.45) : Color.klinkTextSecondary
    }

    private var fontSize: CGFloat {
        key.widthUnits >= 1.5 ? 8 : 10
    }
}

// MARK: - Compact layout (reuses keycodes from KeyboardLayoutView's KeyDef)

private enum VisualizerLayout {
    static let rows: [[KeyDef]] = [
        [
            KeyDef(label: "`", keycode: 50, widthUnits: 1.0),
            KeyDef(label: "1", keycode: 18, widthUnits: 1.0),
            KeyDef(label: "2", keycode: 19, widthUnits: 1.0),
            KeyDef(label: "3", keycode: 20, widthUnits: 1.0),
            KeyDef(label: "4", keycode: 21, widthUnits: 1.0),
            KeyDef(label: "5", keycode: 23, widthUnits: 1.0),
            KeyDef(label: "6", keycode: 22, widthUnits: 1.0),
            KeyDef(label: "7", keycode: 26, widthUnits: 1.0),
            KeyDef(label: "8", keycode: 28, widthUnits: 1.0),
            KeyDef(label: "9", keycode: 25, widthUnits: 1.0),
            KeyDef(label: "0", keycode: 29, widthUnits: 1.0),
            KeyDef(label: "-", keycode: 27, widthUnits: 1.0),
            KeyDef(label: "=", keycode: 24, widthUnits: 1.0),
            KeyDef(label: "⌫", keycode: 51, widthUnits: 1.75, isModifier: true)
        ],
        [
            KeyDef(label: "⇥", keycode: 48, widthUnits: 1.3, isModifier: true),
            KeyDef(label: "Q", keycode: 12, widthUnits: 1.0),
            KeyDef(label: "W", keycode: 13, widthUnits: 1.0),
            KeyDef(label: "E", keycode: 14, widthUnits: 1.0),
            KeyDef(label: "R", keycode: 15, widthUnits: 1.0),
            KeyDef(label: "T", keycode: 17, widthUnits: 1.0),
            KeyDef(label: "Y", keycode: 16, widthUnits: 1.0),
            KeyDef(label: "U", keycode: 32, widthUnits: 1.0),
            KeyDef(label: "I", keycode: 34, widthUnits: 1.0),
            KeyDef(label: "O", keycode: 31, widthUnits: 1.0),
            KeyDef(label: "P", keycode: 35, widthUnits: 1.0),
            KeyDef(label: "[", keycode: 33, widthUnits: 1.0),
            KeyDef(label: "]", keycode: 30, widthUnits: 1.0),
            KeyDef(label: "\\", keycode: 42, widthUnits: 1.45)
        ],
        [
            KeyDef(label: "⇪", keycode: 57, widthUnits: 1.55, isModifier: true),
            KeyDef(label: "A", keycode: 0, widthUnits: 1.0),
            KeyDef(label: "S", keycode: 1, widthUnits: 1.0),
            KeyDef(label: "D", keycode: 2, widthUnits: 1.0),
            KeyDef(label: "F", keycode: 3, widthUnits: 1.0),
            KeyDef(label: "G", keycode: 5, widthUnits: 1.0),
            KeyDef(label: "H", keycode: 4, widthUnits: 1.0),
            KeyDef(label: "J", keycode: 38, widthUnits: 1.0),
            KeyDef(label: "K", keycode: 40, widthUnits: 1.0),
            KeyDef(label: "L", keycode: 37, widthUnits: 1.0),
            KeyDef(label: ";", keycode: 41, widthUnits: 1.0),
            KeyDef(label: "'", keycode: 39, widthUnits: 1.0),
            KeyDef(label: "↩", keycode: 36, widthUnits: 2.0)
        ],
        [
            KeyDef(label: "⇧", keycode: 56, widthUnits: 2.0, isModifier: true),
            KeyDef(label: "Z", keycode: 6, widthUnits: 1.0),
            KeyDef(label: "X", keycode: 7, widthUnits: 1.0),
            KeyDef(label: "C", keycode: 8, widthUnits: 1.0),
            KeyDef(label: "V", keycode: 9, widthUnits: 1.0),
            KeyDef(label: "B", keycode: 11, widthUnits: 1.0),
            KeyDef(label: "N", keycode: 45, widthUnits: 1.0),
            KeyDef(label: "M", keycode: 46, widthUnits: 1.0),
            KeyDef(label: ",", keycode: 43, widthUnits: 1.0),
            KeyDef(label: ".", keycode: 47, widthUnits: 1.0),
            KeyDef(label: "/", keycode: 44, widthUnits: 1.0),
            KeyDef(label: "⇧", keycode: 60, widthUnits: 2.55, isModifier: true)
        ],
        [
            KeyDef(label: "ctrl", keycode: 59, widthUnits: 1.3, isModifier: true),
            KeyDef(label: "opt", keycode: 58, widthUnits: 1.3, isModifier: true),
            KeyDef(label: "⌘", keycode: 55, widthUnits: 1.3, isModifier: true),
            KeyDef(label: "space", keycode: 49, widthUnits: 6.3),
            KeyDef(label: "⌘", keycode: 54, widthUnits: 1.3, isModifier: true),
            KeyDef(label: "opt", keycode: 61, widthUnits: 1.3, isModifier: true),
            KeyDef(label: "ctrl", keycode: 62, widthUnits: 1.3, isModifier: true)
        ]
    ]
}
