# Foundry product polish and completion plan

Status: superseded by `docs/plans/2026-09-25-foundry-premium-plan.md` (P5 polish sweep carries the open packages). Previously in progress. Executed packages are recorded in `docs/qa/` per dated coverage doc and `.audit/product-polish.tsv`; live-UI gaps remain marked unverified there.

## Outcome

Make the existing product dependable enough for daily use: every advertised action does what its label promises, every workflow has a usable failure and recovery path, and every screen is readable and consistent in light and dark appearance. Downloads is the first complete feature pass after shared appearance and navigation.

This plan covers the features that exist today. The August 23 roadmap remains the separate source for new capabilities such as file search, Quicklinks, and Script Commands. Completing the current product does not automatically authorize building every item on that roadmap.

The implementation stays in SwiftUI, AppKit, Foundation, and the existing feature boundaries. Reuse `CommandPanelState`, `ActionRunner`, feature state objects, and native controls. Add no design library, generic workflow framework, or new persistence architecture without a demonstrated need.

## Current state and evidence

The audit so far includes source inspection of the shell, shared controls and materials, downloads, clipboard, snippets, developer tools, translation, and portions of AI, file conversion, File Shelf, camera, and emoji. Home, search, and the modified Downloads empty state were inspected through computer use and screenshots. Other screens have not passed a visual or end-to-end review.

A release build succeeded. The first implementation draft passed 439 tests with zero failures. The subsequent reopen change compiled and was exercised through computer use, but the full test suite was not rerun after that change. These results establish a baseline; they do not establish feature completeness or excellent visual quality.

### Existing uncommitted work

Before the request changed to planning, I modified these files:

| File | Draft change | Outstanding proof |
| --- | --- | --- |
| `Sources/Foundry/Features/Media/MediaDownloadService.swift` | Resolve the chosen destination per download; publish actual saved URLs. | Folder change, file reveal, playlist output, cancellation, and progress ordering regression tests. |
| `Sources/Foundry/Features/Media/MediaDownloadModels.swift` | Add saved output URLs to progress. | Verify final output survives late progress updates and completion. |
| `Sources/Foundry/UI/MediaDownloadsView.swift` | Simplify capability copy; enlarge details; expose Finder action; rename history clearing. | Populated, failed, cancelled, missing-file, keyboard, and both appearance states. |
| `Sources/Foundry/Application/AppDelegate.swift` | Show the panel when the app reopens. | Cold launch, existing instance, hotkey, and login launch behavior. |
| `Sources/Foundry/Shell/ShellController.swift` | Expose the existing panel-show method to the app delegate. | Same launch checks. |

Treat these as a draft to review in the first execution task, not as an accepted design or finished feature. No further source changes belong to this planning pass. The local staged app contains the draft; the installed `/Applications` copy was not replaced during this work.

The README changes, August planning documents, and benchmark report predate this work. Preserve them. Do not reset the worktree or include unrelated files in commits.

## Confirmed audit findings

Evidence labels distinguish what was seen from what was inferred. “Source-confirmed” means the implementation establishes the issue, but its exact runtime presentation still needs reproduction.

