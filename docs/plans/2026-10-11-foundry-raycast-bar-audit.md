# Foundry vs. the Raycast bar: audit and remediation plan

> **For the executor:** work phase by phase. Every task lists files, the change, and an acceptance check. Run `swift test` (whole suite) only at phase gates. Use the narrowest test filter (`swift test --filter <Suite>`) per task. Don't sweep `foundry-ad/`, `launch-film/`, `anvil/`, or `.devin/` into Foundry commits.

**Goal:** make Foundry *feel* like Raycast. That means instant, invisible when dismissed, honest about what Return will do, and keyboard-perfect, with a codebase that can absorb new features without editing the same 17 switches.

**Evidence base (2026-10-11):** full read of the shell (`PanelController`, `ShellController`, `HotkeyController`, `DirectPasteService`), panel state and view, the search pipeline (`CommandRegistry`, `CommandProviderScheduler`, `CommandRanker`, `ResultSections`), clipboard store, config, theme and rows, plus targeted reads elsewhere. Runtime: clean `swift build` (0 warnings), `swift test` (603 tests, 0 failures, 3 env-skipped, 77 s), `build-app.sh` (8.2 MB bundle), passive sampling of a running build, and one live screenshot (`/tmp/foundry-audit/shots/home.png`, query "als").

Each finding is labelled **[verified]** (read in code or measured) or **[hypothesis]** (strongly suggested, needs the listed check before you fix it).

---

## Part 1 — The critique

### What is defensible

- **Builds clean** (0 warnings on Swift 6.4) and has **603 green tests**. That's rare for a solo app this size.
- **Real engineering in places:** the staged and atomic `ArtifactStore`, the conversion graph router, and generation-guarded async in `FileConversionState`. The clipboard capture respects concealed and transient pasteboard types, and the snippet tap checks `IsSecureEventInputEnabled`.
- The **post-dismiss HUD** (`TransientNoticeController`) is the right Raycast pattern.
- The **hotkey layer** (Carbon `RegisterEventHotKey`, with rollback when a command-hotkey registration fails) is correct and boring, as it should be.
- The **bundle is small** (8.2 MB), and **process spawn takes about 90 ms**.

Everything else falls short of the bar. In rough order of how much it hurts:

### A. Shell and window model: the launcher never actually goes away (P0)

1. **[verified] The panel is never ordered out, and Foundry never gives focus back.** `ShellController.showPanel()` calls `NSApp.activate(ignoringOtherApps: true)`, which defeats `.nonactivatingPanel`. `PanelController.hide()` only fades alpha to 0, sets `ignoresMouseEvents` and `inputEnabled=false`, and leaves the window ordered in at `.statusBar` level on every Space. Nothing deactivates the app or reactivates the previous one unless a paste is pending. Your own 1.2 benchmark report admits it: *"the panel does not hide on app deactivation."* Raycast's contract is that on dismiss, the previous app is frontmost and keystrokes go there. **[hypothesis to confirm in 10 s]** Press Esc and start typing. Characters likely don't reach the previous app until you click.
2. **[verified] Two stacked entrance animations, and one breaks your own rule.** AppKit runs an alpha fade plus a `CASpringAnimation` translate (with a comment saying *"a scale transform resamples the layer and every row renders soft"*). Then SwiftUI's `replayPresentation()` runs `scaleEffect(0.97→1)` and `opacity(0→1)` after a `DispatchQueue.main.async` hop. Result: the first presented frame is empty, and the rows render soft during the settle. Raycast shows content on frame 1.
3. **[verified] Home is rebuilt from scratch on every open.** `resetForOpen()` sets `results = []`, and `refreshHomeResults()` then fans out `defaultResults()` to all 18 providers with a 400 ms deadline. That gives an empty or "Loading Home" spinner frame, then a pop-in. Root search should be precomputed and drawn synchronously.
4. **[verified] Panel position depends on the display's scale factor.** `topInset = 280 / backingScaleFactor` puts the panel 140 pt from the top on Retina and 280 pt on 1× displays.
5. **[hypothesis] System alerts and save panels may appear *behind* the launcher.** The panel sits at `.statusBar` (25). `NSAlert.runModal` and `NSSavePanel` sit at modal-panel level (8). `PanelDismissalPolicy` deliberately keeps the panel up while a modal exists. Check: run Rename on a file result with the panel open.
6. **[verified] ⌘Q inside the panel terminates the app** (`FoundryPanel.handleShortcut`). Raycast ignores it. Accidental quits of a background utility are a real support burden.

### B. Keyboard and interaction correctness (P0)

