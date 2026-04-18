// Data model for app-aware sound pack profiles.
import Foundation

struct AppProfile: Codable, Identifiable, Sendable {
    var id: UUID
    var bundleID: String
    var packID: String
    var appName: String

    init(bundleID: String, packID: String, appName: String) {
        id = UUID()
        self.bundleID = bundleID
        self.packID = packID
        self.appName = appName
    }
}
