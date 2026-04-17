# KlinkMac

Ultra-low-latency mechanical keyboard sound emulation for macOS.

## What it is

KlinkMac makes any Mac keyboard sound like a premium mechanical keyboard. Each keystroke triggers a pre-recorded sound from the currently active pack. The goal is imperceptible latency (sub-10ms end-to-end) with rock-solid consistency — better than any app currently on the market, paid or free.

## Why it exists

Existing options are either old and clunky (Mechvibes — Electron, ~30–50ms latency, no GUI for custom packs) or paid and closed-source (Klack, ~15ms latency, $4.99). KlinkMac is built for personal use first, with a potential pro tier if differentiating features emerge.

## Target

- **Platform:** macOS only, 13.0+ (Apple Silicon + Intel)
- **Audience initially:** personal use
- **Audience later:** mechanical keyboard enthusiasts, writers, focus-seekers, streamers
- **Competitor to beat on latency:** Klack

## Tech stack

- Swift 5.9+ and SwiftUI (with AppKit interop where required)
- CoreAudio via AVAudioEngine → custom AVAudioSourceNode
- CGEventTap for system-wide keystroke capture
- Swift Atomics for lock-free primitives
- No Electron, no web views, no cross-platform layers

## How to use this plan

The plan is organized as a progression of milestones. Work them in order.

1. Read `CLAUDE.md` — sets project-wide context for Claude Code
2. Read `ARCHITECTURE.md` — understand the threading model and why decisions were made
3. Read `ROADMAP.md` — see the full phase map
4. Start Phase 0 by handing `phases/phase-0-foundation.md` to Claude Code with "implement this phase"
5. Complete each phase's acceptance checklist before moving to the next
6. Refer to `specs/sound-pack-format.md` when working on pack-related features (Phase 1+)

See `GETTING_STARTED.md` for concrete hand-off instructions.

## Directory structure

```
klinkmac-plan/
├── README.md                         (this file)
├── CLAUDE.md                         (auto-loaded by Claude Code)
├── ARCHITECTURE.md                   (design decisions, threading)
├── ROADMAP.md                        (phase overview)
├── GETTING_STARTED.md                (Claude Code handoff instructions)
├── phases/
│   ├── phase-0-foundation.md         (end-to-end plumbing)
│   ├── phase-1-feel.md               (sounds like a real keyboard)
│   ├── phase-2-latency.md            (sub-10ms, zero dropouts)
│   ├── phase-3-usable.md             (shippable to others)
│   └── phase-4-usp.md                (pro-tier features)
└── specs/
    └── sound-pack-format.md          (pack file format spec)
```

## Current status

Planning complete. Ready to begin Phase 0.
