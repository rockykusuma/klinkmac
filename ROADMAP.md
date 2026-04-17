# Roadmap

Each phase is independent and shippable on its own. Don't pull work forward from later phases — early phases are intentionally ugly to reduce integration risk before optimization.

## Phase 0 — Foundation

**Goal:** prove the pipeline works end-to-end. Ugly UI, one hardcoded sound.

**Ship criteria:**
- Type in any app → hear a sound
- Menu bar toggle works
- Accessibility permission flow handles grant/deny/revoke

**Effort:** 1–2 days
**Doc:** `phases/phase-0-foundation.md`

## Phase 1 — Feel

**Goal:** sounds like a real mechanical keyboard, with distinct keys and natural variation.

**Ship criteria:**
- Multiple distinct sounds per keycode (spacebar, enter, alphanumerics)
- Distinct key-down and key-up sounds
- Natural pitch variation — no robotic loop feel
- Three bundled packs switchable live

**Effort:** 3–5 days
**Doc:** `phases/phase-1-feel.md`

## Phase 2 — Latency

**Goal:** sub-10ms end-to-end, measured, consistent, zero dropouts at 150 WPM.

**Ship criteria:**
- Measured latency <10ms via Audio System Trace in Instruments
- No dropped events at sustained 150 WPM typing
- CPU usage on audio thread <5% on Apple Silicon at full polyphony

**Effort:** 2–4 days (including profiling)
**Doc:** `phases/phase-2-latency.md`

## Phase 3 — Usable by others

**Goal:** a friend can install and use the app without help.

**Ship criteria:**
- Formalized sound pack format with loader
- Drag-and-drop pack install
- Settings persistence (relaunches remember state)
- Launch-at-login support
- Signed, notarized DMG available for download
- First-run onboarding that doesn't confuse non-technical users

**Effort:** 4–7 days
**Doc:** `phases/phase-3-usable.md`

## Phase 4 — USP features (pro tier candidates)

**Goal:** differentiating features that justify a paid tier.

**Ship criteria:** one killer feature ships and works end-to-end.

**Candidates (pick one to start):**
- Record-your-own-pack (auto-segment real keyboard recording into a pack)
- Meeting-mute (auto-silence when Zoom/Meet/Teams is on a call)
- App-aware profiles (different pack per foreground app)
- Typing visualizer overlay (for streamers)
- AI-generated packs from a text prompt

**Effort:** open-ended per feature
**Doc:** `phases/phase-4-usp.md`

## Sequencing rule

Each phase's acceptance checklist must pass before starting the next. If you discover a blocker mid-phase, fix it in-phase rather than pushing forward.
