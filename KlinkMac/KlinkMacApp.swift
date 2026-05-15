// App entry point — menu-bar-only, no Dock icon (LSUIElement = YES in Info.plist).
import SwiftUI

@main
struct KlinkMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appState = AppState()
    // Mirror themeID with @AppStorage so body re-evaluates on change.
    @AppStorage("themeID") private var themeID = "jade"

    var body: some Scene {
        let theme = KlinkTheme.find(id: themeID)

        MenuBarExtra {
            MenuBarView(appState: appState)
                .task { delegate.appState = appState }
                .environment(\.klinkTheme, theme)
        } label: {
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(appState: appState)
                .environment(\.klinkTheme, theme)
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
