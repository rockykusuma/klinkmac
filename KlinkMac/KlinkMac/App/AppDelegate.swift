// NSApplicationDelegate for receiving file-open events (.klinkpack).
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Injected by KlinkMacApp after AppState is initialized.
    var appState: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "klinkpack" {
            appState?.installFromURL(url)
        }
    }
}