7. **[verified] Home selection walks items you can't see.** The view renders `suggestionResults.prefix(5)` and `commandResults.prefix(5)`, filtered by `isSuggestibleApp` and `isPrimaryWindowLayout`. `moveSelection` walks raw `state.results` (6 apps, then 5 commands, including filtered ones). Arrow keys jump around and the highlight vanishes onto hidden rows. The calculator fallback rows are rendered `isSelected: false` and can't be reached at all.
8. **[verified] Action shortcuts hijack text-editing keys.** `ActionShortcut.conventional` maps `.copyFile` to **⌘C** and `.moveToTrash` to **⌘⌫**. `FoundryPanel.performKeyEquivalent` runs before the field editor. Select query text and press ⌘C: you copy the *file*. Press ⌘⌫ to clear the query: you get a **trash** prompt.
9. **[verified] ⌘V is reimplemented badly.** `pasteFromClipboard()` appends to the end of `query`, ignoring caret position and selection. The Edit menu already has `paste:`, so the override is pure regression.
10. **[verified] Esc with a query closes the panel** instead of clearing the query first (`handleEscape` returns false in search mode). Raycast clears first and closes on the second Esc.
11. **[verified] The footer lies.** The search footer always says **"Open"** (or "Copy Answer") whatever the selected result's real primary action is: Copy, Paste, Run Script, Trash… Feature footers are hand-typed strings such as `keys: "Click"`, and you already had to fix one that drifted from the real keymap.
12. **[verified] Auto-assigned action shortcuts are positional.** `.secondary` (⌘↵) goes to *whatever is second*. Shortcuts move as actions are added, which breaks muscle memory.
13. **[verified] Every result gets "Add to Favorites / Reset Ranking / Configure Command"**, including file results, clipboard rows and fallbacks.
14. **[verified] Selection scrolling centers on every arrow press** (`scrollTo(id, anchor: .center)`). Raycast scrolls only enough to keep the selection visible.
15. **[verified] Return runs through a fire-and-forget `Task`** in `executeSelectedResult()`. It's guarded by `isActionInProgress`, but only after the first `await`, so a double Return can race.

### C. Search quality: "als" shows exactly what's wrong (P0)

16. **[verified in screenshot] Fuzzy matching is too loose and ranking is wrong.** "als" returns Tailscale #1 and Feedback Assistant #2. "Almost Maximize Window" is the obvious word-prefix hit and ranks third. "Random Data" matches through a hidden keyword.
17. **[verified] Section grouping overrides relevance.** `ResultSection.ordered` leads with the top hit's section, then emits *all* of that section before any other. A weak app match always beats a strong command match. Raycast root search is one ranked list.
18. **[verified] The ranker's comparator is not a strict weak ordering.** It mixes `areComparable → usageBoost` with `isBetter`, then falls through to `providerID` alphabetical order. Swift's sort output becomes order-dependent and unstable. Matching also runs twice, once in providers and once in the ranker.
19. **[verified] Results reorder after the first paint.** The immediate phase paints, then the complete phase re-ranks and replaces the list, which shows up as visible row jumps.
20. **[verified] Keystroke coalescing is dead code.** `refreshResults()` calls `searchCoordinator.cancel()`, which sets `searchInFlight = false` *before* `search()` reads it. So the 16 ms coalesce never triggers.
21. **[verified] The scheduler is overbuilt.** Per provider and per keystroke it creates an operation task, a watcher task and a timeout task, plus actor gates and a hand-rolled `FirstResultRace`. With 18 providers over two phases, that's about 100 tasks per keystroke.
22. **[verified] File search spawns `/usr/bin/mdfind` per keystroke** and returns unranked Spotlight order (`prefix(limit)`). Use in-process `NSMetadataQuery`/`MDQuery`, rank by name match and recency, and keep one live query that you update.
23. **[verified] Kind labels leak implementation:** "URL" for a settings pane, "Copy" for Random Data, "Delete" for Move to Trash, "Utility".
24. **[verified] The benchmarks measure the wrong thing.** `search.immediate` p50 of 16.8 ms is engine-only and in-process. Key-to-pixel and hotkey-to-first-frame are unmeasured; `panel.show` was "carried over" from 1.1. Budgets of 41.5 ms and 69.4 ms p95 are 2–4 frames. That isn't a Raycast budget.

### D. Performance and resource use (P0/P1)

25. **[verified, measured] The *open* panel idles at ~7–8% CPU** (top, 12×5 s, panel left open with results); closed-panel idle is ~0.3% (CPU-time delta over 30 s). An open-but-static launcher should still sit near 1%. **[hypothesis, profile first]** still-animated views: `phaseAnimator` pulses, `ProgressView`, the pulsing keycap, and the entrance-settle keep drawing at display rate; the clipboard poll reads pasteboard *data* on change (`log show` repeats `NSPasteboard data requested for public.utf8-plain-text` while the panel is up).
26. **[verified, measured] Memory peaks at 364 MB footprint (276 MB "Malloc Large") during open/typing and settles at ~179 MB.** **[hypothesis]** Clipboard history keeps `.image(Data)` payloads for up to 1,000 items in RAM (`ClipboardHistoryItem.payload`), and `load()` materializes all of them; the markdown parse cache and icon cache add on top.
27. **[verified] Clipboard "SQLite" is a full rewrite.** Every capture runs `save(items)`: N upserts, a rebuilt temp `keep` table, a `DELETE NOT IN`, and an image-directory scan. That's O(history) per copy, with no FTS (search is an in-memory linear `localizedCaseInsensitiveContains`). Text and images are stored unencrypted, while Raycast encrypts its clipboard DB.
28. **[verified] The paste-restore race.** `DirectPasteService.completePendingPaste` restores the old pasteboard in a `defer` *immediately* after posting ⌘V. The target app reads the pasteboard asynchronously, so slow targets can paste the *old* contents. `stage()` also eagerly copies every type of every item, which forces promised data (large images and files) to materialize.
29. **[verified] Icon flash on every result change.** `FileIcon`/`RemoteIcon` start with `@State image = nil` and fill in from an async cache. Rows show the gray SF-symbol placeholder and then pop. The cache needs a synchronous hit path. `RemoteIcon` creates a new ephemeral `URLSession` per request: no reuse and no HTTP cache.
30. **[verified] Icons scale by 1.04 on selection**, which resamples the bitmap and blurs it on every arrow press.
31. **[verified] Settings writes are synchronous on main per change.** `ConfigService.update` runs JSON encode plus an atomic file write under a lock on the main actor. The theme-intensity slider writes on every drag tick.
32. **[verified] The test suite spends 40 s of its 77 s in one test** (`ActionRunnerTests.testExtractTextFromImageRunsVisionOCR`, which also spews `contactsd` XPC errors).
33. **[verified, minor] The release binary logs `[com.apple.dt.xctest] test daemon not ready`.** Something test-related is linked or probed at runtime in release.

