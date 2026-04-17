# Phase 4 — USP features

## Goal

Identify and ship one differentiating feature that makes KlinkMac worth paying for (if you choose to commercialize) or that you personally want to use daily (if you stay free).

## Ship criteria (per feature)

- The feature works end-to-end without degrading the latency or stability achieved in Phases 0–3
- The feature has a clear user-facing explanation
- Measurable benefit: a user can state what changed and why they'd want it

## Important note

This phase is intentionally less detailed than the earlier phases. The right USP will be informed by what you learn from using the app yourself through Phases 0–3. Don't plan too far ahead — pick a feature from this list (or invent a new one) once you've been living with KlinkMac for a while.

## Candidate features

### A. Record-your-own-pack

**Pitch:** user holds their mic up to their real mechanical keyboard, types, and KlinkMac auto-generates a pack from the recording.

**Why it's great:** every user becomes a content creator. Shareable. Uniquely impressive demo.

**Sketch:**
- Recording UI: large "hold to record" button, level meter, countdown
- Audio processing: silence-threshold-based segmentation to isolate individual keystrokes
- User taps the same few keys in a guided sequence (e.g., "tap Space 5 times", "tap Enter 5 times") so the app knows which recording belongs to which key
- Normalize loudness across samples
- Output: a new pack in `~/Library/Application Support/.../Packs/` ready to use

**Technical risk:** mic quality varies wildly. Auto-segmentation may be flaky. Mitigate by letting users manually trim each sample before saving.

### B. Meeting mute

**Pitch:** KlinkMac detects when Zoom, Meet, Teams, or Discord is actively using the microphone and silences itself so coworkers don't hear a mechanical keyboard over your voice.

**Why it's great:** solves a real, constant annoyance. Opt-in default-on. Table-stakes for professional use.

**Sketch:**
- Monitor the active input audio device via CoreAudio property listeners
- Detect processes using the mic via `kAudioHardwarePropertyProcessInputMute` or by polling `ps`/process listings for known videoconferencing apps
- When a monitored app becomes active and has mic access, set a `shouldMute` flag
- Multiple modes: "mute always when on a call", "mute only if my mic is hot", "route sounds to my headphones only"

**Technical risk:** detecting "on a call" is surprisingly fiddly. Start with the simplest heuristic (foreground app matches a list) and iterate.

### C. App-aware profiles

**Pitch:** different sound pack depending on foreground app. Cherry Blue while coding in Xcode, soft Topre while writing in Obsidian, silent when Slack is focused.

**Why it's great:** feels magical once configured. Deeply personal.

**Sketch:**
- Profile = `{ appBundleID: String, packID: String }`
- On `NSWorkspace.didActivateApplicationNotification`, check profiles, swap the active bank if there's a match
- UI in Preferences: "Profiles" tab, add/edit/delete rules
- Fallback to the default pack if no rule matches

**Technical risk:** pack-swapping during typing must continue to be glitch-free (already solved in Phase 2).

### D. Typing visualizer overlay

**Pitch:** optional floating overlay showing keys as they press, with customizable styles. Great for streamers and tutorial creators.

**Why it's great:** taps into the Twitch / YouTube audience. Easy viral demo.

**Sketch:**
- Separate, optional window (borderless, always-on-top, click-through)
- Subscribes to the same `EventQueue` the audio engine drains from (tee the queue into two consumers)
- Renders a keyboard layout; keys light up on press with customizable color/animation
- Skinnable via simple JSON themes (reuse the pack format ideas)

**Technical risk:** the audio engine is currently the sole consumer of the queue. Moving to multi-consumer means either broadcasting from the tap thread or a separate queue for the visualizer. The latter is cleaner.

### E. AI-generated packs

**Pitch:** user types a prompt ("sounds like a 1970s Olivetti typewriter with a slight echo") and the app generates a coherent pack using an audio generation model.

**Why it's great:** unique, demo-friendly, expansive library for free.

**Sketch:**
- Call a text-to-audio API (Stability Audio, ElevenLabs Sound Effects, etc.)
- Generate 5–10 variations per key type (down, up; letter, space, enter, backspace)
- Post-process: normalize, trim silence
- Save as a new pack

**Technical risk:** output quality is hit-or-miss; costs money per generation. Probably belongs behind a Pro tier explicitly to cover API costs.

### F. Output routing

**Pitch:** route keyboard sounds only to specific audio devices (e.g., headphones only, never speakers; or to a virtual loopback so they show up in OBS).

**Why it's great:** niche but beloved by power users. Nearly zero complexity if done right.

**Sketch:**
- CoreAudio lets you target a specific output device for an engine
- UI: dropdown in Preferences listing available output devices, plus "system default"
- When user selects a specific device, instantiate the `AVAudioEngine` targeting that device's `AUHAL`

**Technical risk:** low. This is the safest Phase 4 feature to ship first.

## Recommended order if pursuing multiple

1. **Meeting mute** — biggest everyday value, easy to validate
2. **Output routing** — simple, unlocks streamer use case
3. **Record-your-own-pack** — high wow-factor, differentiates from competitors
4. **App-aware profiles** — feels good once configured, relatively simple
5. **Visualizer overlay** — only if streamer audience is a target
6. **AI-generated packs** — save for last, highest risk/reward

## Pro tier question

Don't answer "paid or free?" until you've shipped at least one Phase 4 feature and seen reactions. If you do commercialize:

- Free: Phases 0–3 functionality, 3 bundled packs
- Pro ($4.99 one-time or $1/month): all Phase 4 features, additional pack library, priority support

Match Klack's price point as a reference anchor.

## Acceptance checklist (per feature)

Customize this per feature. General template:

- [ ] Feature has a clear toggle / entry point in the UI
- [ ] Feature does not regress Phase 2's latency numbers
- [ ] Feature has a failure mode that's graceful (no crashes, clear error messages)
- [ ] Feature's purpose is self-evident to a user without reading docs

## Notes for Claude Code

- Don't start Phase 4 until Phases 0–3 are genuinely done and the app has been in daily use for at least a few weeks. The right USP becomes obvious from use
- Each Phase 4 feature is big enough to warrant its own mini-plan. When you're ready to start one, create `phases/phase-4-feature-name.md` with detailed deliverables and acceptance criteria
- Prototype hard and fast. The cost of a bad Phase 4 feature is the UI mess it leaves behind — be willing to rip out features that don't earn their place