| ID | Priority | Evidence and issue | Explicit change | Completion evidence |
| --- | --- | --- | --- | --- |
| P01 | Deferred | User direction: preserve the current glass appearance. The initial contrast concern is removed from this execution. | No change. Revisit only with a future visual brief. | Not applicable. |
| P02 | Deferred | User direction: preserve the current glass appearance. The native-glass contrast slider is out of scope for this execution. | No change. Revisit only with a future visual brief. | Not applicable. |
| P03 | High | Source-confirmed in the pre-draft service: the folder is captured in `Dependencies` at launch while the UI reads the current preference. | Snapshot the current destination when each download starts; retain that destination for the entire operation. | Change folder without relaunching, then verify a new file lands there; an already-running operation keeps its original destination. |
| P04 | High | Source-confirmed in the pre-draft Downloads: completed rows have no saved-file action or structured output paths. | Preserve saved URLs, reveal actual files, offer Open for a single existing file, and explain moved/deleted files without claiming success. | Real single-file and playlist downloads; verify Finder selection and correct output names. |
| P05 | Medium | Source-confirmed in pre-draft Downloads: backend labels occupy three rows; errors are 9.5-point monospaced, single-line, truncated. “Clear Completed” also removes failures and cancellations. | Prioritize filename, progress, status, and action. Put service details behind disclosure. Provide expandable/selectable errors. Label clearing according to its actual scope. | Active, failure, retry, cancelled, long-title, and mixed-history screenshots; saved files survive list removal. |
| P06 | High | Source-confirmed: `ClipboardHistoryView` passes `copy: { state.copySelected() }` to every card, while sibling actions first select that card. | Make each card action target its own item explicitly; use the same rule for double-click. | Select item A, click Copy on B, verify B is on the pasteboard. Repeat after filtering and reordering. |
| P07 | Medium | Source-confirmed: clipboard Pause/Resume is inside the populated-results branch. It disappears when empty or filtered to no matches. | Keep capture status and Pause/Resume in a persistent toolbar. Differentiate empty history, paused capture, and no search matches. | Pause an empty history, resume it, and recover from no matches without leaving the feature. |
| P08 | High | Source-confirmed: the snippet “Insert snippet” button calls `copySelected`, which only writes the pasteboard. | Wire Insert through the existing direct-paste flow and dismiss after staging succeeds. Keep Copy as a separate action. | Insert into a disposable text document; verify content, target, caret behavior, and denied-access feedback. |
| P09 | Medium | Source-confirmed: snippets show “No snippets yet” whenever filtered results are empty, including a nonempty library. | Separate first-use and no-match states; provide Clear search for the latter. | Search an unmatched term in a populated library, then clear it and recover the same selection where possible. |
| P10 | High | Source-confirmed: `DeveloperToolsState.refreshBase64` trims input before encoding. Encoding therefore changes the source bytes. | Encode the original string; normalize only where decoding rules permit it. | Exact known-value test for leading/trailing spaces and a newline, plus UI round-trip and copy verification. |
| P11 | Medium | Source-confirmed: invalid timestamp input yields an empty result array without an error in the tool state. | Show a format-specific inline error for invalid nonempty input. Make seconds/milliseconds interpretation explicit. | Empty input is quiet; invalid input explains a valid example; valid input shows correct units and timezone. |
| P12 | Medium | Source-confirmed in the pre-draft app: no reopen handler shows the launcher. A running background instance could be activated without showing its panel. Draft reopen behavior was exercised successfully. | Retain the existing show-panel path for app reopen. Verify login startup separately so ordinary login does not steal focus. | Cold launch, reopen from Finder, already-running instance, global shortcut, and login startup checks. |
| P13 | Medium | Screenshot: the feature title/back-control cluster is centered while search has a leading input. Source: fixed-title header branches do not occupy the available width. | Give Back a fixed leading position and align feature titles to a shared edge; reserve trailing space for feature actions. | Compare Home, Downloads, conversion, translation, and Settings headers at the actual panel size. |
| P14 | High | Live audit: Clipboard History rendered long, unredacted workspace content in its card grid. Source: capture filtering only checks pasteboard types and bundle IDs; `ClipboardInlinePreview` renders up to five full lines. | Add conservative sensitive-content detection before persistence, redact long previews by default, and let the user opt in to full preview only for the selected item. | Verify that tokens, credentials, and prompt-injection-like text are excluded; ordinary text remains capturable and can be copied without unnecessary disclosure. |

## Direction for the polish

Recommended: refine Foundry as a compact native utility. Keep system typography, SF Symbols, the launcher silhouette, and the blue interaction accent. Use material for the shell, quiet surfaces for content, and clear selection for keyboard navigation. Files and text should be the dominant content.

Two alternatives were considered. A separate large workspace window would help dense editors but introduce another navigation model before the existing one is proven. A cosmetic refresh alone would be smaller but would leave mislabeled and incorrect actions intact. The chosen direction addresses the current product in place; resize a feature only when the audit proves content cannot fit or scroll usefully.

Apply these concrete rules:

- Shared leading header, stable back control, feature title, and trailing actions. Escape returns one level and preserves context where useful.
- Use the existing spacing scale: 4, 8, 12, 16, 20, 24, and 32 points. Remove nested cards when spacing alone communicates grouping.
- Start with 13-point row titles and 12-point supporting content. Smaller labels must remain readable at normal desktop scale; do not squeeze operational information into 9-point text.
- Keep one visually dominant action per surface. Use native buttons, menus, selection, progress, and focus behavior where possible.
- Keep filenames and essential errors recoverable in full. A tooltip can supplement a label; it cannot be the only recovery instruction.
- Keep status text alongside status color. Show hover, keyboard focus, pressed, disabled, loading, success, and error where each state applies.
- Light and dark mode are both required. A global white-to-black replacement is not acceptable: image treatments, accent buttons, foregrounds, and overlays have different roles.
- Honor Reduce Motion and Reduce Transparency. Do not add animation to frequent search or keyboard selection changes just for decoration.

## Execution order

Execute one package at a time. Each package ends with evidence and a reviewable diff before the next starts. An executor must load `prose`, `ponytail`, and `code-deslop`; use `design-engineering` for UI work and `architect` for changed ownership or contracts. Use `executing-plans` during execution. This document itself does not start implementation.

### Package 0: Reconcile the draft and complete the inventory

**Files:** the five changed source files above; this plan; create `docs/qa/2026-09-05-product-polish/coverage.md` during execution.

1. Record `git status --short` and review the five source diffs. Classify each draft change as retain, revise, or remove; do not touch unrelated work.
2. Record macOS version, display scale, app build, appearance, and accessibility settings for the audit machine.
3. List every command route and feature exposed by `CommandRegistry.swift`, `BuiltInCommandProvider.swift`, and `CommandPanelState.Mode`.
4. Open each surface through the packaged app. Record how it is reached, its main action, and available recovery paths.
5. Capture initial screenshots of each surface, including representative populated states using disposable data.
6. Add discovered issues with severity, reproduction steps, file ownership, and expected behavior. Keep untested integrations marked unverified.

**Exit:** every advertised existing feature has a coverage row. The five draft files have an explicit disposition. Do not describe the product as fully audited until this inventory is complete.

### Package 1: Shared navigation and launcher behavior

**Modify:** `Sources/Foundry/UI/CommandPanelView.swift`; `Sources/Foundry/Shell/PanelController.swift` only if a measured layout problem requires it. Retain/revise the reopen changes in `Application/AppDelegate.swift` and `Shell/ShellController.swift`.

**Tests:** `Tests/FoundryTests/CommandPanelStateTests.swift`, `ResourcePackagingTests.swift`; use the existing material-policy test location found during inventory.

1. Reproduce P12 and P13 in the staged app and save the baseline evidence.
2. Align shared headers and back controls. Make icon actions expose accessible names, visible focus, and usable hit areas.
3. Verify Enter, Escape, Tab, arrow keys, Command-K, and Command-comma without intercepting normal text editing in feature inputs.
4. Test repeated open/close, focus return, modal sheets, and reopening an existing process.
5. Run focused tests, then capture matching screenshots.

**Exit:** no invisible focus on key actions, no clipped shared chrome, and the existing glass presentation remains unchanged. Normal text and essential controls must remain readable in the product’s supported appearance.

### Package 2: Finish Downloads

**Modify:** `Sources/Foundry/UI/MediaDownloadsView.swift`, `UI/CommandPanelState.swift`, `Features/Media/MediaDownloadModels.swift`, `MediaDownloadService.swift`, `MediaDownloadProvider.swift`, and `Commands/Execution/ActionRunner.swift` only for required action/cancellation wiring.

**Tests:** `Tests/FoundryTests/MediaDownloadTests.swift`, `MediaNetworkPolicyTests.swift`, `ActionRunnerTests.swift`.