### E. UI/UX polish (P1)

34. **[verified] Modal `NSAlert` UIs from a launcher**, 25 `runModal` sites in all. Examples: the color picker (an alert with a hand-framed `NSPopUpButton` and a WCAG text dump), the Wi-Fi QR form, the "QR copied — save PNG?" prompt, Rename, Empty Trash, destructive confirmations ("This action can change or terminate system state", which is generic slop copy), and the Firefox connector. Raycast does all of these as in-panel forms with inline confirmation. This is the biggest "doesn't feel like Raycast" item after the window model.
35. **[verified] Settings lives inside the 750×495 transient launcher**, with an 11-category, 176 pt rail. It vanishes when you click away to fetch an API key. "Import and Quit" and "Reset and Quit" are needed because settings don't apply live. Raycast has a dedicated, resizable Settings window.
36. **[verified] The design system is a facade.** `FoundryTheme` defines 5 fonts and 3 spacings. The code uses **28 distinct font sizes** (7, 8, 9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5…), **49 distinct opacity literals**, and **10+ corner radii**. There are 144 raw `.system(size:)` calls and 25 raw `Color(red:)`. Text at 7–9 pt is below macOS legibility norms.
37. **[verified] Pointing-hand cursors on 66 controls.** This is a web idiom that native Mac apps (Raycast included) don't use. It's also implemented with `NSCursor.set()` in `onHover`, which leaves the hand cursor stuck when a hovered view disappears.
38. **[verified] Row anatomy:** two-line 44 pt rows (subtitles hidden for commands but shown for others), selection drawn with both fill *and* a 1 pt border, and uppercase tracked section headers. Raycast uses a single-line title plus an inline gray subtitle, a quiet fill, and Title-case headers. The section grouping itself should go (see C17).
39. **[verified] Reduce Transparency mode in light appearance** paints `Color.black.opacity(0.42)` over `windowBackgroundColor`, which comes out muddy gray.
40. **[verified] The Quick Look implementation is a custom `QLPreviewView` in a utility panel** instead of the system `QLPreviewPanel`. That loses fullscreen, markup and Open With, and it steals key focus from the launcher.
41. **[verified] Hotkey display strings are inconsistent:** "⌘ Space" and "⌥ Space" have a space, "⇧⌘V" doesn't. Onboarding enables a global ⇧⌘V that collides with paste-plain in Chrome and Slack.
42. **[verified] No localization.** There are 0 `String(localized:)` calls; every string is a literal.
43. **[verified] `FeatureSurface` type-erases header, trailing and content to `AnyView`** on every body evaluation, and five whole-tree `.animation(value:)` modifiers animate unrelated subtrees (a change in shelf count animates the whole panel).

### F. Architecture and engineering quality (P1/P2)

