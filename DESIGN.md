# Design

This document captures visual and interaction design decisions for KlinkMac. Claude Code should read this before implementing any UI and defer to these principles when the plan doesn't specify.

## Philosophy

KlinkMac is a utility, not an entertainment app. Design is restrained, confident, and unmistakably native. The product's quality shows in the latency and the sound, not in UI flourishes. Every screen should look like macOS — no attempt to reinvent conventions.

## Principles

1. **Native first.** macOS HIG in letter and spirit. No custom window chrome, no bespoke controls, no web-app feel.
2. **Menu bar first.** The primary interaction is a popover. Preferences is a secondary surface. No main window.
3. **Restrained color.** System accent for state indicators (active, info/selection). Otherwise monochromatic grays.
4. **Subtle brand.** No logo watermarks, no branded chrome. The keyboard glyph is the entire visual identity.
5. **Privacy trust.** Every screen that touches permissions should reinforce "your data stays on your Mac."

## Visual identity

- **Menu bar glyph:** `keyboard.fill` SF Symbol, monochrome foreground. A filled keyboard conveys "active"; switch to outlined `keyboard` when paused.
- **App icon (for Finder / cmd-tab):** same keyboard, centered on a subtle neutral gradient-less background. Flat, no shadow, no depth. Uses the system-standard iconset sizes (16, 32, 128, 256, 512, 1024).
- **Primary accent:** macOS system accent color (user-configurable — `NSColor.controlAccentColor`). Respect their system setting; do not override.
- **State colors:**
  - Active: system success green dot + "Active" label
  - Paused: system warning amber dot + "Paused" label
  - Attention/permission needed: system danger red indicator

## Typography

- Face: San Francisco (system default — do not bundle or override)
- Sizes:
  - Window title: 13px / weight 500
  - Section heading: 12px / weight 400 / color secondary / uppercase tracking 0.3px
  - Body (primary): 13px / weight 400
  - Body (secondary): 11px / weight 400 / color secondary
  - Numeric readouts (volume %, sizes): tabular-nums so digits don't jiggle
- Weights: 400 regular, 500 medium. Nothing heavier. No italic except for proper emphasis in prose.
- Sentence case everywhere. Never title case, never ALL CAPS.

## Dark mode

Fully automatic. Use SwiftUI's semantic colors (`Color.primary`, `Color.secondary`, `Color.accentColor`, `Color(nsColor: .windowBackgroundColor)`) or NSColor's dynamic color class in AppKit. Never hardcode a hex color. All three mockup surfaces must look correct in both modes with zero additional code.

## Surfaces

### Menu bar glyph
- Always visible when the app is running
- One symbol, no badges, no text
- Filled when active, outlined when paused — no other states

### Menu bar popover
- SwiftUI `MenuBarExtra(…, content: …)` with `.window` style (custom content, not NSMenu)
- Width: 300pt
- Structure (top to bottom):
  1. Header row — icon, app name, state label, pause/resume button (32pt tall)
  2. Volume slider row (label + value + slider, ~56pt tall)
  3. Hairline separator
  4. Sound pack section — section header + active pack (highlighted) + alternatives + "Browse packs…" link
  5. Hairline separator
  6. Preferences… (with ⌘, accessory)
  7. Quit KlinkMac (with ⌘Q accessory)
- All rows 36pt tall minimum for comfortable click targets
- Active pack gets `Color(nsColor: .selectedContentBackgroundColor)` background plus an accent-colored checkmark
- Alternative packs just show name + one-word descriptor ("Tactile", "Clicky") on the right
- No animations on pack selection — swap is instantaneous

### Preferences window
- Standard `Settings { … }` SwiftUI scene — macOS handles the toolbar and window chrome
- Three tabs: General, Packs, About
- Opens at 560pt wide, 520pt tall, resizable within reasonable bounds
- **General tab:**
  - Pause shortcut customizer (KeyboardShortcuts framework or equivalent)
  - Volume slider (duplicates the menu bar for convenience)
  - Launch at login toggle
  - Output device picker (Phase 4 if output routing ships)
