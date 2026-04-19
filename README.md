# KlinkMac

Ultra-low-latency mechanical keyboard sound emulation for macOS.

Any Mac keyboard, premium mechanical sound. Sub-10ms end-to-end latency, open source, free.

## Install

```bash
brew install --cask rockykusuma/klinkmac/klinkmac
```

Or download [`KlinkMac.dmg`](https://github.com/rockykusuma/klinkmac/releases/latest) and drag to Applications.

**First run:** launch → grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility → enable KlinkMac). The app lives in the menu bar — no Dock icon.

Requires macOS 13.0+.

## Features

- **15 bundled sound packs** — Cherry MX Blue / Brown / Red / Black (ABS + PBT), NK Cream, Topre, and more
- **Velocity-aware dynamics** — sound adapts to typing rhythm: fast → lighter clicks, slow → heavier thocks
- **Record your own pack** — use your mic to sample a real keyboard
- **Custom packs** — drag-drop any `.klinkpack` file to install
- **Meeting mute** — auto-silences during Zoom, Meet, Teams, Discord, FaceTime
- **App-aware profiles** — different pack per foreground app
- **Output routing** — send sounds to any audio device
- **Typing visualizer overlay** — floating click-through keyboard for streamers
- **Launch at login**

## Sound packs

**Install:** drag a `.klinkpack` onto the Packs tab in Preferences.  
**Record:** Preferences → Packs → Record Pack → type naturally.  
**Export:** hover any user pack → click the ↑ icon.  
**Format:** [`SOUND-PACK-FORMAT.md`](SOUND-PACK-FORMAT.md)

User packs live at `~/Library/Application Support/com.klinkmac.KlinkMac/Packs/`.

## Contributing

```bash
open KlinkMac/KlinkMac.xcodeproj
```

Set your Apple Developer team in **Signing & Capabilities**, then ⌘R.

Read [`ARCHITECTURE.md`](ARCHITECTURE.md) before touching the audio engine — the render callback has strict no-allocation / no-lock rules.

## License

MIT — see [`LICENSE`](LICENSE).