44. **[verified] `CommandPanelState` is a god object.** It's about 1,450 lines across 3 files, with about 70 stored properties, 15 `on*` callback closures, mirrored copies of config fields (`showMenuBarIcon`, `hapticsEnabled`, `themeIntensity`… duplicated from `ConfigService`, giving two sources of truth), and a per-mode `if` chain in `performModeShortcut`/`moveSelection`/`pasteFromClipboard`. It also has a magic `Task { sleep(2s); ensureAgentsSocket() }` in `init`.
45. **[verified] `CommandActionKind` is a god enum with 68 cases, switched over in 17 places.** Adding a feature means editing the enum, `ActionRunner`, `resultKindLabel` (in the *view*), `shouldHidePanelForHotkey`, shortcut tables, and more: textbook shotgun surgery.
46. **[verified] `ActionRunner.swift` is 1,530 lines** containing OKLCH colour math, WCAG contrast, Wi-Fi QR escaping, CoreAudio device switching, keep-awake process management, archive creation, QR save dialogs, and so on. That's feature logic in the executor. `CommandPanelView` (1,415 lines), `CalculatorProvider` (1,045) and `FileConversionView` (1,015) also cross 1,000 lines.
47. **[verified] Stringly-typed identity, with 79 `hasPrefix("…")` sites.** The view decides behaviour from ID prefixes (`"file."`, `"snippet."`, `"calculator."`, `"quicklink."`, `"foundry.file-shelf"`). Calculator history recovers the expression by splitting the *subtitle* on `" · "`. Results need a typed payload (`.file(URL)`, `.snippet(ID)`, `.calculation(expr, value)`).
48. **[verified] Concurrency is papered over, not modelled.** There are 59 `@unchecked Sendable` and 5 `nonisolated(unsafe)` (`CommandRegistry`, providers, scheduler…). `ConfigService.current` is read across threads behind an `NSLock` while the registry is `@unchecked`.
49. **[verified] 200 `try?` sites.** Failures vanish (for example, the QR PNG `try? png.write` reports success even when the write fails).
50. **[verified] Persistence is split across `config.json` and 17 `UserDefaults` keys** with inconsistent naming (`preferredCurrencyQuote`, `colorPicker.recents`, `foundry.mainBrowser`, `conversion.firstSuccessCelebrated`). Backup and Restore silently omits the main browser, currency, download folder and colour recents.
51. **[verified] Config has shotgun surgery.** Adding one setting means touching the struct, the memberwise `init`, the custom decoder, a bespoke `updateX` (17 of them), the mirrored state property, its `init` copy, and a setter.
52. **[verified] Clipboard state code is golfed**, with semicolon-chained one-liners over 400 chars (`captureCurrentPasteboard`, `init`, `moveSelection`). 168 lines exceed 200 chars.
53. **[verified] Test coverage is skewed.** `AIProvider` has 56 tests; the 1,450-line panel state has 22; the shell, focus and activation have none (apart from `PanelHideGate`). The snapshot tests are env-gated, so they never run in CI and catch nothing.
54. **[verified] DEBUG `swift run` calls `SMAppService.mainApp.unregister()`** and then installs and launches over `/Applications`. A dev run silently removes the user's login item.
55. **[verified, product risk] Codex OAuth reuses OpenAI's Codex CLI `client_id`** and calls `chatgpt.com/backend-api` (a private API). It's fragile and a ToS exposure, so make it an explicit, labelled opt-in.
56. **[verified] Window tiling rolls back** the frame if it hasn't settled after 12×25 ms. Apps that animate resizes (Electron and others) get reverted. It also sets size before position, while Rectangle's proven order is size → position → size.

### Scope note

`anvil/` (the website), `foundry-ad/` and `launch-film/` are not covered here. They deserve their own pass.

---

## Part 2 — The plan

Order is chosen so that each phase leaves the app shippable, and so that later refactors land on a measured, test-guarded base.

### Phase 0 — Build the laboratory first (measure, don't guess)

**0.1 Key-to-pixel and hotkey-to-frame instrumentation.**
Files: `Sources/FoundryServices/DiagnosticsService.swift`, `Shell/PanelController.swift`, `UI/CommandPanelView.swift`.
Add `os_signpost` intervals: `hotkey→firstFrame` (end it in a `CATransaction.setCompletionBlock` after the first commit with non-empty rows), and `keystroke→resultsCommitted` (start in the `query` `didSet`, end in the next layout pass after `results` changes). Extend `scripts/drive-signposts.swift` to report p50/p95/max.
New budgets in `docs/benchmarks/`: hotkey→first frame with content p95 ≤ 50 ms; keystroke→pixels p95 ≤ 16 ms for the immediate tier.
Accept: a benchmark JSON with both metrics, recorded on a host with Accessibility granted.

**0.2 Idle profile.**
Run `xctrace record --template 'Time Profiler' --attach Foundry --time-limit 60s` with the panel closed, plus `--template 'Allocations'` after a clipboard history load. Record the top 5 idle stacks.
Accept: a report under `docs/benchmarks/2026-10-xx-idle.md` naming the source of the 7–8% CPU and the 276 MB Malloc Large, which confirms or refutes hypotheses D25a–c and D26.

**0.3 Shell behaviour tests.**
New `Tests/FoundryTests/PanelShellTests.swift`: inject a fake activation port (protocol `AppActivation { func activate(); func deactivate(returningTo: pid_t?) }`). Assert that `hide()` orders out and returns activation to the captured app, and that `show()` doesn't call `NSApp.activate`.
Accept: the tests fail on current code.

### Phase 1 — P0 feel: window model and keyboard

