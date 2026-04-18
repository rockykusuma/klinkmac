// Design tokens, theme system, shared components, and animated primitives for KlinkMac's dark UI.
import AppKit
import SwiftUI

// MARK: - Color tokens (static, non-themed)

extension Color {
    static let klinkBackground    = Color(hex: "0A0A0F")
    static let klinkSurface       = Color(hex: "1A1A2E")
    static let klinkSurfaceHigh   = Color(hex: "252540")
    static let klinkText          = Color(hex: "F1F5F9")
    static let klinkTextSecondary = Color(hex: "94A3B8")
    static let klinkSuccess       = Color(hex: "10B981")
    static let klinkWarning       = Color(hex: "F59E0B")

    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        assert(s.count == 6 && UInt64(s, radix: 16) != nil, "Invalid hex color: '\(hex)'")
        let v = UInt64(s, radix: 16) ?? 0
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double( v & 0xFF) / 255
        )
    }
}

// MARK: - Theme

struct KlinkTheme: Equatable, Identifiable {
    let id: String
    let name: String
    let accent: Color
    let secondary: Color

    static let indigo = KlinkTheme(
        id: "indigo", name: "Indigo", accent: Color(hex: "6366F1"), secondary: Color(hex: "8B5CF6"))
    static let grape = KlinkTheme(
        id: "grape", name: "Grape", accent: Color(hex: "A855F7"), secondary: Color(hex: "C084FC"))
    static let rose = KlinkTheme(
        id: "rose", name: "Rose", accent: Color(hex: "F43F5E"), secondary: Color(hex: "FB7185"))
    static let amber = KlinkTheme(
        id: "amber", name: "Amber", accent: Color(hex: "F59E0B"), secondary: Color(hex: "F97316"))
    static let jade = KlinkTheme(
        id: "jade", name: "Jade", accent: Color(hex: "10B981"), secondary: Color(hex: "34D399"))
    static let sky = KlinkTheme(
        id: "sky", name: "Sky", accent: Color(hex: "0EA5E9"), secondary: Color(hex: "38BDF8"))

    static let all: [KlinkTheme] = [.indigo, .grape, .rose, .amber, .jade, .sky]

    static func find(id: String) -> KlinkTheme {
        all.first { $0.id == id } ?? .indigo
    }
}

// MARK: - Theme environment

private struct KlinkThemeKey: EnvironmentKey {
    static let defaultValue = KlinkTheme.indigo
}

extension EnvironmentValues {
    var klinkTheme: KlinkTheme {
        get { self[KlinkThemeKey.self] }
        set { self[KlinkThemeKey.self] = newValue }
    }
}

// MARK: - Visual effect blur backdrop

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Animated waveform

struct WaveformView: View {
    var isActive: Bool
    var barCount: Int = 40
    var color: Color?
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        let barColor = color ?? theme.accent
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isActive)) { timeline in
            Canvas { ctx, size in
                let t       = timeline.date.timeIntervalSinceReferenceDate
                let spacing = CGFloat(2)
                let barW    = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)

                for i in 0..<barCount {
                    let fi    = Double(i)
                    let phase = fi * 0.45
                    let freq  = 1.8 + (fi.truncatingRemainder(dividingBy: 5)) * 0.35
                    let amp   = isActive
                        ? (sin(t * freq + phase) * 0.5 + 0.5)
                        : 0.08 + (fi.truncatingRemainder(dividingBy: 3)) * 0.04

                    let minH = CGFloat(isActive ? 4 : 2)
                    let barH = minH + CGFloat(amp) * (size.height - minH * 2)
                    let x    = CGFloat(i) * (barW + spacing)
                    let y    = (size.height - barH) / 2
                    let rect = CGRect(x: x, y: y, width: barW, height: barH)
                    let path = Path(roundedRect: rect, cornerRadius: barW / 2)
                    let alpha = isActive ? (0.4 + amp * 0.6) : 0.2
                    ctx.fill(path, with: .color(barColor.opacity(alpha)))
                }
            }
        }
    }
}

// MARK: - Custom drag slider

struct KlinkSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    @Environment(\.klinkTheme) private var theme

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let span     = range.upperBound - range.lowerBound
            let progress = CGFloat((value - range.lowerBound) / span)
            let w        = geo.size.width
            let thumbX   = progress * w

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.klinkSurfaceHigh)
                    .frame(height: 4)

                Capsule()
                    .fill(LinearGradient(
                        colors: [theme.accent, theme.secondary],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(thumbX, 4), height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: theme.accent.opacity(isDragging ? 0.7 : 0.4),
                            radius: isDragging ? 8 : 4)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .offset(x: max(thumbX - 7, -7))
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { g in
                        isDragging = true
                        let clamped = min(max(Double(g.location.x / w), 0), 1)
                        value = range.lowerBound + clamped * span
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Pill toggle

struct KlinkToggle: View {
    @Binding var isOn: Bool
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        ZStack {
            Capsule()
                .fill(isOn ? theme.accent : Color.klinkSurfaceHigh)
                .frame(width: 40, height: 22)
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .offset(x: isOn ? 9 : -9)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Animated blob background (onboarding only)

struct AnimatedBlobBackground: View {
    @State private var phase = false
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        ZStack {
            Color.klinkBackground
            blob(color: theme.accent, opacity: 0.35,
                 size: CGSize(width: 260, height: 180),
                 off1: CGPoint(x: -80, y: -100), off2: CGPoint(x: -40, y: -60))
            blob(color: theme.secondary, opacity: 0.28,
                 size: CGSize(width: 220, height: 200),
                 off1: CGPoint(x: 100, y: 80), off2: CGPoint(x: 60, y: 40))
            blob(color: Color(hex: "1E40AF"), opacity: 0.22,
                 size: CGSize(width: 200, height: 160),
                 off1: CGPoint(x: 20, y: 120), off2: CGPoint(x: -20, y: 80))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    @ViewBuilder
    private func blob(color: Color, opacity: Double,
                      size: CGSize, off1: CGPoint, off2: CGPoint) -> some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [color.opacity(opacity), .clear],
                center: .center,
                startRadius: 0,
                endRadius: max(size.width, size.height) / 2
            ))
            .frame(width: size.width, height: size.height)
            .offset(x: phase ? off1.x : off2.x, y: phase ? off1.y : off2.y)
            .blur(radius: 50)
    }
}
