// QWERTY keyboard grid for the record-pack flow — shows per-key recording state.
import SwiftUI

// MARK: - Key definition

struct KeyDef: Identifiable {
    let label: String
    let keycode: UInt32
    let widthUnits: Double   // relative width; 1.0 = standard key
    var isModifier: Bool = false

    var id: UInt32 { keycode }
}

// MARK: - Keyboard rows (US ANSI layout, each row totals 15 width units)

let keyboardRows: [[KeyDef]] = [
    // Row 1 — number row (13 standard + backspace 2.0 = 15)
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
        KeyDef(label: "⌫", keycode: 51, widthUnits: 2.0)
    ],
    // Row 2 — QWERTY (tab 1.5 + 12 + backslash 1.5 = 15)
    [
        KeyDef(label: "⇥", keycode: 48, widthUnits: 1.5),
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
        KeyDef(label: "\\", keycode: 42, widthUnits: 1.5)
    ],
    // Row 3 — ASDF (caps 1.75 + 11 + return 2.25 = 15)
    [
        KeyDef(label: "⇪", keycode: 57, widthUnits: 1.75, isModifier: true),
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
        KeyDef(label: "↩", keycode: 36, widthUnits: 2.25)
    ],
    // Row 4 — ZXCV (lshift 2.25 + 10 + rshift 2.75 = 15)
    [
        KeyDef(label: "⇧", keycode: 56, widthUnits: 2.25, isModifier: true),
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
        KeyDef(label: "⇧", keycode: 60, widthUnits: 2.75, isModifier: true)
    ],
    // Row 5 — modifiers + space (6×1.5 + space 6.0 = 15)
    [
        KeyDef(label: "ctrl", keycode: 59, widthUnits: 1.5, isModifier: true),
        KeyDef(label: "opt", keycode: 58, widthUnits: 1.5, isModifier: true),
        KeyDef(label: "⌘", keycode: 55, widthUnits: 1.5, isModifier: true),
        KeyDef(label: "Space", keycode: 49, widthUnits: 6.0),
        KeyDef(label: "⌘", keycode: 54, widthUnits: 1.5, isModifier: true),
        KeyDef(label: "opt", keycode: 61, widthUnits: 1.5, isModifier: true),
        KeyDef(label: "ctrl", keycode: 62, widthUnits: 1.5, isModifier: true)
    ]
]

// MARK: - KeyboardLayoutView

struct KeyboardLayoutView: View {
    let recorder: PackRecorder
    let onKeyTap: (UInt32, String) -> Void

    private let keyHeight: CGFloat = 38
    private let keySpacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let baseW = geo.size.width / 15.0
            VStack(spacing: keySpacing) {
                ForEach(keyboardRows.indices, id: \.self) { rowIdx in
                    HStack(spacing: keySpacing) {
                        ForEach(keyboardRows[rowIdx]) { key in
                            KeyCell(
                                key: key,
                                cellState: cellState(for: key)
                            ) {
                                guard !key.isModifier else { return }
                                onKeyTap(key.keycode, key.label)
                            }
                            .frame(width: baseW * key.widthUnits - keySpacing,
                                   height: keyHeight)
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(keyboardRows.count) * (keyHeight + keySpacing) - keySpacing)
    }

    private func cellState(for key: KeyDef) -> KeyCellState {
        if key.isModifier { return .modifier }
        switch recorder.state {
        case .awaitingPress(let kc, _) where kc == key.keycode:
            return .awaiting
        case .recording(let kc, _) where kc == key.keycode:
            return .recording
        default:
            return recorder.recordedKeys.contains(key.keycode) ? .recorded : .normal
        }
    }
}

// MARK: - Cell state + cell view

enum KeyCellState { case normal, awaiting, recording, recorded, modifier }

private struct KeyCell: View {
    let key: KeyDef
    let cellState: KeyCellState
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var pulse = false
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            ZStack {
                background
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onChange(of: cellState) { _, new in
            if new == .recording {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation { pulse = false }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch cellState {
        case .normal:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.klinkSurfaceHigh : Color.klinkSurface)
        case .awaiting:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.accent.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.6), lineWidth: 1.5)
                )
        case .recording:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.red.opacity(pulse ? 0.45 : 0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.8), lineWidth: 1.5)
                )
        case .recorded:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.green.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                )
        case .modifier:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.klinkBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        if cellState == .recorded {
            VStack(spacing: 1) {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.9))
                Text(key.label)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            }
        } else {
            Text(key.label)
                .font(.system(size: fontSize,
                              weight: cellState == .awaiting ? .semibold : .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var fontSize: CGFloat {
        key.widthUnits >= 1.5 ? 10 : 12
    }

    private var labelColor: Color {
        switch cellState {
        case .modifier:     return Color.klinkTextSecondary.opacity(0.4)
        case .awaiting:     return theme.accent
        case .recording:    return Color.red
        case .recorded:     return Color.green
        case .normal:       return isHovered ? Color.klinkText : Color.klinkTextSecondary
        }
    }
}