- **Packs tab:**
  - List of installed packs as cards
  - Each card: app icon for bundled / recording icon for user-created, name, metadata line, "Active" badge or "Activate" button, overflow menu for user packs
  - Drop zone with dashed border for drag-and-drop install
  - Footer: "Open Packs Folder" and "Record your own…" on the left, "Browse pack library ↗" on the right
- **About tab:**
  - App icon, name, version, build
  - Links: website, GitHub, support email
  - Credits for sound sources
  - Acknowledgments for open-source dependencies

### First-run onboarding
- Single non-modal window, shown automatically when Accessibility permission is not granted
- Width: 520pt, height fits content (~400pt)
- Centered on main screen on first show
- Structure:
  1. Large 72pt keyboard icon in a rounded background tile
  2. Title: "One more step to get typing" (not "KlinkMac needs Accessibility access" — warmer)
  3. One paragraph explaining what KlinkMac does and why permission is needed
  4. Privacy pill with three items: ✓ Sees which key, ✗ Never what you type, ✗ Never leaves your Mac
  5. Two buttons: "I've granted it" (secondary), "Open System Settings" (primary, accent)
  6. Footer microcopy about revocation
- Auto-dismisses when permission is detected as granted (1-second polling via `Timer.publish`)
- Reappears if permission is revoked at runtime

## Component specs

### Buttons
- Height: 24pt default, 28pt for primary actions
- Corner radius: 6pt
- Border: 0.5pt secondary
- Padding: 12pt horizontal for secondary, 18pt for primary
- Primary action: accent background, white foreground
- Secondary action: transparent background, primary foreground, 0.5pt border

### Sliders
- Use stock SwiftUI `Slider` — do not customize
- Always paired with a label and a numeric readout (right-aligned, tabular-nums)

### Cards (in preferences)
- Background: `.windowBackgroundColor` or primary
- Border: 0.5pt tertiary
- Corner radius: 8pt
- Internal padding: 12pt
- Gap between cards: 8pt
- Active card gets a slightly brighter background (`.selectedContentBackgroundColor` at low opacity)

### Section headers
- 11–12pt, weight 500, color tertiary
- Padding: 4pt below, 8pt above
- No uppercase transformation in Swift — write the strings in the case you want

## Microcopy principles

- Active voice. "KlinkMac needs access" not "Access is needed."
- Lead with what we don't do when discussing privacy — it builds trust faster than leading with what we do.
- Button labels are verbs: "Activate", "Install", "Open", "Grant". Never "OK" or "Submit".
- Error messages describe the problem and the fix, not just the error. "Pack 'X' is missing 'space-down.wav' — the file was referenced in its manifest but not found" rather than "Invalid pack".

## Animation

- Minimal. No decorative motion.
- Pack switching: zero animation (bank swap is instant in Phase 2; visual reflects that).
- Volume changes: instant (audio is already real-time).
- Preferences tabs: native SwiftUI transition — do not override.
- The one place motion is welcome: the permission window gently dismissing when permission is detected as granted (a short `.opacity` fade, ≤200ms).

## Accessibility

- Respects "Reduce Motion" system setting (trivial since we have almost no motion)
- Full VoiceOver support on every control — label every `Toggle`, `Slider`, `Button` with a clear `.accessibilityLabel` modifier
- High-contrast mode: automatic via system colors
- Keyboard navigation: Preferences fully usable without a mouse (tab order, default-focused control, keyboard shortcuts)
- Dynamic Type: respect `@Environment(\.dynamicTypeSize)` where applicable — text should scale with system settings

## What this design deliberately does not do

- No onboarding "tour" beyond the permission screen
- No tooltips on standard controls — labels are explicit enough
- No logos or branding chrome inside the app itself
- No notifications, badges, or attention-grabbing affordances
- No in-app marketing for the pro tier (if it exists) — the website sells, the app serves

## Decisions deferred to implementation

- Exact color values: defer to system semantic colors; do not pick specific hexes
- Exact SF Symbol choice for the menu bar: `keyboard.fill` is the strong default, but if a more distinctive glyph becomes available, substitute with documentation
- Animation timing: use SwiftUI defaults unless there's a concrete reason to override
