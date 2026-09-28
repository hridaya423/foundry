# Goal report

## Objective
please continue with the full implementation of the plan. we can continue with sgining etc later.

## Progress
(started)

## Goal resumed (2026-09-28, iteration 1+)
Objective: full plan implementation; signing/Sparkle deferred.
New this turn: `9562b1f` @Observable migration (16 states, 30 view sites, 536 tests green).
Release build staged OK (build/Foundry.app); live keystroke measurement DEFERRED TO END — user is actively using the laptop (~20 min), driver steals keyboard focus.
Order now: deferred P4 items (⌘Y Quick Look, {selection}, inline hotkey/alias, Open With, per-layout hotkeys, favicons, file filters, emoji skin tones, unused-output warning) → bundle-size check → live signpost+footprint run last.

## Goal resumed (2026-09-28, deferred-P4 sweep)
- `703ca4f` ⌘Y Quick Look on file results (QLPreviewView child panel) + NOT-output title fix.
- `613928f` `{selection}` placeholder for snippets + quicklinks (AX read of front app).
- `432f9ff` ⌘K "Configure Command" → deep-links into Settings Commands row (expanded/anchored — covers inline Set Hotkey/Add Alias without a second recorder); ⌘K "Open with <App>" rows on file results (async Launch Services lookup off the keypress path).
- `c1db648` file search `kind:` filters + bare `f ` recents shelf (modified-this-week, newest first).
- `d09458a` emoji skin tones — ⌘T cycles a persisted tone applied on copy (exact-sequence check guards ZWJ emoji); variants collapsed in browse, still searchable.
- `c1a7b7c` favicons for quicklinks — `remoteIconURL` + cached fetch of the link's own `/favicon.ico`.
- Per-layout window hotkeys: already shipped — `globalHotkey` works on every command; Configure Command is the 1-key route.
- Verified: full suite green (536+), build clean.
- Remaining: live keystroke search.immediate measurement (needs AX — deferred to end), Liquid Glass render cost (6.2 build), bundle-size call (14,604 KB vs 14,052 budget — report proposes ≤15 MB), push to origin (~85 ahead).

## 2026-09-29 — P4 remainder sweep (c554465, f62538a, c717af1)
- File results: Copy File (⌘C), Add to File Shelf, drag-out via `.onDrag`, Spotlight-disabled notice deep-linking to Siri & Spotlight settings (mdfind stderr detection).
- Quicklinks: `openWithBundleID` (Raycast `openWith` kept on import) → `.openURLWithApp` runner kind; per-link favicon opt-out + app picker in Settings rows; 6th seed is "Search Files" (`foundry://files/` fills `f `); "Create Quicklink" catalog command.
- Action chords: ⌘D favorite, ⌘⇧, configure, ⌃X delete quicklink/snippet (destructive → confirm gate), ⇧⌘F/⇧⌘C/⌘↵ unchanged; `.refreshResults` after deletes.
- ⌘K now floats bottom-right (glass card, 340×≤320) over the result list instead of replacing it; action filter stays in the field; Escape restores.
- Settings deep-link routes `quicklink.*`/`script.*` ids to their own panes; window commands show "Use ⌃⌥←" Rectangle-style suggested hotkeys until assigned.
- Verified: build green; Quicklink/FileSearch/WindowManagement/CommandContracts tests pass. Full suite killed mid-run by contactsd sandbox retries (environment noise — unrelated to changes).