**1.1 A non-activating panel that actually dismisses.** (A1, A2, A6)
- `ShellController.showPanel`: remove `NSApp.activate(ignoringOtherApps:)`. Use `panel.orderFrontRegardless()` plus `makeKey()`. A `.nonactivatingPanel` with `canBecomeKey == true` receives keys without activating the app, and the frontmost app keeps its menu bar.
- `PanelController.hide`: after the fade, call `panel.orderOut(nil)`. If `NSApp.isActive` (because a modal or settings path activated us), call `NSApp.hide(nil)` *only when no other Foundry window is visible*, otherwise reactivate the captured target pid. Delete `isSuspended`, `inputEnabled`, and the `ignoresMouseEvents` juggling.
- Where activation is genuinely needed (Settings window, onboarding, system panels), activate explicitly at that call site.
- Delete the SwiftUI `presented`/`replayPresentation` entrance. Keep *one* entrance: alpha 0→1 over 120 ms plus a 4 pt translate, both in AppKit, with no scale. Remove the `DispatchQueue.main.async` re-key hack.
- Remove ⌘Q from `FoundryPanel.handleShortcut`. Quit stays in the ⌘ menu and the status item.
- Accept: the Phase 0.3 tests pass. Manually: hotkey → type "saf" → Esc → keep typing, and the characters land in the previous app. Signpost hotkey→first frame p95 ≤ 50 ms.

**1.2 A synchronous home.** (A3)
`CommandRegistry`: keep a `homeSnapshot` that refreshes in the background on app-index change, usage change, running-apps change (NSWorkspace notifications), and after each execution. `resetForOpen()` assigns it synchronously, and never sets `results = []`.
Delete the "Loading Home" empty state.
Accept: in a test, `resetForOpen()` leaves non-empty `results` with no await. No spinner appears on open.

**1.3 Scale-independent placement.** (A4)
Position the panel at `visibleFrame.maxY - visibleFrame.height * 0.22 - height` (Raycast-like), in points.
Accept: a unit test of `frame(for:)` on 1× and 2× fake screens gives equal point offsets.

**1.4 Modal layering.** (A5) Confirm with the check in A5 first. If confirmed, replace these flows outright in Phase 3. In the interim, lower the panel to `.floating` (or order it out) while a modal or `NSSavePanel` runs.

**1.5 What you see is what you navigate.** (B7)
Introduce `struct PanelList { sections: [Section]; flat: [CommandResult] }`, computed once in state (not in the view) whenever results change. The view renders `sections`, and `moveSelection` walks `flat`. Home prefixes and filters live in this builder. Calculator fallbacks become real list items.
Accept: a test where every ID reachable by arrowing is rendered, and vice versa.

**1.6 Text editing wins over action shortcuts.** (B8, B9)
- In `FoundryPanel.performKeyEquivalent`: if the first responder is a field editor and the chord is in `{⌘A, ⌘C, ⌘X, ⌘V, ⌘Z, ⇧⌘Z, ⌘⌫, ⌥⌫, ⌘←, ⌘→}`, return `super`. As a fallback, the action fires only when the field has no selection.
- Remap: Move to Trash → ⌃X (Raycast convention), Copy File → ⌘⇧. (period).
- Delete `pasteFromClipboard()` and `onCommandV`. The Edit menu handles paste.
- Accept: tests on `ActionShortcut` showing no conventional shortcut collides with the text-editing set. A UI test that ⌘C with a selected query copies the query.

**1.7 Escape, footer, focus semantics.** (B10, B11, B13, B14, B15)
- Esc: actions panel open → close it. Then a non-empty query → clear it. Then a non-root mode → go home. Then close.
- The footer derives from the *selected result's preferred action*: `FooterActionSpec(label: preferredAction.title, keys: "↵")` + `"Actions ⌘K"`. Feature surfaces publish `primaryAction` and `actions` from their state, never typed-in strings. Delete `keys: "Click"`.
- Meta actions (Favorite, Reset Ranking, Configure) are appended only to results with `isCommand == true` (a new field; see 4.2).
- Scrolling: replace `scrollTo(anchor: .center)` with minimal scrolling (track visible ID bounds via `onScrollGeometryChange`, and scroll only when the selection leaves the viewport).
- Return: set `isActionInProgress = true` synchronously before spawning the task.
- Accept: `CommandPanelStateTests` cases for each Esc step, a footer label that equals the selected action title, and double-Return firing exactly once.

**Phase 1 gate:** `swift test` is green, the Phase 0 benchmarks are re-run and recorded, and the manual focus check passes.

### Phase 2 — P0 search quality and pipeline

**2.1 One scalar score, one ranked list.** (C16–C18)
- Replace the `CommandRanker.ordered` comparator with `score = matchScore × (1 + frecencyWeight × frecency) + favoriteBoost`.
- `matchScore` tiers: exact title 1.0; title prefix 0.9; word-boundary prefix ("als" → **Al**most…) 0.85; acronym ("amw") 0.8; substring 0.6; alias exact 0.95; keyword prefix 0.5; fuzzy subsequence ≤ 0.35, and only when every char lands at a word boundary or is contiguous in runs ≥ 2 (this kills "T**a**i**ls**cale" for "als").
- Frecency: an exponential half-life (7 days) over `UsageRankingStore` executions, per query prefix.
- Tie-break by title, then ID only. Drop `providerID` ordering.
- Delete `ResultSection.ordered` from root search. Keep `ResultSection` only as a *label*, if at all.
- Accept: a golden test table (`Tests/FoundryTests/RankingGoldenTests.swift`) of ~30 query→top-3 expectations, including "als" → Almost Maximize Window first, "saf" → Safari, "term" → Terminal, "sys" → System Settings, "cl" → Clipboard History (after usage). Plus a property test that the comparator is a strict weak ordering (antisymmetry and transitivity over random triples).

