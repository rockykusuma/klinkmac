# Phase 3 — Usable by others

## Goal

Transition from "works on my machine" to "someone else can download, install, and enjoy it without help." This is the phase where KlinkMac becomes a real, shippable product.

## Ship criteria

- Finalized, documented sound pack file format
- Drag-and-drop pack installation
- Settings persist across app launches
- App can launch at login
- Signed and notarized DMG available for download
- A non-technical friend can install and use the app without you narrating every step

## Out of scope

- New pro features (Phase 4)
- Major latency work (should already be dialed in from Phase 2)
- iOS / Windows ports (not in scope, period)

## Deliverables

### 1. Formalized sound pack format

Implement the format specified in `specs/sound-pack-format.md`. Summary:

- Packs are directories (distributed as `.klinkpack` ZIP archives)
- Root contains `manifest.json` and a set of `.wav` files
- Manifest describes pack metadata, per-keycode sample mapping, and key-up overrides

File: `Packs/PackFormat.swift`.

```swift
public struct PackManifest: Codable {
    public let name: String
    public let author: String
    public let version: Int
    public let description: String?
    public let defaults: PackKeyMapping
    public let keys: [String: PackKeyMapping]   // key = keycode number as string
}

public struct PackKeyMapping: Codable {
    public let down: String?        // relative path to WAV
    public let up: String?
}
```

### 2. Pack loader (filesystem)

Extend `PackLoader`:

```swift
public final class PackLoader {
    public static func loadBundled(named: String) throws -> SampleBank
    public static func loadFromDisk(at url: URL) throws -> SampleBank       // unzipped directory
    public static func installPack(zipURL: URL) throws -> URL               // extracts to user packs dir, returns dir URL
}
```

- User packs directory: `~/Library/Application Support/com.yourid.KlinkMac/Packs/`
- Create the directory on first launch if missing
- `installPack` unzips the `.klinkpack` file, validates the manifest, copies to user packs dir
- Validation: manifest parses, all referenced WAVs exist, every WAV decodes successfully
- Reject packs with missing or malformed manifests with a clear user-facing error

### 3. Pack management UI

Add a proper Preferences window (SwiftUI, opened from the menu bar):

- **General tab:**
  - Pause shortcut customizer
  - Volume slider
  - "Launch at login" toggle
- **Packs tab:**
  - List of installed packs (bundled + user-installed)
  - Each pack row: name, author, version, "Active" indicator, "Delete" button (for user packs only)
  - Drag-and-drop target for `.klinkpack` files — accepting a drop invokes `installPack`
  - "Open Packs Folder" button (reveals the dir in Finder)
  - "Get more packs" link → your website (placeholder for now)
- **About tab:**
  - Version, build number
  - Link to website, GitHub, support email

Use `Settings { … }` scene in SwiftUI for proper macOS conventions.

### 4. Settings persistence

File: `Settings/SettingsStore.swift`.

- Backed by `UserDefaults` for primitives
- Keys: `isPaused`, `volume`, `activePackID`, `launchAtLogin`
- Use `@AppStorage` in SwiftUI views where practical
- On app launch, read the saved `activePackID` and load that pack. Fall back to a bundled default if the pack no longer exists

### 5. Launch at login

Use `SMAppService.mainApp.register()` and `.unregister()` (macOS 13+). This replaces the older `SMLoginItemSetEnabled` API.

- Binding in the Preferences → General tab
- Handle the possible `NSError` (e.g., user denied) gracefully — show an explanatory alert

### 6. Onboarding refinement

First-run experience:

- Window appears automatically with clear, friendly language
- Step 1: explains what KlinkMac does (one short paragraph, maybe with a tiny animated demo)
- Step 2: Accessibility permission request with the same text as Phase 0 but polished visually
- Step 3: "Try it out" — prompts user to type something and confirms they hear the sound
- Step 4: "You're all set" with a pointer to the menu bar icon

Do not skip straight to the permission dialog — context first.

### 7. App Sandbox reconsideration

CGEventTap with Accessibility inside the sandbox is possible but finicky. Decision for this phase:

- **Ship outside the sandbox initially.** We're distributing directly as a DMG, not via the Mac App Store. Outside the sandbox is simpler and has fewer edge cases
- Document this in `README.md` so future maintainers know
- If Mac App Store distribution becomes a priority later, a separate effort will port to sandbox

### 8. Code signing and notarization

- Enroll in the Apple Developer Program ($99/year) if not already
- Configure "Developer ID Application" signing in Xcode for Release builds
- Build script (`Tools/release.sh`) that:
  1. Builds the app in Release config
  2. Signs it with the Developer ID certificate
  3. Creates a DMG with `create-dmg` or `hdiutil`
  4. Notarizes the DMG via `xcrun notarytool submit`
  5. Staples the notarization ticket with `xcrun stapler staple`
- Smoke test: download the DMG on a different Mac, install, run. Gatekeeper should accept it.

### 9. Distribution

- Simple landing page at klinkmac.com (or the alternate domain you secured)
- Content:
  - One-line hero: "Mechanical keyboard sounds for any Mac. Lowest latency, no compromises."
  - Download button linking to the notarized DMG
  - Short demo video or GIF
  - Feature bullets: native, low-latency, customizable, privacy-respecting
  - Link to changelog / version history
- Host on GitHub Pages, Cloudflare Pages, or Vercel — static is fine
- Not required for this phase, but strongly recommended: set up [Sparkle](https://sparkle-project.org) for in-app auto-updates. Add the appcast URL to the Info.plist.

## Acceptance checklist

- [ ] `specs/sound-pack-format.md` is the authoritative reference; code matches it exactly
- [ ] Dragging a `.klinkpack` file onto the Preferences window installs it correctly
- [ ] Invalid / malformed packs show a clear error message, don't crash
- [ ] App state (volume, active pack, pause) survives quit-and-relaunch
- [ ] Launch-at-login toggle works: restart the Mac, app launches automatically
- [ ] Signed DMG opens and installs on a fresh Mac without Gatekeeper warnings
- [ ] A friend who has never seen the app can install and be typing with sound in under 2 minutes
- [ ] Preferences window looks native; uses system controls and follows macOS HIG

## Notes for Claude Code

- Avoid scope creep in this phase. The temptation is to add "just one more feature." Resist it
- The sound pack format is a contract. Once you ship Phase 3, changing it breaks every pack users have installed. Review `specs/sound-pack-format.md` critically before coding against it
- Test the full install-and-use flow on a second Mac or a fresh user account — it's the only way to catch onboarding bugs
- Code signing and notarization are finicky. Budget extra time. If Claude Code gets stuck on signing, ask the user to handle the Apple Developer portal steps manually
