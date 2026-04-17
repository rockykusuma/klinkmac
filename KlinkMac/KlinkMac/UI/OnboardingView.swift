// Multi-step first-run onboarding: intro → permission → try it → done.
import AppKit
import SwiftUI

struct OnboardingView: View {
    var appState: AppState
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            switch step {
            case 0:  StepIntro(onNext: { step = 1 })
            case 1:  StepPermission(appState: appState, onNext: { step = 2 })
            case 2:  StepTryIt(onNext: { step = 3 })
            default: StepDone(appState: appState)
            }
        }
        .frame(width: 480, height: 360)
        .onChange(of: appState.isTrusted) { _, trusted in
            if trusted && step == 1 { step = 2 }
        }
    }
}

// MARK: - Step 0: Intro

private struct StepIntro: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to KlinkMac")
                    .font(.title).bold()
                Text("KlinkMac plays mechanical keyboard sounds as you type — on any keyboard, in any app. It runs silently in your menu bar and never stores what you type.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }

            Button("Get started") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 1: Accessibility permission

private struct StepPermission: View {
    var appState: AppState
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Accessibility Permission")
                    .font(.title2).bold()
                Text("KlinkMac needs Accessibility access to detect key presses. This lets it respond to your typing without storing or transmitting any content.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }

            if appState.isTrusted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button("Open System Settings…") {
                    appState.accessibilityManager.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if appState.isTrusted {
                Button("Continue") { onNext() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 2: Try it

private struct StepTryIt: View {
    var onNext: () -> Void
    @State private var keyCount = 0

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: keyCount >= 5 ? "checkmark.circle.fill" : "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundStyle(keyCount >= 5 ? Color.green : Color.accentColor)
                .animation(.bouncy, value: keyCount)

            VStack(spacing: 8) {
                Text("Try it out")
                    .font(.title2).bold()
                Text(keyCount >= 5
                     ? "You can hear the sound! KlinkMac is working."
                     : "Start typing anywhere — you should hear mechanical keyboard sounds.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
                    .animation(.default, value: keyCount >= 5)
            }

            if keyCount < 5 {
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        Circle()
                            .fill(i < keyCount ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            if keyCount >= 5 {
                Button("Continue", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Skip", action: onNext)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Monitor global keystrokes using NSEvent monitor (passive, for counter only).
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in
                if keyCount < 5 { keyCount += 1 }
            }
        }
    }
}

// MARK: - Step 3: Done

private struct StepDone: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "star.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)

            VStack(spacing: 8) {
                Text("You're all set!")
                    .font(.title2).bold()
                Text("KlinkMac lives in your menu bar \(Image(systemName: "keyboard.fill")). Tap it to change packs, adjust volume, or pause. Enjoy the sounds!")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }

            Button("Close") {
                appState.settings.hasCompletedOnboarding = true
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
