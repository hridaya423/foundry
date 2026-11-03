# HANDOFF — Foundry Premium plan

Read this first if you are picking this work up (a new session, another machine, or another agent). Follow the `receive-handoff` rules: the state files named below are ground truth; continue, don't restart; never `reset`/`checkout`/`clean` existing work.

## Goal

**Current workstream (2026-10-11):** `docs/plans/2026-10-11-foundry-raycast-bar-audit.md` — a harsh 56-finding audit of Foundry measured against **Raycast**. Phases 0–6: measurement lab → window/keyboard correctness → search quality → performance/data → architecture → UI/UX polish → platform. Work lands in **phased commits**; the goal ends when every phase is implemented. The user's bar: "every little detail to feel as polished as possible."

The earlier premium plan (`docs/plans/2026-09-25-foundry-premium-plan.md`) is fully implemented and shipped as 1.2.0 — see "Prior state" below.

**Explicitly out of scope for now (user's call): signing, notarization, Sparkle/autoupdate, DMG, Homebrew.** Do not work on distribution.

## State files (keep them updated — this is how a killed session resumes)

| File | Role |
| --- | --- |
| `docs/plans/2026-10-11-foundry-raycast-bar-audit.md` | Live plan — the audit with per-finding files, fixes, and acceptance criteria. |
| `docs/benchmarks/2026-10-11-latency-budgets.md` | Latency budgets from Phase 0 instrumentation. |
| `.devin/goal/report.md` | Progress ledger (tracked in git). Update after every completed unit. |
| This file | Orientation + how to work. |

All work lands as small commits on `main`. `git log --oneline` is the record of what is done. Stage exact files only — `launch-film/` (the film project) and `anvil/` (the marketing site) are tracked but separate concerns; don't include their changes in Foundry commits. `.devin/` is untracked goal state.

## Where things stand (2026-10-12 — Raycast-bar audit COMPLETE)

**All phases 0–6 are implemented** on branch `raycast-quality-overhaul` (18 commits, `2d94634`→`03cfe33`). Not yet merged to `main`. Gate at head: `swift build` + `swift build -c release` clean (0 warnings), **650 tests, 0 failures, 6 skipped**, `lint-lines.sh` PASS at 160, `lint-design.sh` PASS, `lint-l10n.sh` PASS, snapshot references compare-clean.

Phase ledger (see `.devin/goal/report.md` for detail):

- **4.5/4.1–4.3** — `@unchecked Sendable` 60→3 justified; typed `ResultPayload`; feature-owned `ResultAction` (ActionRunner 1551→136); `CommandPanelState` split.
- **Lint** — ratcheted to 160.
- **5.1/5.2/5.7/5.8** — `FoundryTheme` full vocabulary + `lint-design.sh`; row anatomy + QA shots; motion audit; hotkey formatter + copy pass.
- **5.3** — every `NSAlert` replaced by in-panel `PanelPrompt`; `runModal` remains only on `NSOpenPanel`/`NSSavePanel`.
- **5.4** — dedicated resizable Settings window (⌘, from app menu + status item); `.settings` panel mode deleted; reset applies live.
- **5.5** — native `QLPreviewPanel` Quick Look (Space + ⌘Y, follows selection, Esc closes preview first).
- **5.6** — material/appearance fixes: opaque mode uses `windowBackgroundColor` (black wash removed), Increase Contrast separator, Liquid Glass verified.
- **5.9** — localization groundwork: `Localizable.xcstrings`, `LocalizedStringResource` on String-typed UI surfaces, `lint-l10n.sh`, `build-app.sh` merges `.lproj` into the app bundle.
- **6.1** — `WindowFrameSettler`: size→position→size, accepts settled frame, rolls back only on AX-write errors.
- **6.2** — Codex OAuth behind explicit "ChatGPT sign-in (unofficial)" opt-in; enable path gated on acknowledgment.
- **6.3** — snapshot tests compare against checked-in light-mode references (pixel-diff tolerance); `.github/workflows/test.yml` runs lints + suite on push/PR.
- **6.4** — `LiveAppIndex` (`NSMetadataQuery`, `com.apple.application-bundle`, local volumes) merged with root enumeration; live updates invalidate the cache synchronously.

**Benchmarks:** `docs/benchmarks/2026-10-12-search-latency.md` — `search.immediate` p50/p95 16.9/23.0 ms, `search.complete` 17.4/24.1 ms (vs budgets ≤16/≤60). The 16 ms immediate p95 is the remaining gap — provider tail latency, not scoring. Wall-clock key-to-pixel numbers still need a GUI session with Accessibility (see Open items).

### Superseded — pre-overhaul baseline (kept for history)

Commits on `main` tell the story — newest first:

- `31d6760` **4.5 checkpoint (in flight):** first `@unchecked Sendable` batch flipped to checked `Sendable` (7 sites: AppSearchProvider, CommandRegistry, CommandRanker, AppleToolObserver, QuicklinkProvider, FileSnippetStore, DiagnosticsService). **The audit is mid-flight — pick up here.**
- `ac45bed` **4.6 failure visibility:** `try?` 204 → 78, all remaining classified intentional. `BestEffort.attempt`/`log` in FoundryServices logs best-effort failures at `.error`; `URL.fileResourceValues`, `FileManager.attributesIfPresent`/`contentsOfDirectoryIfPresent` non-throwing probe helpers. Fixed QR save (now alerts), corrupt `codex.json` clobber, empty-body Ollama requests.
- `0d835d6` **4.6 one persistence model:** all 20 `UserDefaults` app-state keys → `FoundryConfig.localState` + `UserDefaultsMigration` + `LocalStateStore` facade; backup restore applies live.
- `be79921` **4.7+4.8:** golfed files reformatted; `scripts/lint-lines.sh` gates at 240 (ratchet to 160 is tracked debt); `swift run` no longer unregisters/touches the installed app (`INSTALL_APP=1` opt-in).
- `7778f1c` **Phase 3:** idle burn (clipboard poll gated to panel-open, ConfettiBurst TimelineView paused when done), incremental SQLite clipboard writes, lazy clipboard images + `resolvedPayload` hydration, paste-restore hold window, debounced `ConfigService` writes + `flush`/`discardPending`, icon cache+prewarm, 35 s OCR test gated behind `FOUNDRY_SLOW_TESTS`.
- `9f64945` **Phase 2:** scalar `CommandRanker` (single score, stable order, golden fixtures incl. the `als` case), flat result list, simplified scheduler, `NSMetadataQuery` file search, kind labels.
- (earlier) **Phase 0+1:** `DiagnosticsService` signposts + `drive-signposts.swift` timing, nonactivating panel show, real hide on dismiss + focus return, Esc=clear-then-dismiss, ⌘C/⌘V/⌘⌫ text-editing correctness, footer verb honesty, minimal scrolling, navigable-list fix. `PanelController.hide` 120 ms failsafe.

**Baseline:** `swift build` clean, 0 warnings. `swift test`: **631 tests, 0 failures**, 5 skipped (~57 s). `scripts/lint-lines.sh` PASS at 240.

### Phase 4 — completed (superseded working notes)

All Phase 4 items landed on `raycast-quality-overhaul`: the `@unchecked Sendable` audit finished at 3 justified sites (method was compiler-driven flips onto `OSAllocatedUnfairLock<State>`), typed `ResultPayload` replaced id-prefix dispatch, feature-owned `ResultAction` shrank `ActionRunner` to a 136-line executor, `CommandPanelState` split into focused states, and `lint-lines.sh` ratchets at 160.

## Prior state (1.2.0, 2026-10-08)

- The megaplan (`~/.devin/plans/plan-2b52c0932c2a6746.md`) is implemented: P0 brand (custom `.icns` + designed DMG with Finder layout), P1 conversion graph/router over native+brew engines, P2 conversion UX + Finder-style file actions + `--convert`, P3 Downloads/Snippets/Clipboard facelift, P4 parity commands (OCR, color picker, QR gen/decode, plain paste, confetti), P5 onboarding motion + panel entrance, P6 perf (18 MB → 7.8 MB via pre-sign strip, icons off-main, async `lsof`, `CommandPanelState` split 1463 → 923+357+216, external-engine batch conversions parallelized at cap 2 with native engines staying sequential, markdown parse cache tightened to 50), P7 release docs.
- `VERSION` is `1.2.0`; release notes are in `docs/release-notes/1.2.0.md`.
- `swift test`: 602 tests, 0 failures (3 skipped). `build-app.sh` produces a signed ~8.1 MB bundle; `package-dmg.sh` produces the branded DMG.
- Review-findings pass (post-`7afe028`): fixed five conversion-state defects — Install & Convert now seeds `itemOutcomes` (it reported 0 files), `startOver()` closes its `OperationCoordinator` record, mutating sources mid-batch cancels+invalidates in-flight work, `installTool()` guards stale generations on every exit, and the Downloads completion haptic is injected + gated by `hapticsEnabled`. Also closed the review's real spec gaps: clipboard row hover actions (copy / paste / OCR / remove) and image OCR + barcode decode affordances, File Shelf OCR/barcode context actions, download "Redownload", QR "Save as PNG…" (injectable `offerQRSave` — modal code must never run under tests), conversion-result Quick Look + Share buttons, a searchable format picker (>8 targets), try-it confetti with a cancellable 1.2 s advance, panel-entrance `CASpringAnimation` settle, action-panel spring, Keep Awake in the status menu (with on-state), snippet-expansion `recordUse` by snippetID, and a per-batch completion haptic. Corrected the clipboard footer to the real keymap: ↵ Paste, ⌘↵ Copy, ⌘P Pin.
- Post-release gap pass closed the remaining spec items: `ConversionOptions` gained `stripMetadata` + `nameTemplate` (`{name}`/`{date}`/`{ext}` tokens); the graph gained pdf→txt, multi-PDF merge, and images→PDF via `FileConversionService.mergeToPDF`; ffmpeg honors `-map_metadata -1`, ImageMagick `-strip`, and video `quality` maps to CRF. Panel drops open a Shelf-vs-Convert chooser; file results gained Share. Snippets gained tag-filter chips, sort modes, CSV export, char count, and an expansion toggle on the surface. Clipboard gained merge-with-previous and image dimensions. Downloads gained row selection (⌫ removes), combined-speed footer, and a completion toast. New commands: Capture Text from Screen (`screencapture -i` + Vision), Wi-Fi QR Code, Empty Trash, Toggle Desktop Icons. Color picker now shows a format chooser (Hex/RGB/HSL/HSV/OKLCH/NSColor) plus a 12-item recents list. First successful conversion fires confetti + haptic once.
- Second gap pass (`dcc0148`): snippet root results honor a Settings-controlled Return-key preference (Insert vs Copy, plumbed via `CommandSearchRequest.snippetInsertAsPrimary`) and render a `SnippetPreview` pane with accent-tinted `{tokens}` + metadata rows. `FoundryConfig.hapticsEnabled` gates alignment/level-change taps on confetti, drop-accept, and snippet expansion (the expansion service receives the flag via `configure`). Downloads composer gained a multi-link count badge, ⌘V while unfocused, and link drop onto the composer. The color-picker alert reports WCAG contrast vs white/black. Quicklinks gained `isEnabled` with DuckDuckGo + Wikipedia preinstalled-but-off; the pane shows an Enabled checkbox + dims disabled rows. Clipboard ⌥↵ pastes plain text. Snippet export remembers its last directory. Onboarding footer uses width-morphing pills; step transitions scale-morph.
- New benchmark report: `docs/benchmarks/2026-10-08-foundry-1.2-report.md` — search.immediate p50 16.8 ms / p95 35.6 ms (p95 moved ~+11 ms on a larger result set, still ~2× under budget); bundle 14.6 MB → 8.1 MB.
- Heads-up for future sessions: this checkout is open in the Devin IDE, whose editor occasionally writes stale buffers over `ActionRunner.swift`/`ConversionService.swift` mid-edit — verify `git diff` after touching those files.

### Prior state (1.1.0, 2026-09-26)

- `docs/benchmarks/2026-09-26-foundry-1.1-report.md` — perf budgets; bundle size was 552 KB over then, now resolved by the strip step in P6.
- This host has no Accessibility, so `scripts/drive-signposts.swift N --reopen build/Foundry.app` drives `panel.show` through the reopen handler, and `benchmark-launchers.swift --bundle <app> --runs 0` measures memory without posting key events.
- P7 (1.1): deslop pass, toasts, copy sweep, VoiceOver row activation, hidden main menu.

## Website (2026-11-01, "last 20%" plan)

Plan: `docs/plans/2026-11-01-foundry-last-20.md`. Evidence: `docs/qa/2026-11-01-website/README.md` (before, after, final). Brand: `docs/brand/BRAND.md`, tokens in `docs/brand/tokens.json` (generated into `anvil/app/foundry/tokens.css` and `tokens.ts` by `npm run tokens`).

- Mark: Split Mould (`docs/brand/mark/`). Site nav, favicon, app icon, menu bar glyph and the onboarding cast all draw it.
- Pages: `/proof` (figures from `docs/benchmarks/latest.json`, written by `scripts/write-benchmark-summary.mjs`), `/changelog` + `/changelog/feed.xml` (parsed from `docs/release-notes/*.md`; a new release needs a date in `releaseDates` in `anvil/app/changelog.ts`), `/privacy` (claims proven in `docs/qa/2026-11-01-website/privacy-claims.md`), `/brand` (kit zip built by `anvil/scripts/build-brand-kit.mjs`).
- ⌘K palette on every page (`anvil/app/foundry/palette.tsx`, commands in `palette-commands.ts`). Section hashes (`/#tools`) jump to story stops.
- Version comes from `VERSION` via `next.config.ts`. The download modal is gone: releases must be notarized.
- Checks: `npm test` (site unit tests), `npm run qa` (screenshots, axe, Lighthouse; `--trace` with `QA_GPU=1` for first paint and long tasks).

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
