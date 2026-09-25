# HANDOFF — Foundry Premium plan

Read this first if you are picking this work up (a new session, another machine, or another agent). Follow the `receive-handoff` rules: the state files named below are ground truth; continue, don't restart; never `reset`/`checkout`/`clean` existing work.

## Goal

`docs/plans/2026-09-25-foundry-premium-plan.md` — take Foundry (the macOS launcher app in this repo, NOT `launch-film/` and NOT `anvil/` the website) to a premium Raycast/TinyCast-grade product: polish, onboarding, feature parity, performance, deslop. Bump `VERSION` to `1.1.0` at the end.

**Explicitly out of scope for now (user's call): signing, notarization, Sparkle/autoupdate, DMG, Homebrew.** Do not work on distribution.

## State files (keep them updated — this is how a killed session resumes)

| File | Role |
| --- | --- |
| `docs/plans/2026-09-25-foundry-premium-plan.md` | Live plan (budgets filled in). The untouched original is `2026-09-25-foundry-premium-plan.ORIGINAL.md`. |
| `.devin/goal/report.md` | Progress ledger. Update after every completed unit. |
| This file | Orientation + how to work. |

All work lands as small commits on `main`. `git log --oneline` is the record of what is done. Stage exact files only — `launch-film/` (the film project) and `anvil/` (the marketing site) are tracked but separate concerns; don't include their changes in Foundry commits. `.devin/` is untracked goal state.

## Where things stand (1.1.0, 2026-09-26)

- The plan is complete except the items listed under "Open items" below. `VERSION` is `1.1.0`; release notes are in `docs/release-notes/1.1.0.md`.
- `swift test`: 531 tests, 0 failures (3 skipped, including the opt-in benchmark). `./scripts/build-app.sh`, `./scripts/verify-packaging.sh`, and `git diff --check` all pass.
- P0–P5: done (see `git log --oneline v1.0.0..HEAD`).
- P6: `docs/benchmarks/2026-09-26-foundry-1.1-report.md`. Every budget is met except bundle size, which is 552 KB over (the reason is in the report). This host has no Accessibility, so `scripts/drive-signposts.swift N --reopen build/Foundry.app` drives `panel.show` through the reopen handler, and `benchmark-launchers.swift --bundle <app> --runs 0` measures memory without posting key events.
- P7: deslop and structural pass, write-only `diagnosticsSummary` replaced with toasts, copy sweep, VoiceOver row activation, and a hidden main menu so ⌘C/⌘X/⌘A/⌘Z/⌘W work.

## Open items

1. The fresh-account manual sweep (onboarding reaches a first command within 30 s) and a live VoiceOver/focus-order walk need a GUI session with Accessibility granted to the terminal.
2. Live `search.immediate`/`search.complete` through real keystrokes: run `scripts/drive-signposts.swift 30` (hotkey mode) on a host that grants Accessibility.
3. Deferred refactors. Budgets are met without them, and they can't be UI-verified here: P6.1 `@Observable` migration, P6.2 lazy feature states, and splitting the 1,341-line `CommandPanelState` (extract a settings state object).
4. Liquid Glass render cost needs an Xcode 26 / Swift 6.2 build.
5. Distribution (signing, notarization, Sparkle, DMG, Homebrew) is still out of scope. Note: pushing a change to `VERSION` triggers `.github/workflows/release.yml`.

## Known flakes and quirks

- A hung `xctest`/`swift-test` process holds `.build` — if `swift test` says "Another instance of SwiftPM", find and kill the stale PID.
- `Task.sleep` in tests coalesces under load; suite had 3 timing flakes, now hardened via `Tests/FoundryTests/TestWaiting.swift` condition waits — prefer those over fixed sleeps.
- Offscreen dark-mode renders are unusable (`NSVisualEffectView`); light renders only.
- Sidekick delegation repeatedly failed with capacity errors — implement directly; it's not worth retrying.

## How to run

- Repo root: this directory. `Package.swift` declares `// swift-tools-version: 6.1` and builds with Swift 6.1 (Xcode 16.3, macOS 15 SDK) or 6.2 (Xcode 26). Liquid Glass (`glassEffect`) is compiled only under `#if compiler(>=6.2)`; 6.1 builds use the `NSVisualEffectView` fallback.
- `swift build` / `swift test` for the package; `./scripts/build-app.sh` stages `build/Foundry.app`; `./scripts/verify-packaging.sh` checks the bundle.
- Foundry commits must not sweep in `launch-film/` or `.devin/` changes.
