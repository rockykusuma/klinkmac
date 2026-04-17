// Menu bar dropdown: toggle, pack picker, volume, preferences, quit.
import SwiftUI

struct MenuBarView: View {
    var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(appState.isEnabled ? "Pause" : "Resume") {
            appState.isEnabled.toggle()
        }

        Divider()

        Menu("Pack") {
            ForEach(appState.installedPacks) { pack in
                Button {
                    appState.selectPack(pack)
                } label: {
                    HStack {
                        Text(pack.name)
                        if appState.activePack?.id == pack.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Stepper(
            "Volume: \(Int(appState.volume * 100))%",
            value: Binding(
                get: { Double(appState.volume) },
                set: { appState.volume = Float($0) }
            ),
            in: 0...1,
            step: 0.05
        )

        Divider()

        Button("Preferences…") { openSettings() }
            .keyboardShortcut(",")

        if !appState.isTrusted {
            Button("Grant Accessibility Permission…") {
                appState.accessibilityManager.openSystemSettings()
            }
        }

        Divider()

        Button("Quit KlinkMac") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