**2.2 Stable list across phases.** (C19)
The complete phase may *append* deferred results below the immediate ones. It may reorder immediate results only if the user hasn't moved the selection, and only within the first 100 ms.
Accept: a test that the top-k immediate IDs keep their order when the deferred phase adds lower-scored results.

**2.3 Simplify the scheduler.** (C20, C21)
Replace `CommandProviderScheduler`'s gates and races with one `withTaskGroup` per search: each provider runs `try await withDeadline(provider.timeout) { provider.search(req) }`. Structured cancellation comes from the parent task being cancelled on the next keystroke. Delete `ProviderExecutionGate`, `FirstResultRace`, and the coalesce flag (structured cancellation makes it moot). Keep per-provider timing for diagnostics.
Accept: the existing `CommandSearchCoordinatorTests` and `CommandRankingTests` pass (adapt the busy-gate tests to "a cancelled provider never delivers"). The file shrinks by more than 150 lines.

**2.4 In-process file search.** (C22)
Replace `mdfind` with one long-lived `NSMetadataQuery` (scope: home), and update its predicate on each keystroke. Rank results by name match (reusing the 2.1 scorer) and `kMDItemLastUsedDate`.
Accept: `FileSearchTests` with an injected query backend. The p95 for file-mode results drops (record it with the 0.1 harness).

**2.5 Honest kind labels.** (C23)
Providers supply `kindLabel` (for example "Application", "Command", "System Settings", "Quicklink", "Snippet", "File"). Delete `resultKindLabel` from the view.

**Phase 2 gate:** golden tests pass, and keystroke→pixels p95 ≤ 16 ms (immediate tier).

### Phase 3 — P0/P1 performance and data correctness

**3.1 Fix the open-panel burn** according to the 0.2 findings. Expected moves: (a) `phaseAnimator`/spinner loops get `.paused`-style gating — animate only while visible or for a bounded duration. (b) The clipboard poll compares `changeCount` *only* and reads data only on change; set `timer.tolerance` to at least 0.3 s. (c) Gate agent polling on actual subscribers.
Accept: open-panel idle CPU < 1.5% averaged over 60 s (panel open, results loaded, nothing animating); closed < 0.5%.

