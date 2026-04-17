// App entry point — menu-bar-only, no Dock icon (LSUIElement = YES in Info.plist).
import SwiftUI

@main
struct KlinkMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .task { delegate.appState = appState }
        } label: {
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(appState: appState)
        }
    }
}

// Separate view so @Observable tracking updates the icon on isEnabled changes.
private struct MenuBarIcon: View {
    var appState: AppState
    var body: some View {
        Image(systemName: appState.isEnabled ? "keyboard.fill" : "keyboard")
    }
}