1. Add regression tests for the selected destination and actual output URLs before revising the draft service.
2. Prove completion cannot lose output URLs when queued progress callbacks arrive. Keep one owner for final state; do not infer a filename from a human-readable success message.
3. Preserve the operation's starting destination. Add a Change folder action using the existing folder chooser flow.
4. Arrange the view as a link composer, destination row, active list, and recent history. Remove duplicated folder actions and backend copy from the main reading path.
5. Make active rows show title, progress or a clear indeterminate phase, byte counts when known, and Cancel. Show speed/ETA only when valid.
6. Make completed rows offer Open for one file and Show in Finder for all saved outputs. Handle moved/deleted files explicitly.
7. Make errors readable, selectable, and expandable. Retry starts a new operation without making the original failure vanish unexpectedly or duplicating an active request.
8. Define batch input behavior: deduplicate links, report rejected entries, and preserve rejected input rather than silently clearing mixed valid/invalid text.
9. Keep clearing/removing history separate from filesystem deletion. Confirm active downloads survive clearing history and closing the panel.
10. Test direct media, a permitted YouTube clip, a playlist, unsupported input, HTTP failure, network interruption, cancellation, retry, changed folder, duplicate filenames, and missing output files. Test social-service capability with a public test URL; describe a real service failure honestly.

**Exit:** input → progress → saved file → Open/Reveal works end to end. Every failure has a visible recovery action. Screenshot empty, active, completed, failed, cancelled, mixed-history, long-title, and missing-file states in both appearances. Never expose private URLs or titles in shared evidence.

### Package 3: Clipboard and snippets

**Modify:** `Sources/Foundry/UI/ClipboardHistoryView.swift`, `ClipboardHistoryState.swift`, `SnippetsView.swift`, `SnippetState.swift`, `CommandPanelView.swift`, `CommandPanelState.swift`; reuse `Sources/Foundry/Shell/DirectPasteService.swift`.

**Tests:** `Tests/FoundryTests/ClipboardHistoryTests.swift`, `DirectPasteServiceTests.swift`, `SnippetRendererTests.swift`, `SnippetExpansionServiceTests.swift`, `LibraryPersistenceTests.swift`.

1. Reproduce Copy B while A is selected. Fix card-target ownership and verify every sibling action uses the same intended item.
2. Add a regression matrix for concealed types, password-manager bundles, token-like values, and long workspace text. Exclude detected sensitive content from history without exposing it in the UI or diagnostic output. Preserve ordinary copied text.
3. Redact text previews by default. Reveal full text only after explicit selection in the local UI; copy must continue to preserve the exact stored value.
4. Keep clipboard capture status and Pause/Resume visible in empty, populated, and filtered states.
5. Audit text, image, and file previews. Make long content inspectable and make pointer/keyboard selection agree.
6. Wire snippet insertion through the existing staged direct-paste flow, including placeholder/caret behavior supported by `SnippetRenderer`.
7. Separate no snippets from no search matches. Clarify duplicate-keyword errors and prevent silent loss of unsaved edits when switching snippets or leaving the screen.
8. Test create, edit, save, search, pin, copy, insert, import, delete cancellation, and persistence after restart with a disposable library or explicitly scoped test entries.

**Exit:** card actions act on the visible target; Insert inserts; Copy copies; data survives restart; failure preserves editable content. Do not change retention limits or storage formats merely as a polish task.

### Package 4: Developer tools, calculator, and translation

**Modify:** `Sources/Foundry/UI/DeveloperToolsState.swift`, `DeveloperToolsView.swift`, `TranslatorState.swift`, `TranslatorView.swift`, `CalculatorViews.swift`; affected engines under `Features/DeveloperTools`, `Features/Calculator`, and `Features/Translation` only for reproduced correctness issues.

**Tests:** `Tests/FoundryTests/DeveloperToolsProviderTests.swift`, `TranslationTests.swift`, and the existing calculator tests located during inventory.

1. Add this state-boundary regression inside `DeveloperToolsProviderTests`:

```swift
@MainActor
func testBase64ToolPreservesWhitespaceWhenEncoding() {
    let state = DeveloperToolsState()
    state.base64Input = " a\n"
    XCTAssertEqual(state.base64Output, "IGEK")
    state.base64Operation = .decode
    state.base64Input = "IGEK"
    XCTAssertEqual(state.base64Output, " a\n")
}
```