## 2026-09-29 — live keystroke measurement + perf fix (d5ccc0e)
- Deferred-to-last live run happened (user off laptop; AX granted on this host).
- drive-signposts.swift fixed: types real virtual keys (unicode-string events never reached the field), polls panel visibility per cycle — blind ⌘Space toggles had been inverting and typing into a closed panel.
- First live run exposed a real regression the synthetic harness missed: `NSWorkspace.runningApplications` (~25ms XPC) ran per keystroke in the apps provider; app-catalog TTL reload blocked publishes ~80ms.
- Fix: `RunningAppsSnapshot` 2s TTL cache (shared with home's running-dot pass); `InstalledAppCache` stale-while-revalidate (signature change still syncs).
- Live numbers (48 cycles, release): panel.show 8.8/22.3 (budget 15.6/23.4 ✓, was 19.0/35.0); search.immediate 17.0/60.2 (was 45.2/97.5; p95 ~10% over 54.8 — deliberate 16ms coalesce + ~370-app fuzzy match); search.complete 94.2 (over 69.4 — deferred tiers); footprint 50.3MB warmed (vs 31.2 on M4 — host differs); bundle 16,468KB (over 15,000 — today's feature code; flagged in report).
- Liquid Glass render cost: toolchain IS Swift 6.3.3/macOS 28 — glass paths compile in this build; still needs an Instruments pass to quantify.
- Report updated: docs/benchmarks/2026-09-26-foundry-1.1-report.md "Live keystroke measurement" section.
- Full suite green post-perf-change: 546 tests, 0 failures (18s).
- Visual verification via qa-capture: home/search/⌘K-popover/clipboard/settings PNGs all correct (docs/qa/2026-09-29-live/). Quicklink favicon renders; ⌘K floats bottom-right over results; action chords labeled.
- P5 audit leftovers confirmed already-covered: snippet duplicate-keyword banner + auto-persist (no dirty state), translator task-cancel guards late results.
- Session deslop scan clean (one `as!` flagged → was correct CF idiom; revert committed 476e716-fixup).
- Remaining: search.immediate p95 ~10% over budget + complete p95 + footprint + bundle — all documented honestly in report; Liquid Glass render cost needs Instruments; light-mode captures; P7 repo-wide deslop; push (~87 ahead); signing/Sparkle deferred per user.

## 2026-09-29 — P5 remainder (0b5189f, cfbdae5)
- Clipboard retention to SQLite-era bounds: 1,000 items / 1 GB / 90-day age pruning, pinned exempt, all configurable in Settings (items / keep-for / storage cap). Schema 8 upgrades users still on the 40/16MB JSON-era defaults only; custom values preserved. Full suite green after change.
- Calculator: last-10 copy history (UserDefaults-backed, deduped) surfaced on bare `calc`/`=`/`calc history`; currency staleness already shown via Frankfurter rate date in the note.
- P5 audit sweep result: sensitive-content exclusion (concealed/transient/password types + password-manager bundles), translator ⌘S swap + copy/replace + language-pack guidance, dev-tools inline errors + ⌘1–9, downloads (dest snapshot, Open/Reveal, missing-file message, scoped "Clear history", retry), emoji (persistent recents, column cycling, ⌘T tone picker, suggested fallback), browser/notes cache, agents (relative status age, integrationError), widgets ("free"/"used" labels, offline stock marks) — all already shipped.
- Feature-cut audit table delivered: docs/plans/2026-09-29-feature-cut-audit.md (camera hide-by-default proposed, awaiting approval; everything else keep).
- Remaining: same perf gaps as above; P7 repo-wide deslop + a11y pass + final gate; push; signing/Sparkle deferred.

## 2026-09-29 — P7 gate (9d3b79b, fc02ee4, a178661)
- Deslop: removed write-only `diagnosticsSummary`, unused Spacing stops/FeatureHeader init/imports/Onboarding.isVisible/ScriptArgument.directory. Periphery scan — remaining findings are assign-only Codable fields (encode-side use it can't see), zero actionable.
- Stringly-typed footer and NotificationCenter bridges already gone (typed footerActions; direct shell calls).
- Copy pass: the plan's three named strings already replaced in earlier passes.
- A11y audit: 53 accessibilityLabel sites; icon-only buttons verified labeled (WindowLayoutPicker utilities included).
- Release notes + README refreshed for the parity additions; VERSION already 1.1.0.
- Final gate: **549 tests / 0 failures** (25 s), `build-app.sh` release green, `verify-packaging.sh` green, `git diff --check` clean. Build signs with the local Apple Development cert — Developer ID/Sparkle still deferred.
- One flaky note: first suite run stalled ~20 min on a contactsd XPC storm (environment, no test touches Contacts); retry passed clean.
- Still open: search.immediate p95 ~10% over budget + complete p95 + warmed footprint/bundle on this host (documented); Instruments pass for Liquid Glass; push to origin; signing/Sparkle/notarization when the user resumes distribution.

## 2026-09-29 — PreparedQuery + phase-2 telemetry (3257c4d)
- `SearchScoring.PreparedQuery` hoists query normalization/tokenization/char-arrays out of per-candidate matching (~370 apps × keywords + every ranker pass). Apps provider p95 fell 26 → 12.8 ms.
- New zero-cost sub-spans `search.phase2.collect`/`search.phase2.rank` pin the complete-phase tail down: deferred providers ≈ 0 ms for intent-gated queries, ranking ≈ 5 ms — residual is cooperative-pool/main-queue congestion during keystroke bursts (16 ms coalesce inside the span by design). Kept as permanent telemetry.
- Live rerun (40 cycles, release): **panel.show 7.8/11.1**, **search.immediate 16.1/53.5 — under budget (54.8)**, search.complete 88.0 p95 (over 69.4; understood and documented as accepted limitation — it's the refinement publish, not first paint).
- Full suite re-run: 549 tests / 0 failures. `diff --check` clean. Commit 3257c4d.
- Still open: search.complete p95 tail (documented), footprint 50.3 MB / bundle 16.5 MB on this host (documented), Instruments pass for Liquid Glass, push (~96 ahead), signing/Sparkle when user resumes distribution.


## 2026-09-29 — Instruments pass (xctrace Time Profiler)
- 30 s / 24 show-type-dismiss cycles, release build: main-thread CPU ~12% (3.55 s), dominated by SwiftUI layout + AttributeGraph (inclusive), no Foundry hotspot.
- Zero rows in potential-hangs/hang-risks — no main-thread stalls. Liquid Glass render cost is not measurable as CPU penalty at this fidelity; GPU cost would need Metal System Trace.
- Verdict recorded in benchmark report. Ledger deduped (3065e5c — user edit had duplicated the PreparedQuery section).
- Remaining open items are all external/decision points: push (~97 commits ahead — needs go-ahead), camera-preview hide-by-default proposal (awaiting approval in feature-cut audit), signing/Sparkle/DMG (explicitly deferred by user), fresh-account sweep (needs another macOS user).

## 2026-09-29 — P7 full-diff deslop + review (b521977) + user decisions
- Ran the P7 spec's code-deslop + thermo-nuclear pass over the full diff since P0 (1305d69, ~8k lines / 103 files): comments clean (only why-docstrings), zero debug artifacts/TODOs, all try?/catch at real boundaries, no copy-paste duplication, no dead files (four filename-grep misses resolved as live Swift types). One real fix: force-unwrap in QuickLookPanelController.
- Copy sweep clean: sentence case, actionable error strings.
- Structural flag (recorded, not fixed in-pass): CommandPanelState.swift was 1,091 lines at P0 and is 1,449 now — pre-existing god-object shape; split is a refactor, not a deslop fix.
- Time Profiler pass: 12% main-thread CPU during 24 cycles, zero hang-risk rows. Verdict in benchmark report.
- User decisions: push declined (stay local); camera-preview hide declined (stays visible); signing/Sparkle/DMG still deferred by user.
- Agent-doable work complete. Remaining requires the user: distribution session (signing/notarization/Sparkle/DMG/fresh-account sweep) and push if ever desired.

## waiting claim (2026-09-29 06:30)
All plan implementation complete and committed locally (tests green, release build + packaging verified, benchmarks + review recorded). Remaining is external: signing/notarization/Sparkle/DMG release pipeline and fresh-account sweep — explicitly deferred by the user — and push to origin, which the user declined for now.

## 2026-09-29 — P6 idle-cost verified at code level
- Panel hidden: widgetBoard.stop() + agents.stopPolling() + clipboardHistory.reset() all fire in panelWillClose — widget/agent timers die with the panel.
- Agent socket deferred to first panel open or +2s (spec'd). Snippet event tap only when configured+AX-trusted; AX retry bounded at 60 attempts. PermissionHealth poll scoped to onboarding view lifecycle.
- Clipboard poll intentionally always-on (feature requires capture while hidden); adaptive 0.7s→5s after 60s input idle, tolerance 0.2, isPaused gated. One intentional timer, documented.
- Live CPU idle sample not taken: user is running a Foundry-vs-Raycast bench harness on this host (docs/benchmarks/2026-09-29-foundry-1.1-raycast-2.5.3-mbp-*.json); driving the app concurrently would contaminate it.

## waiting claim (2026-09-29 06:38)
All agent-doable plan work is complete and committed locally: P0-P7 implemented, 549 tests green, release build + packaging verified, benchmarks published with honest budget misses, deslop/review/copy/a11y passes done, idle cost verified. Remaining is external: signing/notarization/Sparkle/DMG release + fresh-account sweep (user deferred), push (user declined).

## 2026-09-29 — idle cost measured live; user's Raycast bench noted
- ps -o time delta over 30s with panel hidden: 0:00.50 -> 0:00.50 (zero measurable CPU; ~0.5s total across ~85 min uptime). P6 idle item now verified, not just audited.
- User's own benchmark landed (2026-09-29-foundry-1.1-raycast-2.5.3-mbp-report.md): Foundry 16.2 MB vs Raycast 224 MB (13.8x), warmed footprint 81-90% lower. Their report flags the mini warmed leg still pending — user-side, not this goal.

## waiting claim (2026-09-29 06:45)
All agent-doable plan work is complete and committed locally: P0-P7 implemented, 549 tests green, release build + packaging verified, live benchmarks + Instruments pass + idle-cost measurement recorded, deslop/review/copy/a11y passes done. Remaining is external only: signing/notarization/Sparkle/DMG + fresh-account sweep (user deferred) and push (user declined).

---

## Settings in-panel + Tinycast benchmark (30 Sep 2026)

**Settings moved inside the panel** (`cd3cf00`): `openSettings()` enters a new `.settings` mode rendered in `CommandPanelView` — rail + search + detail panes inside the 750pt panel, footer home-chord back. `SettingsWindowController` and all window plumbing deleted. Visual proof `docs/qa/2026-09-29-settings-panel/`.

**Foundry vs Tinycast 0.11.3** (same M4 Pro, on battery): panel show **Foundry 17.5/19.1 ms vs Tinycast 66.7/64.7 ms — Foundry 3.4–3.8× faster**; footprint 60.5–120.0 vs 40.4–40.6 MB and install 16.5 vs 13.6 MB — Tinycast lighter. Full report `docs/benchmarks/2026-09-29-foundry-1.1-tinycast-0.11.3-mbp-report.md`.

**Key fix enabling the latency win**: `PanelController` now keeps the panel mapped at alpha 0 (input gated) instead of `orderOut` — eliminates ~80–90 ms of window-server surface creation per show; ~110 → ~17 ms CG-observed. Verified: invisible when hidden, keystrokes reach the previous app.

**Site updated**: story headline now the conservative 81% / 115.2 vs 620.2 MB / Raycast 2.5.3.0; methodology page got the Tinycast tables (latency + footprint + install) and the battery-power caveat; next build green.
