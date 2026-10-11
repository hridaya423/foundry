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

### Phase 2 — search quality ✅ (uncommitted, staged for commit)
- Single scalar rank: `SearchMatchTier.score` + fuzzy nudge (< tier gap) + bounded usage frecency (< 0.15, can't cross tiers) + favorite nudge
- Flat result list — removed `ResultSection.ordered` re-bucketing that forced apps ahead of commands regardless of match strength
- Strict weak ordering, total tie-breaks — provider return order cannot leak into result order
- Stable-prefix merge: deferred-phase results can't reshuffle the head after the 120ms glance window or user interaction
- File search: in-process `NSMetadataQuery` replaces per-search `mdfind` spawn; results ranked by basename match quality (was raw Spotlight index order); Spotlight-disabled detected by a once-per-launch probe
- Kind labels describe the result kind (Application/File/Snippet/…) not the action verb
- New golden tests: `als` boundary-fuzzy case, weak-app-vs-strong-command, determinism under provider reorder, heavy-usage tier boundary
- Fixed flaky `ConversionGate` test helper (release-before-wait lost wakeup — suite deadlocked twice under load)

### Verification evidence
- `swift build`: clean
- `swift test`: 620 tests, 0 failures, 3 skipped (42.7s)
- Focused: 36 search tests pass; FileConversionTests 19/19

## Remaining
- Phase 3: performance/data — idle CPU ~7–8% (clipboard polling suspect), incremental clipboard persistence, lazy images, paste-restore race, icon cache, async config writes, test speed/determinism
- Phase 4: architecture — typed action payloads, CommandPanelState split (~70 props), one persistence model, @unchecked Sendable/try? audit
- Phase 5: UI/UX — design tokens, row anatomy, alerts→in-panel forms, Settings window, Quick Look, materials/motion, copy, localization groundwork, accessibility
- Phase 6: platform — window tiling settle, Codex OAuth opt-in, CI snapshots
- Final: benchmark evidence, HANDOFF + report update, goalctl done

## Manual-only / environment-gated
- Accessibility-gated keystroke benchmarks, VoiceOver walkthrough, Liquid Glass cost check, notarization — documented in `docs/HANDOFF.md`, not falsely claimed
- Idle CPU/memory measured via `ps` (7–8% CPU, ~364 MB peak during audit)