**3.2 Clipboard store redesign.** (D26, D27)
- An incremental API: `insert(item)`, `delete(id)`, `setPinned(id)`, `trim(policy)`.
- An FTS5 table for text, with `items` holding metadata only.
- Images live on disk with a thumbnail column (≤ 256 px PNG). The in-memory `ClipboardHistoryItem` holds `ImageRef(signature)`, not `Data`, and full data loads lazily for paste and preview.
- Encrypt at rest with a Keychain-held key (SQLCipher isn't available, so do AES-GCM per text blob via CryptoKit; the FTS index stays local). If FTS-over-ciphertext is too much, document it and encrypt images only, as an explicit decision.
- Accept: a migration test from the current schema. A workload test that inserting into a 1,000-item history touches O(1) rows. A memory check: the footprint after loading 1,000 items with 200 images stays under 60 MB.

**3.3 Paste correctness.** (D28)
Restore the pasteboard only after the target has consumed it: wait 250–400 ms after posting, or until `changeCount` changes away from ours. Use `NSPasteboardItem` data providers to lazily re-provide the previous items instead of eagerly copying every type.
Accept: `DirectPasteServiceTests` with a fake slow target that reads after 200 ms gets the staged content. A test that a promised-data type isn't materialized during `stage()`.

**3.4 Icons without flashes.** (D29, D30)
Add `CommandIconRepository.cachedImage(for:) -> NSImage?` (synchronous). `FileIcon` initializes `@State` from it. Prewarm the icons for the home snapshot and the top 12 results off-main. Use one shared `URLSession` with `URLCache` for remote icons. Remove the `scaleEffect(1.04)` on selection.
Accept: a snapshot or perf test where re-rendering the same result list makes no placeholder render.

**3.5 Async config writes.** (D31)
`ConfigService` mutates in memory synchronously and persists via a debounced (300 ms) background writer, flushed on terminate.
Accept: a test where 100 rapid updates produce at most 2 writes.

**3.6 Test-suite speed.** (D32)
Run Vision OCR in its test against a tiny 64×32 image (or a stubbed recognizer, with one real test behind `FOUNDRY_SLOW_TESTS`). Shrink the 11.8 s clipboard workload test.
Accept: suite under 30 s.

**3.7** Find and remove the release-build XCTest probe (D33). Accept: `log show` from a release launch has no `com.apple.dt.xctest` lines.

### Phase 4 — P1 architecture: make features cheap to add

**4.1 Typed result payloads.** (F47)
Add `enum ResultPayload { case app(path), file(URL), snippet(id), calculation(expr: String, value: String), quicklink(id), clipboard(id), command(id), url(URL), systemPane(id) }` on `CommandResult`. Migrate every `hasPrefix("file.")`-style check to payload switches. Delete the subtitle parsing for calculator history.
Accept: grep for `hasPrefix("file.` / `"snippet.` / `"calculator.` / `"quicklink.` in `Sources/Foundry/UI` and `Commands` returns 0.

**4.2 Commands own their behaviour.** (F45, F46)
Introduce `protocol ResultAction { id; title; icon; shortcut: ActionShortcut?; style (.normal/.destructive); dismissal (.close/.stay/.hud); func perform(_ ctx: ActionContext) async -> CommandOutcome }`. Each feature module ships its actions next to its provider (`Features/Color/PickColorAction.swift`, `Features/QR/…`, `Features/Files/FileActions.swift`, `Features/System/AudioDeviceAction.swift`, …). `ActionRunner` becomes a ~200-line executor: confirmation policy, cancellation, feedback, and usage recording. `CommandActionKind` is deleted after migrating callers one feature at a time; keep the enum alive until the last caller moves, then remove it in one commit.
Accept: `ActionRunner.swift` < 300 lines. No `switch` over action kinds outside the executor's generic handling. Adding a new command touches only its own feature folder and the provider list.

**4.3 Split `CommandPanelState`.** (F44)
- `PanelSession` (query, list, selection, actions overlay): the root search only.
- `PanelRouter` (mode stack; push/pop semantics like Raycast navigation).
- Each feature state conforms to `PanelFeature { var primaryAction; var actions; func handleKey(_:) -> Bool; func handleMove(_:) }`, which replaces the per-mode `if` chains in `performModeShortcut`, `moveSelection` and `pasteFromClipboard`.
- Settings fields are read straight from an `@Observable SettingsStore` wrapping `ConfigService`, with no mirrored copies.
- Replace the 15 `on*` closures with a small `ShellPort` protocol that `ShellController` implements.
- Delete the `sleep(2s)` socket start: start agents when the agent shelf or a widget first observes them.
- Accept: no file over 500 lines in `UI/` except views being split in 5.x. `CommandPanelState` is gone or under 300 lines. Existing tests pass, retargeted.

**4.4 One persistence model.** (F50, F51)
Move every `UserDefaults` key into `FoundryConfig` (or into a `FoundryLocalState` file for non-portable state such as `launchAtLoginConsent` and celebration flags), with an explicit migration in `ConfigService`. Replace the 17 `updateX` methods with one `func update(_ mutate: (inout FoundryConfig) -> Void)`. The decoder uses a `@DefaultValue` property wrapper (or `decodeIfPresent` via a generic helper), so adding a field is a one-line change.
Backup and Restore apply live, with no quitting.
Accept: grep for `UserDefaults.standard` in `Sources` returns 1 (the migration only). A backup round-trip test includes the main browser, currency, download folder and colour recents.

**4.5 Concurrency honesty.** (F48)
Make the registry and providers `Sendable` for real: immutable providers with `let` dependencies, actor-isolated caches (`InstalledAppCache` becomes an actor), and `ConfigService` publishes immutable `FoundryConfig` snapshots via `AsyncStream` or an `OSAllocatedUnfairLock<FoundryConfig>`. Target: `@unchecked Sendable` ≤ 10, each with a one-line justification comment.
Accept: grep count, and a clean Swift 6 strict-concurrency build.

**4.6 Failure visibility.** (F49)
Audit the 200 `try?` sites. Keep them only for genuinely ignorable best-effort cleanup (`removeItem` of temp files). Everything user-visible either surfaces via `ActionFeedback.failure` or logs via `diagnostics`.
Accept: `try?` ≤ 60, and the QR save reports failure.

**4.7 Readability.** (F52)
Reformat the golfed clipboard files (one statement per line).
Accept: no Swift line over 160 chars in `Sources/` (enforce with a `swift-format` lint rule in `scripts/`).

**4.8 Dev-run safety.** (F54)
Remove `SMAppService.mainApp.unregister()` from DEBUG `main.swift`. Never install over `/Applications` from `swift run` unless `INSTALL_APP=1` is set explicitly.

### Phase 5 — P1 UI/UX polish to Raycast grade

**5.1 Real design tokens.** (E36, E37)
`FoundryTheme`:
- A type ramp with exactly 6 styles: `title` 20/regular, `body` 13/medium, `bodySecondary` 13/regular, `caption` 11/medium, `micro` 11/semibold-uppercase-off, `mono` 12. The minimum size is 11.
- Spacing 4/8/12/16/24. Radii 6 (badge), 8 (control), 10 (row), 14 (overlay), 26 (panel).
- Semantic colours (`textPrimary/Secondary/Tertiary`, `fillSelected`, `fillHover`, `separator`, `destructive`, `success`, `warning`) mapped to dynamic system colours with tuned opacities.
- Migrate every literal, and add `scripts/lint-design.sh` that fails on `.system(size:` / `Color(red:` / `opacity(0.` literals outside `FoundryTheme.swift`.
- Delete `pointerCursor()` and every `NSCursor.*.set()`.
- Accept: the lint passes, and distinct font sizes ≤ 6.

**5.2 Raycast row anatomy.** (E38)
- Single-line 40 pt rows: icon 20–24 pt, title, gray inline subtitle, then right-aligned accessories (alias badge, hotkey keycaps, kind label).
- Selection is a fill only (no border), with a 10 pt radius. Section headers (where still used, such as clipboard or snippet lists) are Title case, 11 pt semibold, tertiary colour.
- Accept: reviewed side by side against a Raycast screenshot at the same scale (add both to `docs/qa/2026-10-xx-rows/`).

**5.3 Kill the alerts: in-panel forms and confirmations.** (E34)
Build a reusable `PanelForm` surface (fields, dropdowns, submit with ↵ and cancel with Esc, all in the panel) and an inline `ConfirmBar` (a destructive action shows "Press ↵ again to Move to Trash" in the footer for 3 s, as Raycast does).
Migrate: Color Picker (result view with swatch, format list, recents, contrast chips; ↵ copies the selected format), Wi-Fi QR (form, then an in-panel QR preview with Copy and Save actions), Generate QR (an in-panel preview instead of the save prompt), Rename (inline form), Empty Trash, Quit All Apps, Kill Process, Move to Trash (ConfirmBar), the script-directory trust prompt (form), the Firefox connector (form), and the download notice (onboarding step).
Accept: grep for `runModal` in `Sources` matches only `NSOpenPanel`/`NSSavePanel` (file pickers), and those run as sheets on the Settings window, or with the panel ordered out.

**5.4 Dedicated Settings window.** (E35)
A standard resizable `NSWindow` (≈ 820×600, min 680×480) hosting `SettingsView` with a sidebar, opened by ⌘, from the panel, the status item or the ⌘ menu. The launcher stays a launcher. Settings apply live; delete "Import and Quit" and "Reset and Quit".
Accept: Settings survives switching apps. A test that restore applies without termination.

**5.5 Native Quick Look.** (E40)
Replace `QuickLookPanelController` with `QLPreviewPanel.shared()`, driven by a data source and delegate on the panel's responder chain. Space and ⌘Y toggle it, and arrow keys keep driving the launcher selection.

**5.6 Material and appearance fixes.** (E39)
Reduce Transparency uses `windowBackgroundColor` plus the semantic separator, with no black wash in light mode. Verify dark, light and Increase Contrast on macOS 26/27 with Liquid Glass.

**5.7 Motion audit.**
- The 1.1 entrance is the only panel animation.
- Remove the whole-tree `.animation(value:)` stack, and scope animations to the subtree that changes (actions overlay, toast).
- Replace `FeatureSurface`'s `AnyView`s with a `@ViewBuilder` switch on mode, plus `PanelFeature` protocol witnesses (from 4.3).
- Mode push/pop uses a 120 ms cross-fade with no movement. Everything respects Reduce Motion.

**5.8 Copy and consistency pass.** (E41, B13 copy)
- One hotkey formatter (`⌥Space`, `⇧⌘V`, with no spaces).
- Remove the default ⇧⌘V suggestion, or detect conflicts first.
- Rewrite confirmation copy to name the object ("Move "Report.pdf" to Trash?").
- Run the `clean-copy` skill over every user-facing string.

**5.9 Localization groundwork.** (E42)
Wrap strings in `String(localized:)` with a `Localizable.xcstrings` catalog via SwiftPM resources. English only for now, but no new literals (lint).

### Phase 6 — P2 platform and risk

- **6.1 Window tiling** (F56): set size → position → size, and accept the frame the app settles at, with no rollback. Rollback only when an AX set call returns an error.
- **6.2 Codex OAuth** (F55): put it behind an explicit "Use ChatGPT sign-in (unofficial)" toggle, with copy explaining that it relies on a private endpoint. Default off.
- **6.3 CI value**: run the snapshot tests in CI with a checked-in reference directory (light mode, which is the one that renders offscreen) and pixel-diff tolerance, so UI regressions fail builds.
- **6.4 App index** (C, AppSearch): supplement directory enumeration with an `NSMetadataQuery` for `kMDItemContentType == 'com.apple.application-bundle'`, to catch apps on other volumes and in nested folders, with live updates instead of 30 s rescans.

---

## Part 3 — Definition of done (the bar)

| Metric | Today | Target |
| --- | --- | --- |
| Hotkey → first frame with content (p95) | unmeasured; blank frame by construction | ≤ 50 ms, never blank |
| Keystroke → pixels, immediate tier (p95) | unmeasured (engine-only 35.6 ms) | ≤ 16 ms |
| Idle CPU, panel open / closed | ~7–8% / ~0.3% | < 1.5% / < 0.5% |
| Footprint after 1k-item clipboard | 179–364 MB | < 120 MB |
| Focus returns to previous app on Esc | no (by code) | yes, tested |
| Ranking golden set | none | 30/30 |
| `runModal` (non-file-picker) | 15+ | 0 |
| Distinct font sizes / opacity literals | 28 / 49 | ≤ 6 / tokens only |
| `@unchecked Sendable` / `try?` | 59 / 200 | ≤ 10 / ≤ 60 |
| Files > 1,000 lines | 5 | 0 |
| Test suite wall time | 77 s | < 30 s |

Run `verification-before-completion` before claiming any phase done. The numbers in this table are the evidence; prose isn't.
