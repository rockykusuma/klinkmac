// Multi-step onboarding with animated dark background and spring transitions.
import AppKit
import SwiftUI

struct OnboardingView: View {
    var appState: AppState
    @State private var step = 0

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    var body: some View {
        ZStack {
            AnimatedBlobBackground()

            VStack(spacing: 0) {
                ZStack {
                    if step == 0 {
                        StepIntro(onNext: advance)
                            .transition(stepTransition)
                            .id("s0")
                    }
                    if step == 1 {
                        StepPermission(appState: appState, onNext: advance)
                            .transition(stepTransition)
                            .id("s1")
                    }
                    if step == 2 {
                        StepTryIt(onNext: advance)
                            .transition(stepTransition)
                            .id("s2")
                    }
                    if step >= 3 {
                        StepDone(appState: appState)
                            .transition(stepTransition)
                            .id("s3")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StepDots(step: step, total: 4)
                    .padding(.bottom, 20)
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: appState.isTrusted) { _, trusted in
            if trusted && step == 1 { advance() }
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            step += 1
        }
    }
}

// MARK: - Step dots

private struct StepDots: View {
    let step: Int
    let total: Int
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == step
                          ? theme.accent
                          : (i < step ? theme.accent.opacity(0.45) : Color.klinkSurfaceHigh))
                    .frame(width: i == step ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
    }
}

// MARK: - Gradient button (shared across steps)

private struct GradientButton: View {
    let label: String
    let action: () -> Void
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [theme.accent, theme.secondary],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 0: Intro

private struct StepIntro: View {
    var onNext: () -> Void
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            WaveformView(isActive: true, barCount: 44)
                .frame(height: 72)
                .padding(.horizontal, 28)

            VStack(spacing: 10) {
                Text("Welcome to KlinkMac")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.klinkText)
                Text("Every keystroke transformed into the satisfying\nclick of a premium mechanical keyboard.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.klinkTextSecondary)
                    .lineSpacing(3)
            }

            GradientButton(label: "Get Started", action: onNext)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 1: Accessibility permission

private struct StepPermission: View {
    var appState: AppState
    var onNext: () -> Void
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.klinkWarning.opacity(appState.isTrusted ? 0 : 0.12))
                    .frame(width: 76, height: 76)
                    .animation(.easeInOut(duration: 0.3), value: appState.isTrusted)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(appState.isTrusted ? Color.klinkSuccess : Color.klinkWarning)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appState.isTrusted)
            }

            VStack(spacing: 10) {
                Text("Accessibility Permission")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.klinkText)
                Text("KlinkMac needs Accessibility access to detect\nkey presses. Your keystrokes are never stored.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.klinkTextSecondary)
                    .lineSpacing(3)
            }

            if appState.isTrusted {
                VStack(spacing: 16) {
                    Label("Permission granted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.klinkSuccess)
                    GradientButton(label: "Continue", action: onNext)
                }
            } else {
                VStack(spacing: 12) {
                    GradientButton(label: "Grant Permission") {
                        appState.accessibilityManager.requestPermission()
                    }
                    Button("I've enabled it — Continue") {
                        onNext()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.klinkTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.klinkSurfaceHigh,
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 2: Try it

private struct StepTryIt: View {
    var onNext: () -> Void
    @State private var keyCount = 0
    @State private var typedText = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill((keyCount >= 5 ? Color.klinkSuccess : theme.accent).opacity(0.12))
                    .frame(width: 76, height: 76)
                    .animation(.easeInOut(duration: 0.3), value: keyCount >= 5)
                Image(systemName: keyCount >= 5 ? "checkmark.circle.fill" : "hand.raised.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(keyCount >= 5 ? Color.klinkSuccess : theme.accent)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: keyCount >= 5)
            }

            VStack(spacing: 10) {
                Text("Try It Out")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.klinkText)
                Text(keyCount >= 5
                     ? "You can hear the click! KlinkMac is working."
                     : "Type in the field below to hear\nmechanical keyboard sounds with every key.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.klinkTextSecondary)
                    .lineSpacing(3)
                    .animation(.default, value: keyCount >= 5)
            }

            TextField("Type here…", text: $typedText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color.klinkText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.klinkSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    fieldFocused ? theme.accent.opacity(0.6) : Color.klinkSurfaceHigh,
                                    lineWidth: 1.5
                                )
                        )
                )
                .focused($fieldFocused)
                .frame(maxWidth: 280)
                .onAppear { fieldFocused = true }

            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < keyCount ? theme.accent : Color.klinkSurfaceHigh)
                        .frame(width: 10, height: 10)
                        .scaleEffect(i < keyCount ? 1.2 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: keyCount)
                }
            }

            if keyCount >= 5 {
                GradientButton(label: "Continue", action: onNext)
            } else {
                Button("Skip") { onNext() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.klinkTextSecondary)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: typedText) { _, new in
            if new.count > keyCount && keyCount < 5 { keyCount = min(new.count, 5) }
        }
    }
}

// MARK: - Step 3: Done

private struct StepDone: View {
    var appState: AppState
    @State private var appeared = false
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [theme.accent.opacity(0.2), theme.secondary.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 76, height: 76)
                Image(systemName: "star.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: "FBBF24"))
                    .scaleEffect(appeared ? 1.0 : 0.2)
                    .rotationEffect(.degrees(appeared ? 0 : -40))
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                    appeared = true
                }
            }

            VStack(spacing: 10) {
                Text("You're All Set!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.klinkText)
                Text(
                    "KlinkMac lives in your menu bar. Tap the keyboard\nicon to change packs, adjust volume, or pause."
                )
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.klinkTextSecondary)
                    .lineSpacing(3)
            }

            GradientButton(label: "Start Using KlinkMac") {
                appState.settings.hasCompletedOnboarding = true
                appState.ensureMonitorStarted()
                NSApp.keyWindow?.close()
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
