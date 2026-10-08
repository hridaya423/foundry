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

## Where things stand (1.2.0, 2026-10-08)

- The megaplan (`~/.devin/plans/plan-2b52c0932c2a6746.md`) is implemented: P0 brand (custom `.icns` + designed DMG with Finder layout), P1 conversion graph/router over native+brew engines, P2 conversion UX + Finder-style file actions + `--convert`, P3 Downloads/Snippets/Clipboard facelift, P4 parity commands (OCR, color picker, QR gen/decode, plain paste, confetti), P5 onboarding motion + panel entrance, P6 perf (18 MB → 7.8 MB via pre-sign strip, icons off-main, async `lsof`, `CommandPanelState` split 1463 → 923+357+216), P7 release docs.
- `VERSION` is `1.2.0`; release notes are in `docs/release-notes/1.2.0.md`.
- `swift test`: 596 tests, 0 failures (3 skipped). `build-app.sh` produces a signed ~7.9 MB bundle; `package-dmg.sh` produces the branded DMG.
- Post-release gap pass closed the remaining spec items: `ConversionOptions` gained `stripMetadata` + `nameTemplate` (`{name}`/`{date}`/`{ext}` tokens); the graph gained pdf→txt, multi-PDF merge, and images→PDF via `FileConversionService.mergeToPDF`; ffmpeg honors `-map_metadata -1`, ImageMagick `-strip`, and video `quality` maps to CRF. Panel drops open a Shelf-vs-Convert chooser; file results gained Share. Snippets gained tag-filter chips, sort modes, CSV export, char count, and an expansion toggle on the surface. Clipboard gained merge-with-previous and image dimensions. Downloads gained row selection (⌫ removes), combined-speed footer, and a completion toast. New commands: Capture Text from Screen (`screencapture -i` + Vision), Wi-Fi QR Code, Empty Trash, Toggle Desktop Icons. Color picker now shows a format chooser (Hex/RGB/HSL/HSV/OKLCH/NSColor) plus a 12-item recents list. First successful conversion fires confetti + haptic once.
- Second gap pass (`dcc0148`): snippet root results honor a Settings-controlled Return-key preference (Insert vs Copy, plumbed via `CommandSearchRequest.snippetInsertAsPrimary`) and render a `SnippetPreview` pane with accent-tinted `{tokens}` + metadata rows. `FoundryConfig.hapticsEnabled` gates alignment/level-change taps on confetti, drop-accept, and snippet expansion (the expansion service receives the flag via `configure`). Downloads composer gained a multi-link count badge, ⌘V while unfocused, and link drop onto the composer. The color-picker alert reports WCAG contrast vs white/black. Quicklinks gained `isEnabled` with DuckDuckGo + Wikipedia preinstalled-but-off; the pane shows an Enabled checkbox + dims disabled rows. Clipboard ⌥↵ pastes plain text. Snippet export remembers its last directory. Onboarding footer uses width-morphing pills; step transitions scale-morph.
- New benchmark report: `docs/benchmarks/2026-10-08-foundry-1.2-report.md` — search.immediate p50 16.8 ms / p95 35.6 ms (p95 moved ~+11 ms on a larger result set, still ~2× under budget); bundle 14.6 MB → 8.1 MB.
- Heads-up for future sessions: this checkout is open in the Devin IDE, whose editor occasionally writes stale buffers over `ActionRunner.swift`/`ConversionService.swift` mid-edit — verify `git diff` after touching those files.

### Prior state (1.1.0, 2026-09-26)

- `docs/benchmarks/2026-09-26-foundry-1.1-report.md` — perf budgets; bundle size was 552 KB over then, now resolved by the strip step in P6.
- This host has no Accessibility, so `scripts/drive-signposts.swift N --reopen build/Foundry.app` drives `panel.show` through the reopen handler, and `benchmark-launchers.swift --bundle <app> --runs 0` measures memory without posting key events.
- P7 (1.1): deslop pass, toasts, copy sweep, VoiceOver row activation, hidden main menu.

## Open items

1. The fresh-account manual sweep (onboarding reaches a first command within 30 s) and a live VoiceOver/focus-order walk need a GUI session with Accessibility granted to the terminal.
2. Live `search.immediate`/`search.complete` through real keystrokes: run `scripts/drive-signposts.swift 30` (hotkey mode) on a host that grants Accessibility.
3. Deferred refactors. Done in 1.2: `CommandPanelState` split into `CommandPanelState.swift` (core/search/actions) + `+Settings` (config mutation, backup, command prefs) + `+Modes` (feature-mode navigation). Still open: P6.1 `@Observable` migration of remaining legacy state objects, P6.2 lazy feature states.
4. Liquid Glass render cost needs an Xcode 26 / Swift 6.2 build.
5. Distribution (notarization, Sparkle, Homebrew) is still out of scope; signing + designed DMG are done in-repo. Note: pushing a change to `VERSION` triggers `.github/workflows/release.yml`.

## Known flakes and quirks

- A hung `xctest`/`swift-test` process holds `.build` — if `swift test` says "Another instance of SwiftPM", find and kill the stale PID.
- `Task.sleep` in tests coalesces under load; suite had 3 timing flakes, now hardened via `Tests/FoundryTests/TestWaiting.swift` condition waits — prefer those over fixed sleeps.
- Offscreen dark-mode renders are unusable (`NSVisualEffectView`); light renders only.
- Sidekick delegation repeatedly failed with capacity errors — implement directly; it's not worth retrying.

## How to run

- Repo root: this directory. `Package.swift` declares `// swift-tools-version: 6.1` and builds with Swift 6.1 (Xcode 16.3, macOS 15 SDK) or 6.2 (Xcode 26). Liquid Glass (`glassEffect`) is compiled only under `#if compiler(>=6.2)`; 6.1 builds use the `NSVisualEffectView` fallback.
- `swift build` / `swift test` for the package; `./scripts/build-app.sh` stages `build/Foundry.app`; `./scripts/verify-packaging.sh` checks the bundle.
- Foundry commits must not sweep in `launch-film/` or `.devin/` changes.