2. Run `swift test --filter DeveloperToolsProviderTests/testBase64ToolPreservesWhitespaceWhenEncoding`. Expected before the fix: the encoding assertion fails. Change `refreshBase64` to use the original input for `.encode`, retaining decode normalization only where valid. Run the same command; expected: pass.
3. Add invalid-timestamp feedback and an explicit seconds/milliseconds policy. Check zero, negative timestamps, decimal seconds, milliseconds, invalid text, and non-finite numeric input before formatting.
4. Exercise every developer-tool tab with valid, invalid, empty, Unicode, and long input. Verify copied output exactly; make failures explain the accepted format.
5. Check calculator precedence, units, malformed input, non-finite results, currency loading/failure, and copied output. Treat external currency freshness as a separate network state.
6. Check translation language changes, same-language input, rapid edits, cancel/reopen, unavailable language resources, and failure recovery. A late translation must not replace newer input's result.
7. Add consistent copy feedback and clear disabled states for empty output.

**Exit:** transformations preserve the intended data, invalid input is explained, stale asynchronous results do not overwrite current work, and the full output is reachable.

### Package 5: Files, conversion, and image tools

**Modify:** `Sources/Foundry/UI/FileShelfView.swift`, `FileShelfState.swift`, `FileConversionView.swift`, `FileConversionState.swift`; services under `Features/Images` only for reproduced failures.

**Tests:** `Tests/FoundryTests/FileConversionTests.swift`, `BackgroundRemovalTests.swift`, `ArtifactStoreTests.swift`, `DependencyProvisioningTests.swift`.

1. Audit drag/drop, chooser cancellation, single/multiple selection, missing files, long paths, and duplicate names.
2. Verify conversion enables only supported combinations and preserves source files. Make source, output format, destination, progress, and completion action explicit.
3. Rework dependency setup copy so tool name, reason, scope, and action are readable. Keep exact technical details available through disclosure, not as the entire primary dialog.
4. Verify cancel and retry during conversion/background removal, model setup failure, and partial batch outcomes.
5. Confirm generated outputs can be opened or revealed. A list removal must not delete an original file.

**Exit:** each supported conversion and image operation has a verified representative input and output; unsupported combinations explain why. Inspect images visually as well as checking file existence.

### Package 6: AI, agents, integrations, and Settings

These are coverage obligations, not a claim that every listed edge case is currently broken.

**Modify after reproduction:** `Sources/Foundry/UI/QuickAIView.swift`, `QuickAIState.swift`, `AISettingsState.swift`, `AgentShelfView.swift`, `AgentMonitorState.swift`, `WidgetSettingsView.swift`, `WidgetBoardState.swift`, `HomeAccessoryStrip.swift`; the relevant files under `Features/AI`, `Features/Agents`, `Features/Browser`, `Features/Notes`, `Features/Camera`, and `Features/Widgets`.

**Tests:** the matching existing `AIProviderTests`, `AIChatStoreTests`, `AgentMonitorTests`, `AgentIntegrationTests`, `BrowserProviderTests`, `CameraPreviewTests`, and `ConfigServiceTests` suites.

1. AI: verify an unconfigured provider, valid configured provider, unavailable model, streaming, stop, retry, thread switching, persistence, and long code/text rendering. Preserve failed prompts and show actionable provider errors.
2. Agents: verify loading, no sessions, active, completed, stale, and disconnected sessions. Open must resolve to the right session. Status age and action availability must agree with the underlying adapter.
3. Browser/Notes: verify discovery, no matches, missing application, unavailable permission, stale records, and opening the correct result. Do not confuse unavailable integration with an empty library.
4. Camera: verify pre-permission, denied, no device, live preview, and closing the surface. Camera use must stop when appropriate; do not request new permission solely to manufacture a passing audit.
5. Widgets: verify loading, fresh data, stale data, offline/error, disabled widgets, and restart persistence. No fabricated metric should look like current data.
6. Settings: verify each visible control changes its advertised behavior, persists after restart, exposes validation, and provides a recovery path on save failure. Check command enablement, aliases, hotkeys, appearance, clipboard settings, and provider configuration.

**Exit:** every available configured integration has an end-to-end result. Credentials or permissions that are unavailable remain named gaps; do not declare their workflows verified.

### Package 7: Remaining commands and final product sweep

