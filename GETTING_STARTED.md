# Getting started with Claude Code

How to actually run this plan.

## One-time setup

1. Install Claude Code if you haven't: follow the instructions at `claude.com/code`
2. Copy this entire `klinkmac-plan/` directory into a new folder that will become your repo root
3. `cd` into that folder and run `claude` to start a Claude Code session

Claude Code auto-discovers `CLAUDE.md` and loads it as context, so it'll know the non-negotiables and code style before you ask anything.

## Starting Phase 0

In your first session, paste something like:

```
We're building KlinkMac — see README.md and CLAUDE.md for context.
Please read ARCHITECTURE.md, ROADMAP.md, and phases/phase-0-foundation.md,
then implement Phase 0. Follow the acceptance checklist at the bottom of
the phase doc. Let me know when each deliverable is complete so I can
review before moving on.
```

## Phase hand-off pattern

For each phase:

1. Point Claude Code at the phase doc: "Please read `phases/phase-N-*.md` and implement it"
2. Let it work in chunks; review deliverables as they land
3. When the acceptance checklist is satisfied, commit and move to the next phase
4. If it runs into something the plan didn't anticipate, have it propose an amendment to the phase doc before implementing

## Recommended workflow

- Use git from day one. Commit per deliverable, not per phase
- Keep one branch per phase (`phase-0`, `phase-1`, etc.) if you want clean history
- Run Instruments (Audio System Trace) before and after any change that touches the audio path — keep measurements in a `LATENCY_LOG.md` file
- When Claude Code modifies files, skim the diffs before accepting — especially anything touching the render callback

## When things go wrong

- **Permission flow is stuck:** nuke the Accessibility entry for KlinkMac in System Settings and re-launch
- **Audio dropouts:** open Instruments → Audio System Trace. If the render thread is missing its deadline, the culprit is almost always an allocation, lock, or log call you added in the render path. Check commits since the last clean run
- **Build fails after Claude Code changes:** have it review the error; most common cause is Swift concurrency warnings from `Sendable` checking or missing `@MainActor` annotations

## Stopping points

Each phase has a clean stopping point. If you need to pause the project for weeks or months, finish the phase you're in before stopping — partial phases rot fast.
