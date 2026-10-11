# Goal report

## Objective
/gauntlet-loop work towards this high quality standard. make sure to commit in phases and work is not finished until all the phases are fully implemented.

Quality bar: Raycast. Plan: `docs/plans/2026-10-11-foundry-raycast-bar-audit.md` (56 findings).

## Progress

### Phase 0 — measurement lab ✅ (commit 9a64ed3)
- Signpost marks/spans for hotkey→panel-front, panel first-frame, keystroke→results, results commit (`DiagnosticsService`, `PanelController`, `CommandPanelState`, `CommandPanelView`)
- `scripts/drive-signposts.swift` extended with latency capture; `docs/benchmarks/2026-10-11-latency-budgets.md`
- `PanelShellTests`, `PanelHideGateTests`, `PanelKeyboardTests` added

### Phase 1 — window model + keyboard ✅ (commit 9a64ed3)
- Dismissal orders the panel out; focus returns to previous app via `AppActivation`; stays active when another Foundry window (onboarding) is visible
- Home never opens blank — cached snapshot + async reconcile
- Keyboard: navigation only traverses rendered rows; Esc clears query before closing and pops feature modes; footer shows the real preferred action; ⌘C/⌘V/⌘⌫ routed correctly through field editor first

### Phase 2 — search quality ✅ (commit 9f64945)
- Single scalar rank: `SearchMatchTier.score` + fuzzy nudge (< tier gap) + bounded usage frecency (< 0.15, can't cross tiers) + favorite nudge
- Flat result list — removed `ResultSection.ordered` re-bucketing that forced apps ahead of commands regardless of match strength
- Strict weak ordering, total tie-breaks — provider return order cannot leak into result order
- Stable-prefix merge: deferred-phase results can't reshuffle the head after the 120ms glance window or user interaction
- File search: in-process `NSMetadataQuery` replaces per-search `mdfind` spawn; results ranked by basename match quality (was raw Spotlight index order); Spotlight-disabled detected by a once-per-launch probe
- Kind labels describe the result kind (Application/File/Snippet/…) not the action verb
- New golden tests: `als` boundary-fuzzy case, weak-app-vs-strong-command, determinism under provider reorder, heavy-usage tier boundary
- Fixed flaky `ConversionGate` test helper (release-before-wait lost wakeup — suite deadlocked twice under load)

### Phase 3 — performance/data ✅ (commit 7778f1c)
- Clipboard poll runs only while the panel is open (`start`/`stop` on resetForOpen/panelWillClose/shutdown); launch does a one-shot capture — kills the 0.7 s runloop wake that ran forever
- ConfettiBurst's 60 fps `TimelineView` pauses while idle (was ticking an empty Canvas for the panel's whole life)
- Clipboard store: incremental diff-write (insert new / update changed pin+position / delete missing via keep-table) replaces the rewrite-every-row save; images live on disk keyed by signature, first 24 eager, rest lazy (`imageData(signature:)`, hydrated via `resolvedPayload`/`selectedItem`); fixed the empty-payload signature hazard; `policy.bounded` O(N²)→O(N)
- Direct paste: 750 ms staged-clipboard hold after ⌘V before restoring — slow targets no longer paste the old clipboard
- Icons: synchronous `cachedImage` seed for FileIcon/RemoteIcon (no placeholder flash), one shared URLSession+URLCache, top-12 results prewarmed, `scaleEffect(1.04)` resample removed
- Config writes: debounced 300 ms background persist (`flush` on terminate and before backup export, `discardPending` on restore); 100 rapid updates → 1 write (`persistedWriteCount`)
- Test speed: clipboard workload 35 s → ~1 s (unique payloads actually exercise bounds now — identical fixtures dedup'd to 1 row); scoring measure 10→3 iterations; OCR fixture 640×160→300×80
- D33 resolved: the `com.apple.dt.xctest` launch lines come from `RecapPerformanceTesting.framework`, loaded by AppKit on macOS 26 — OS behaviour, not Foundry code; no app-side fix exists
- Deferred (documented): FTS5 text index (in-memory filter over ≤1,000 items is cheap), at-rest encryption, thumbnail column, NSPasteboardItem lazy providers

### Phase 4.7 — readability (partial, this commit)
- All >240-char lines eliminated across `Sources/`; >300 golfed one-liners reformatted one-statement-per-line (OperationCoordinator, DependencyModels/Provisioning, ExecutableLocator, ProcessRunner, WindowPlacementMetadata, Translation provider/models, clipboard files, AI instruction strings → heredocs)
- `scripts/lint-lines.sh` added — gates Sources at 240 now; ~290 lines remain over the 160 target (ratchet tracked below)

### Phase 4.8 — dev-run safety ✅ (this commit)
- Removed the DEBUG `SMAppService.mainApp.unregister()` — `swift run` no longer unregisters the installed app's login item
- Rebuild+install over /Applications now requires explicit `INSTALL_APP=1`; a plain `swift run` runs the dev binary only

### Bug found via test-env fragility (this commit)
- `PanelController.hide()` ordered the panel out only inside an `NSAnimationContext` completion — in a headless/occluded context the completion never fires and the panel leaks onscreen. Added a 120 ms deadline failsafe (generation-guarded so a show() still wins); PanelShellTests that hung 3 s now pass in 0.3 s

### Verification evidence
- `swift build`: clean
- `swift test`: 625 tests, 0 failures, 5 skipped (~20 s; FOUNDRY_SLOW_TESTS-gated Vision cases skipped; CoreData/contactsd noise is environmental)
- Focused: 212 tests across reformatted areas pass; 3 PanelShellTests green incl. headless-compositing failsafe
- `scripts/lint-lines.sh --max 240`: PASS

## Remaining
- Phase 4: typed `ResultPayload` (79 prefix-check sites), `ResultAction` + ActionRunner generic executor, CommandPanelState split (~70 props), one persistence model (UserDefaults→FoundryConfig), @unchecked Sendable audit (59→≤10), `try?` audit (~200→<60), lint ratchet 240→160
- Phase 5: UI/UX — design tokens, row anatomy, alerts→in-panel forms, Settings window, Quick Look, materials/motion, copy, localization groundwork, accessibility
- Phase 6: platform — window tiling settle, Codex OAuth opt-in, CI snapshots
- Final: benchmark evidence, HANDOFF + report update, goalctl done

## Manual-only / environment-gated
- Accessibility-gated keystroke benchmarks, VoiceOver walkthrough, Liquid Glass cost check, notarization — documented in `docs/HANDOFF.md`, not falsely claimed
- Idle CPU/memory measured via `ps` (7–8% CPU, ~364 MB peak during audit)