**Inspect:** every remaining route from Package 0, including emoji/symbols, app search, window layout, system utilities, and actions menus. Modify only files associated with recorded defects.

1. Emoji: search, no matches, keyboard grid navigation, copy, and pin persistence where exposed. Empty pinned content should not falsely report a failed search.
2. App search/actions: exact and fuzzy matching, rapid query replacement, empty results, selected-row stability, action selection, and context return.
3. Window management: representative layouts, multiple displays if available, permission failure, and window restoration. Use a disposable window for resizing.
4. System utilities: inspect command contracts and safe representative actions. Do not exercise shutdown, logout, process termination, or similar destructive actions as ordinary visual QA.
5. Run one uninterrupted daily-use sequence: open launcher → search → clipboard → snippet insertion → download → reveal output → convert a test file → developer tool → configured AI → Settings → close/reopen.
6. Review the diff with `code-deslop` and `ponytail`; use `thermo-nuclear-code-review` only if execution introduced substantial structural changes.
7. Run the full test/build/package checks and the final screenshot comparison.

**Exit:** the quality gate below passes, or the release report lists the exact remaining blockers. Stop adding polish once the confirmed findings and acceptance cases pass.

## Verification and handoff contract

Run commands from `/Users/hridyaagrawal/Honey/anvil`:

```sh
swift test --filter MediaDownloadTests
swift test --filter ClipboardHistoryTests
swift test --filter DeveloperToolsProviderTests
swift test
./scripts/build-app.sh
./scripts/verify-packaging.sh
git diff --check
```

Choose the focused command for the package being changed. Expected results: relevant tests pass with zero failures, app packaging exits successfully, and `git diff --check` reports no whitespace errors. Do not run the clean release build concurrently with `swift test`. A successful build alone is not a UI test.

Each behavioral change needs a regression at the existing state/service boundary that fails on the old behavior. Avoid tests that simply repeat layout implementation. Use computer use for clicks, keyboard, focus, dialogs, and screenshot evidence. Reinspect the accessibility state after actions before using new element identifiers.

Evidence belongs in `docs/qa/2026-09-05-product-polish/` during execution. For each feature, record build, setup, exact actions, expected outcome, actual outcome, screenshot filenames, and status: passed, failed, or unverified. Capture before/after at the same size and appearance. Screenshots of the already-modified Downloads draft must be labeled as draft, not original baseline.

Review the completed surface in one batched visual pass, fix its recorded defects, and confirm once more. Further iterations require a newly observed defect. Build verification must use the exact final binary that was visually tested; record any distinction between the local staged app and installed app.

Make each passing package a separate commit when execution includes committing. Stage exact files, never the whole dirty worktree. Suggested commit subjects: `Fix shared appearance and launcher navigation`, `Complete download file actions and recovery`, `Fix clipboard targets and snippet insertion`, and `Preserve developer tool input and explain failures`.

## What “excellent” will mean

The product earns that description only when:

1. Every existing feature has a coverage entry and its primary workflow passes through the actual app. Unavailable integrations are explicitly excluded from the claim.
2. No known wrong-target action, incorrect transformation, lost input, false success, or inaccessible essential control remains.
3. Light/dark appearance and accessibility variants are checked. Text, controls, selection, and errors remain legible; full content and recovery actions remain reachable.
4. The Downloads completion matrix passes, including actual saved output and failure recovery. Empty-state screenshots alone do not count.
5. Mouse and keyboard produce the same intended result; navigation preserves useful context and visible controls match actual shortcuts.
6. Tests, packaging, and the final visual pass refer to the final revision. Performance meets the existing roadmap's measured baseline without an unexplained regression.

The final report should name completed packages, show representative before/after evidence, list verification results, and identify anything unverified. It must not substitute “perfected” or a numerical taste score for that evidence.

## Review decision

Recommended sequence: Package 0 → shared foundation → Downloads → clipboard/snippets → tools/translation → files → integrations/settings → final sweep.

Review this plan before implementation resumes. The first review should settle the disposition of the existing draft and the compact native direction. Each execution package then supplies its own concrete diff and evidence. No product implementation, installation, or commit is part of this planning handoff.
