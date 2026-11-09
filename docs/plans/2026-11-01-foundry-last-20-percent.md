# Foundry, the last 20% — Implementation Plan

Status (2026-11-09): executed. This is the plan for the Swift app, Phases 0–7, committed 2026-11-01 to 2026-11-02 and released as 1.3.0 (`0f23e20`). It is not the website plan (see `2026-11-01-foundry-last-20.md`). Audits: `2026-11-01-last-20-audits/`.

> **For Claude:** REQUIRED SUB-SKILL: Use `executing-plans` to implement task-by-task. Load `emil-design-eng` for every motion value, `clean-copy` for every string, `onboarding-design` for Phase 3, `test-driven-development` for every behaviour change, `verification-before-completion` before any done claim. Subagents that judge visuals run on `claude-opus-5-5` (memory: design subagents on Opus).

**Goal:** Make every interaction in Foundry feel like the best Mac software made it: Raycast's keyboard truth, Linear's restraint, Things 3's quiet, Arc and Dia's first run. Nothing new in scope; depth on what exists.

**Architecture:** Foundry is a Swift 6 SPM package (targets `Foundry`, `FoundryDomain`, `FoundryServices`), SwiftUI inside an AppKit non-activating panel. The visual vocabulary is `Sources/Foundry/UI/FoundryTheme.swift`, enforced by `scripts/lint-design.sh`. Panel state is split across `CommandPanelState` and its extensions; feature modes implement `PanelFeature`; the footer, ⌘K actions and prompts are owned by `PanelSession` and `FeatureSurface`. Onboarding is its own window (`UI/Onboarding/`). We change behaviour under tests, change visuals under snapshot tests and lint rules, and judge the result from captures of the real app, never from code alone.

**Tech Stack:** Swift 6.1/6.2, SwiftUI, AppKit, XCTest, `swift test --filter`, `scripts/lint-design.sh`, `scripts/lint-l10n.sh`, `scripts/lint-lines.sh`, `scripts/qa-capture.swift` (live panel PNGs), `FOUNDRY_QA_SNAPSHOT_DIR` offscreen renders (`OnboardingSnapshotTests`, `PreviewSnapshotTests`), `scripts/drive-signposts.swift` (latency), `top` and `xctrace` (idle cost).

---

## 0. Why this plan exists

Foundry is at the 80% mark. The Raycast-bar audit of 2026-10-11 (56 findings) is implemented. Latency p95 is under budget. 650+ tests are green. The remaining gap is not a missing feature. It is the layer of care that separates "works" from "feels inevitable": the first frame, the footer that tells the truth, the error that names the fix, the Esc that peels one layer, the onboarding that ends with something of your own.

Three read-only audits were run on 2026-11-01 against this tree and saved beside this plan:

- `docs/plans/2026-11-01-last-20-audits/panel.md` (launcher core: entrance, rows, search field, states, footer, ⌘K, keyboard, motion, pointer, accessibility, copy, tokens)
- `docs/plans/2026-11-01-last-20-audits/features.md` (clipboard, snippets, Quick AI, shelf, conversion, media, translator, emoji, developer tools, calculator, camera, agents, drop, Settings)
- `docs/plans/2026-11-01-last-20-audits/onboarding.md` (activation moment, step table, permissions, copy, Arc and Dia comparison)

Every task below cites a finding by file and line. The P0 claims were re-read in the source before this plan was written. Visual claims in the audits (overlap, alignment) are code-derived and get confirmed by a capture in the task that touches them.

### The bar, stated so it can fail

A task is done when all of these hold for the surface it touched:

1. **Frame 1 is final.** No blank, placeholder or shifting frame on open, reopen or first keystroke.
2. **The footer never lies.** Every key shown does exactly what it says, and nothing is shown when nothing would happen.
3. **Everything clickable is keyboard-reachable, and every key path is instant** (no animation on keyboard-initiated changes).
4. **Every state is designed:** default, hover, pressed, focus, disabled, loading, empty (first use), empty (filtered), error. Error copy names the fix.
5. **Esc peels one layer.** Prompt, then filter, then feature, then panel.
6. **Browsing never mutates data.**
7. **One vocabulary.** Every size, colour, opacity, radius and duration comes from `FoundryTheme`, and the lint proves it.
8. **Reduced Motion, Reduce Transparency, Increase Contrast and VoiceOver each have a designed path**, verified by a render or an announcement.
9. **Evidence, not claims.** A red-then-green test, a lint that was red, a snapshot diff, or a capture you looked at.

### Open decisions (taste calls, recommendation first)

The tasks below implement the recommended option. If the user chooses otherwise, change the task, not the bar.

| # | Decision | Recommendation | Alternative |
|---|---|---|---|
| D1 | Panel entrance | Opacity 0 to 1 over 0.10 s on `timingCurve(0.23, 1, 0.32, 1)`, scale at most 0.98 over 0.14 s, **no spring**, content present on frame 1. | Keep the 1.1 spring from 0.97 (the user restored it once; see progress.md "Restored the v1.1.0 panel look"). |
| D2 | Onboarding length | Four screens: Welcome, Shortcut and Try (merged), Bring your stuff (only when Alfred or Raycast is detected), Done. Preferences, Permissions and AI leave the flow. | Keep seven screens and polish each. |
| D3 | Launch at login | On by default, shown on Done as a row the user can turn off before finishing. | Off by default, as today. |
| D4 | Camera surface | Cut. It has no action, no capture, no mirror. | Keep and add capture plus mirror toggle. |
| D5 | Developer Tools and Translator | Keep as modes, fix them (Return, Esc, errors, memory). Do not convert to inline results in this plan. | Fold into root results and ⌘K transforms (bigger, not deeper). |
| D6 | Casing rule | Actions, commands and buttons in Title Case (HIG). Headings, states, messages and hints in sentence case. | All sentence case. |
| D7 | Media favicons | Tie to the existing quicklinks "Site icons" switch; off means bundled glyphs only. No silent third-party calls. | Keep DuckDuckGo always on. |
| D8 | Commits | Small commits per task on this branch, Foundry files only (never `anvil/`, `foundry-ad/`, `launch-film/`, `.devin/`). | One commit per phase. |

---

## 1. Operating rules for the executor

- Run the narrowest filter per task: `swift test --filter <SuiteName>`. Run the whole suite plus the three lints only at phase gates.
- Every string is user-facing copy: load `clean-copy`, apply D6, and keep `scripts/lint-l10n.sh` green (new strings go through `LocalizedStringResource`).
- Every duration and curve comes from the new `FoundryTheme.Motion` (Task 2.1). Do not write `duration:` or `.spring` outside the theme.
- Snapshot references live beside `PreviewSnapshotTests` and `OnboardingSnapshotTests`. When a task changes a reference on purpose, regenerate it, look at the PNG, and say what changed.
- Live captures: `swift scripts/qa-capture.swift <dir> [home|search|actions|clipboard|settings]` against a running build. Do not send synthetic ⌘Space while the user is at the machine (progress.md records two failed attempts). Ask first or run from the bench bundle `com.hridya.foundry.bench`.
- No new dependencies. No new feature surfaces. If a fix would widen scope, write it in `progress.md` under "Deferred" and move on.
- Keep `progress.md` current after every task: what landed, the evidence path, what is open.

---

## Phase 0 — Land the branch and freeze the baseline

The tree carries 182 modified and 13 untracked Foundry files from the mini port (progress.md "Port from old mini line", bugs B1–B7, features F1–F20), uncommitted. Nothing in this plan can be measured until that work is landed and green.

### Task 0.1: Verify the uncommitted work

**Files:** none changed.

**Step 1: Build and test the tree as it stands**

```sh
swift build 2>&1 | tail -3
swift test 2>&1 | tail -5
scripts/lint-design.sh && scripts/lint-l10n.sh && scripts/lint-lines.sh
```

Expected: build clean, `Executed 6xx tests, with 0 failures`, three lints print nothing and exit 0. If one run shows a single non-repeating failure (progress.md saw one), run that suite alone three times and record the result in `progress.md`.

**Step 2: Record the counts**

Append to `progress.md`: test count, skipped count, lint status, the commit hash of HEAD, and the `git status --short | wc -l` figure.

### Task 0.2: Commit the port in logical units

**Files:** everything under `Sources/`, `Tests/`, `Package.swift`, `README.md`, `scripts/`, `docs/` that `git status` lists. Exclude `anvil/`, `foundry-ad/`, `.devin/`, `.jury/`, `launch-film/`.

**Step 1: Group by concern**

Use `git add -p` groups matching progress.md's ledger: (a) bug fixes B1–B7, (b) fallbacks F1, (c) scripts and shortcuts F2–F4, F6, (d) snippets and quicklinks F5, F17, (e) settings panes F8, (f) clipboard F9, (g) Quick AI F10, (h) translator, emoji, what's new, footer count F11–F14, (i) app results, contrast, favicons, ⌘K title, copy F15–F20, (j) onboarding files under `UI/Onboarding/` and `Resources/Onboarding/`, (k) scripts (`render-icon.swift`, `render-dmg-background.swift`, `build-app.sh`, `package-dmg.sh`).

**Step 2: Commit each group** with a one-line subject naming the ledger items, body listing files. Run `swift build` between groups only if a group touches `Package.swift` or resources.

**Step 3: Gate**

`swift test` full, three lints. Expected: same numbers as Task 0.1.

### Task 0.3: Freeze the "before" captures

**Files:** create `docs/qa/2026-11-01-last-20/before/`.

**Step 1: Offscreen renders**

```sh
FOUNDRY_QA_SNAPSHOT_DIR=docs/qa/2026-11-01-last-20/before swift test --filter 'OnboardingSnapshotTests|PreviewSnapshotTests'
```

Expected: PNGs for every onboarding step and the clipboard and row-anatomy previews, light mode.

**Step 2: Live panel captures** (ask the user, or use the bench bundle): home, search for "als", actions, clipboard, settings, in light and dark, plus one capture with Reduce Transparency on and one with Increase Contrast on.

**Step 3: Measure the two numbers this plan must not regress**

- `swift scripts/drive-signposts.swift 30 --reopen build/Foundry.app` for `panel.show` and `search.immediate` p50/p95.
- Panel open, idle, `top -pid $(pgrep -x Foundry) -l 5 -s 5` for CPU. Record both in `docs/benchmarks/2026-11-01-last-20-before.md`.

### Task 0.4: Add the lint ratchets as failing checks

The audits found values that pass `lint-design.sh` by shape: ternary opacities, raw `cornerRadius:` literals, raw `duration:` literals, `Color.red`/`Color.green`, `FoundryTheme.dark(0.06)`.

**Files:** Modify `scripts/lint-design.sh`. Create `scripts/lint-design-ratchet.txt` (a list of currently allowed violation counts per rule).

**Step 1: Write the failing check**

Extend the grep set to: `cornerRadius: *[0-9]`, `duration: *[0-9]`, `\.spring\(`, `opacity\([^)]*[0-9]\.[0-9]`, `Color\.(red|green|blue|orange|yellow)`, `FoundryTheme\.(dark|light|primary)\([0-9]`. Each rule reads its allowed count from the ratchet file; a count above the allowance fails.

**Step 2: Run it**

`scripts/lint-design.sh` Expected: FAIL, printing the violations per rule with counts.

**Step 3: Seed the ratchet** with today's counts so the script passes, and commit. From here every task that touches a file must lower its rule count or hold it. Phase 6 drives every count to zero and deletes the ratchet file.

**Step 4: Run it** Expected: PASS.

---

## Phase 1 — Trust: bugs that make the product lie

Each of these was verified in the source. They go first because polish on top of a lie is still a lie.

### Task 1.1: Onboarding survives a quit

Finding: onboarding.md "Fix before anything else". `CommandPanelState.swift:159` writes the config on first launch, so `configExistedAtLaunch` is true on the next launch and `OnboardingState.shouldShowAutomatically` (`OnboardingState.swift:97-99`) returns false. The saved `onboardingStep` is never consulted. `OnboardingStateTests.swift:17-22` asserts the wrong gate.

**Files:** Modify `Sources/Foundry/UI/Onboarding/OnboardingState.swift:97-99`; Modify `Tests/FoundryTests/OnboardingStateTests.swift:17-22`.

**Step 1: Write the failing test** `testResumesAfterQuitWhenAStepWasSaved`: set `onboardingStep = OnboardingStep.tryIt.rawValue` and `onboardingCompletedVersion = nil` in the local state, call `shouldShowAutomatically(localState:configExistedAtLaunch: true)`, assert true. Add a second assertion that a completed version returns false even with a saved step. Fix the existing test's second assertion so `configExistedAtLaunch: true` with no saved step still returns false.

**Step 2: Run it** `swift test --filter OnboardingStateTests` Expected: FAIL on the new assertion.

**Step 3: Minimal implementation** `completedVersion == nil && (configExistedAtLaunch == false || localState.get(\.onboardingStep) != nil)`. On `finish()`, clear `onboardingStep`.

**Step 4: Run it** Expected: PASS.

**Step 5: Manual check** Quit on Try it, relaunch, onboarding opens on Try it. Record in `progress.md`.

### Task 1.2: Every exit from onboarding is inert

Finding: onboarding.md C3. `OnboardingView.swift:103` `.onExitCommand { state.finish() }`; `OnboardingState.swift:122` `finish()` claims ⌘Space, which disables Spotlight's shortcut and quits Raycast or Alfred, from any step including Welcome. Skip and the close button route the same way.

**Files:** Modify `OnboardingState.swift:121-130` (split `finish()` into `finish()` and `abandon()`); Modify `OnboardingView.swift:103` and the Skip button; Modify `OnboardingWindowController.swift:65` (`windowWillClose`); Test `OnboardingStateTests.swift`.

**Step 1: Write the failing test** `testAbandonNeverClaimsCommandSpace`: inject a spy for `claimCommandSpace`, call `abandon()` from `.welcome`, assert the spy was not called, assert `onboardingCompletedVersion` is set (so it does not reappear) and `onboardingStep` is cleared.

**Step 2: Run it** Expected: FAIL, `abandon` not defined.

**Step 3: Implement** `abandon()` marks complete and stops the Spotlight poll, nothing else. Esc, Skip and window close call `abandon()`. `finish()` stays for Done. Esc on the Try it step while the panel is open must not reach `onExitCommand` (the panel is key, so it does not; add a test that `onExitCommand` is only wired when `step != .tryIt || panelOpen == false`).

**Step 4: Run it** Expected: PASS.

### Task 1.3: Reopen shows Home on frame 1

Finding: panel.md 1 P0. `CommandPanelState+Lifecycle.swift:27-29` sets `query = ""` (which repaints Home from cache) then `results = []` and `selectedResultID = nil`, wiping it until async `loadHome` lands.

**Files:** Modify `Sources/Foundry/UI/CommandPanelState+Lifecycle.swift:23-31`; Test `Tests/FoundryTests/CommandPanelStateTests.swift`.

**Step 1: Write the failing test** `testReopenInsidePopToRootWindowKeepsHomeRowsOnFirstFrame`: open, type "sa", close, reopen within the pop-to-root window, assert `session.results.isEmpty == false` and `selectedResultID == navigableResults.first?.id` synchronously after `panelWillOpen`.

**Step 2: Run it** Expected: FAIL (results empty).

**Step 3: Implement** Delete the two wiping lines. Keep `query = ""` for this task (D-note: Raycast keeps the query and selects all; that is Task 2.5).

**Step 4: Run it** Expected: PASS.

### Task 1.4: The footer never lies

Findings: panel.md 5 P0 and P1. `PanelSession.swift:292` returns "Open" with no selection; while a `PanelPrompt` is up the footer still advertises the row action (`CommandPanelView.swift:143-154` vs `911-940`).

**Files:** Modify `Sources/Foundry/UI/PanelSession.swift:288-294` (`preferredActionTitle: String?`); Modify `Sources/Foundry/UI/CommandPanelView.swift:894-940`; Test `Tests/FoundryTests/CommandPanelStateTests.swift`.

**Step 1: Write the failing tests** `testFooterShowsNothingWithNoSelection` (results empty, assert `searchFooterActions.isEmpty`), `testFooterShowsPromptVerbsWhilePromptIsUp` (present a prompt with confirm label "Move to Trash", assert footer is `[↵ Move to Trash, esc Cancel]`).

**Step 2: Run** Expected: FAIL.

**Step 3: Implement** `preferredActionTitle` returns nil without a selection. The footer builder checks `pendingPrompt` first, then the selection, else empty.

**Step 4: Run** Expected: PASS.

### Task 1.5: Browsing snippets never mutates them

Finding: features.md Snippets P0. `SnippetsView.swift:498-503` syncs on selection, which calls `updateSelected` (`SnippetState.swift:128-137`) which stamps `updatedAt` and re-sorts after 350 ms, so the selected row jumps to the top.

**Files:** Modify `Sources/Foundry/UI/SnippetState.swift:128-137`; Test `Tests/FoundryTests/LibraryPersistenceTests.swift` or a new `SnippetStateTests.swift`.

**Step 1: Write the failing test** `testSelectingASnippetDoesNotChangeUpdatedAt`: create three snippets with distinct `updatedAt`, select the last, call `updateSelected` with identical fields, assert `updatedAt` unchanged and order unchanged.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement** Early return when title, content, keyword and tags equal the stored values.

**Step 4: Run** Expected: PASS.

### Task 1.6: Quick AI errors look like errors and the view follows the stream

Findings: features.md Quick AI P0 ×2. `QuickAIState.swift:233-238` writes the failure into `quickAIResponse`; `QuickAIView.swift:53` is a bare `ScrollView`.

**Files:** Modify `Sources/Foundry/UI/QuickAIState.swift` (add `quickAIError: QuickAIError?` with cases `rejectedKey(provider)`, `rateLimited(provider)`, `offline`, `other(String)`); Modify `Sources/Foundry/UI/QuickAIView.swift:53-80` (`ScrollViewReader`, bottom anchor, `InlineNotice(.error, …, actionTitle: "Retry")`); Test `Tests/FoundryTests/AIChatStoreTests.swift` or new `QuickAIStateTests.swift`.

**Step 1: Write the failing test** `testProviderFailureIsNotRenderedAsAnAnswer`: stub a provider that throws 401, submit, assert `quickAIResponse` is empty and `quickAIError == .rejectedKey("OpenAI")`. Map 429 to `.rateLimited`, `URLError.notConnectedToInternet` to `.offline`.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement** the mapping and the view: copy per case: "Your API key was rejected. Update it in Settings › AI." / "Rate limited by OpenAI. Retry in a minute or switch model." / "You're offline. Switch to Apple Intelligence or retry." Auto-scroll: on `quickAIResponse` change while loading and `userScrolledUp == false`, `proxy.scrollTo("bottom", anchor: .bottom)` with no animation.

**Step 4: Run** Expected: PASS. Offscreen render of the error state into `docs/qa/2026-11-01-last-20/quickai-error-light.png`; look at it.

### Task 1.7: Clipboard failures appear where they happen

Findings: features.md Clipboard P0 ×2 and P1. `CommandPanelState+Paste.swift:12,31` and `ClipboardHistoryState.swift:176` write to `clipboardHistory.report`, which nothing renders; `SettingsView.swift:1026` shows that same object as a persistence error; a failed direct paste silently falls back to copy while the footer still says "Paste ↵".

**Files:** Modify `Sources/Foundry/UI/CommandPanelState+Paste.swift:12-31`; Modify `Sources/Foundry/UI/ClipboardHistoryState.swift` (split `report` into `actionError` and `persistenceError`); Modify `Sources/Foundry/UI/Settings/SettingsView.swift:1026`; Modify `Sources/Foundry/UI/CommandPanelView.swift` footer for clipboard mode; Test `Tests/FoundryTests/ClipboardHistoryTests.swift`.

**Step 1: Write the failing tests** `testOCRFailureShowsPanelFeedback` (stub OCR returning no text, assert `showActionFeedback` received `.failure("No text found in this image. Try a sharper screenshot.")`), `testPasteFallbackTellsTheUser` (make `DirectPasteService` throw, press Return, assert feedback `.info("Copied. Paste with ⌘V. Allow Accessibility to paste directly.")`), `testClipboardFooterSaysCopyWhenAccessibilityIsMissing`.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement.** Settings shows only `persistenceError`: "Couldn't save clipboard history: \(reason). Check free disk space."

**Step 4: Run** Expected: PASS.

### Task 1.8: Arrows never move an invisible list

Finding: features.md Shared P0. `CommandPanelState+Input.swift:73`: in Media, Developer Tools, Quick AI and Agents, arrows call `session.moveSelection` on the hidden root results.

**Files:** Modify `Sources/Foundry/UI/CommandPanelState+Input.swift:65-80`; Modify `Sources/Foundry/UI/PanelFeature.swift` (add `func handleMove(_ direction: MoveDirection) -> Bool` with a default of `false`); Modify `MediaDownloadsView.swift` and `AgentShelfView.swift` to own `selectedID`; Test `Tests/FoundryTests/PanelKeyboardTests.swift`.

**Step 1: Write the failing test** `testArrowsInMediaModeDoNotTouchRootSelection`: enter media mode with two downloads, press down, assert `session.selectedResultID` unchanged and media `selectedID` is the second download. Same for agents. For Quick AI and Developer Tools assert both unchanged.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement** the hook; the input router asks the active feature first.

**Step 4: Run** Expected: PASS.

### Task 1.9: Overlays are readable without glass

Finding: panel.md 9 P0. `FoundryControls.swift:19` uses `scrimStrong` (black 0.5) as the `floatingOverlay` fallback under Reduce Transparency and on every pre-macOS 26 build: the ⌘K panel, prompt, drop chooser and feedback capsule render as mid-gray with dark text in light mode.

**Files:** Modify `Sources/Foundry/UI/FoundryControls.swift:14-22`; Modify `Sources/Foundry/UI/FoundryBackdrop.swift` if the material view lives there; Test `Tests/FoundryTests/PreviewSnapshotTests.swift`.

**Step 1: Write the failing snapshot** `testRenderActionsOverlayWithReduceTransparency`: render the actions surface in light mode with the reduce-transparency environment forced on, sample the overlay's centre pixel, assert its luminance is above 0.85 (window background), not around 0.5.

**Step 2: Run** `swift test --filter PreviewSnapshotTests` Expected: FAIL (luminance ≈ 0.5).

**Step 3: Implement** Reduce Transparency: `Color(nsColor: .windowBackgroundColor)` plus a 0.5 pt `separator` stroke. Legacy systems: `VisualEffectView(material: .popover)` plus the same stroke.

**Step 4: Run** Expected: PASS. Look at the PNG in both appearances.

### Task 1.10: Destructive Settings actions confirm

Findings: features.md Settings P0 and P1. `QuicklinksSettingsPane.swift:88` and `FileSearchSettingsPane.swift:39` "Restore Defaults" replace user data at once; `SettingsPaneRows.swift:302` "Remove profile" deletes a Keychain key at once; lowering clipboard retention trims live (`SettingsView.swift:962-1017`).

**Files:** Modify those four sites; Test `Tests/FoundryTests/SettingsSearchTests.swift` (or new `SettingsActionsTests.swift`) for the state layer: each destructive action goes through a `pendingConfirmation` before mutating.

**Step 1: Write the failing test** `testRestoreQuicklinkDefaultsRequiresConfirmation`: with three custom links, call `restoreDefaults()`, assert links unchanged and `pendingConfirmation?.title == "Replace your 3 quicklinks with the defaults?"`; call `confirm()`, assert replaced.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement** with `confirmationDialog`, role `.destructive`, button titles "Replace", "Remove Profile" ("Remove \(name)? Its API key is deleted from the Keychain."), and "This removes \(n) older items." for retention.

**Step 4: Run** Expected: PASS.

### Task 1.11: One system prompt at a time for Accessibility

Finding: onboarding.md B. `PermissionHealthState.swift:84-90` calls `AXIsProcessTrustedWithOptions(prompt: true)` and then also opens System Settings, so two surfaces appear at once.

**Files:** Modify `Sources/Foundry/UI/PermissionHealthState.swift:80-95`; Modify `scripts/build-app.sh:~180` (add `NSAppleEventsUsageDescription`: "Foundry asks apps for the current selection and tab so commands can act on them."); Test `Tests/FoundryTests/ResourcePackagingTests.swift` for the plist key.

**Step 1: Write the failing test** `testInfoPlistCarriesAppleEventsUsageDescription`.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement.** The request path: prompt once; open System Settings only on a second explicit click ("Open System Settings") or when `AXIsProcessTrusted()` is still false after the prompt returns and the user has already been prompted once (store `accessibilityPromptedAt`).

**Step 4: Run** Expected: PASS. Manual check on a clean user account: exactly one surface opens.

### Phase 1 gate

`swift test` full, three lints, `lint-design-ratchet` counts not higher than Phase 0. Update `progress.md`.

---

## Phase 2 — The panel: every interaction in the launcher core

### Task 2.1: Motion becomes a token

Finding: panel.md 7 P1 and the inventory table; features.md Shared P2.

**Files:** Modify `Sources/Foundry/UI/FoundryTheme.swift` (add `enum Motion`); Modify `scripts/lint-design.sh` (rule `duration:` allowance to 0 outside theme after this task's sweep); Modify every site in the inventory table in panel.md 7.

Token set, all on `timingCurve(0.23, 1, 0.32, 1)` unless named:

```
Motion.press      0.10 s  (scale 0.97, opacity 0.7; release 0.18 s)
Motion.hover      0.10 s  ease-out, opacity only
Motion.state      0.14 s  (content arrives, counts change)
Motion.overlayIn  0.15 s  (⌘K, prompt, drop chooser; opacity + scale 0.98, anchor at origin)
Motion.overlayOut 0.10 s  ease-in
Motion.enter      0.10 s  (panel opacity), scale 0.98 over 0.14 s   [D1]
Motion.exit       0.06 s  ease-in (Esc, click-away); 0 for Return-driven dismissals
Motion.toastIn    0.12 s, hold 1.6 s, out 0.18 s ease-in
```

**Step 1: Write the failing check** Set the `duration:` and `.spring(` ratchet allowances to 0. Run `scripts/lint-design.sh`. Expected: FAIL listing every ad hoc site.

**Step 2: Implement** the tokens and replace each site. Delete the dead transitions (`CommandPanelView.swift:81, 105-121, 494, 529`), the drop-target `phaseAnimator` (`:636-640`), and the mode crossfade (`:84-89`) in favour of an incoming-only `Motion.hover` opacity. Merge the two press styles in `FoundryControls.swift:142,154`. `PanelController.swift:59` compact resize becomes `animate: false`.

**Step 3: Run the lint** Expected: PASS. `swift test --filter PanelKeyboardTests` still PASS.

### Task 2.2: Frame 1 is final, and the exit is instant when it should be

Findings: panel.md 1 P1 ×4. `CommandPanelView.swift:259-266` `presented = false` then `DispatchQueue.main.async` then spring; `PanelController.swift:216` shadow never invalidated; `:143-149` exit fade delays paste; `:59` resize animates on a keystroke.

**Files:** Modify `Sources/Foundry/UI/CommandPanelView.swift:22, 173-174, 259-266`; Modify `Sources/Foundry/Shell/PanelController.swift:62-91, 123-157, 216`; Test `Tests/FoundryTests/PanelShellTests.swift`.

**Step 1: Write the failing tests** `testShowPresentsContentBeforeOrderFront` (observe `presentationToken` changes before `makeKeyAndOrderFront` via the fake panel's call log), `testReturnDrivenHideOrdersOutImmediately` (call `hide(reason: .executed)`, assert `orderOut` was called synchronously, before any run-loop turn), `testEscapeHideFadesThenOrdersOut` (reason `.dismissed`, assert `orderOut` after the group completes).

**Step 2: Run** Expected: FAIL.

**Step 3: Implement** `hide(reason:)` with `.executed` and `.dismissed`. Set the start state before ordering front; animate opacity with `Motion.enter`; call `panel.invalidateShadow()` in the completion and after `setCompactCollapsed`.

**Step 4: Run** Expected: PASS.

**Step 5: Evidence** A screen recording of the real panel opening at 120 fps (`screencapture -V 2` or QuickTime), stepped frame by frame: frame 1 contains rows. Save a frame to `docs/qa/2026-11-01-last-20/frame1.png`.

### Task 2.3: One row everywhere

Finding: panel.md 2 P1 and P2; features.md Shared and Clipboard P2. Three row components, two heights, two icon sizes, icon scale on selection, fill plus border selection.

**Files:** Delete `HomeResultRow` in `Sources/Foundry/UI/PanelRowViews.swift:69-99`; Modify `ResultRow` (`:288-336`), `PanelChrome.swift:51-91` (action rows), `CommandPanelView.swift:661` (stack spacing 2); Modify `PanelRowViews.swift:79, 291` and `PanelChrome.swift:68` (remove `scaleEffect`); `PanelRowViews.swift:12-26` (fill only; 2 pt accent border only under Increase Contrast); `:317-322` running dot 4 pt `textTertiary` after the title; `:344-356` one `Badge` 20 pt radius `Radius.badge` `fillTint`; `:376-394` fallback tile `FoundrySmoothedRectangle(cornerRadius: size * 0.2237)`. Test `Tests/FoundryTests/PreviewSnapshotTests.swift` `testRenderRowAnatomy`.

**Step 1: Update the row-anatomy snapshot test** to assert: row height 44 (38 compact), icon 28, title `FoundryTheme.body`, no border on the selected row in the default environment, a 2 pt border under `foundryIncreaseContrast`. Regenerate the reference after looking at it.

**Step 2: Run** Expected: FAIL on the old reference.

**Step 3: Implement.** Also align the header: `FeatureSurface.swift:33` horizontal padding 22 → 28 so the field's text sits on the icon column (16 inset + 12 row padding).

**Step 4: Run** Expected: PASS with the new reference. Capture home and search live; the list must not shift between them (Task 2.6 finishes that).

### Task 2.4: The ⌘K actions panel behaves like Raycast's

Findings: panel.md 3 P0, 5 P1 ×5, P2 ×2. The main field is rebound to `actionFilter` (`CommandPanelView.swift:469-470`); spring with overshoot (`:128-139`); centre-scroll (`+Surfaces.swift:110-113`); destructive actions not grouped (`PanelChrome.swift:72`); "ACTIONS" kicker (`+Surfaces.swift:62-79`); glass keycaps (`FeatureSurface.swift:156-171`).

**Files:** Modify `Sources/Foundry/UI/CommandPanelView.swift:128-139, 466-472`; Modify `Sources/Foundry/UI/CommandPanelView+Surfaces.swift:62-113`; Modify `Sources/Foundry/UI/PanelChrome.swift:51-91`; Modify `Sources/Foundry/UI/FeatureSurface.swift:156-171`; Modify `Sources/Foundry/UI/FoundryTheme.swift` (`Radius.popover = 18`); Test `Tests/FoundryTests/PanelKeyboardTests.swift`, `PreviewSnapshotTests.swift`.

**Step 1: Write the failing tests** `testOpeningActionsKeepsRootQueryVisible` (query "sa", open actions, assert `session.query == "sa"` and the header binding is still `query`), `testDestructiveActionsSortLast` (a result with Open, Copy Path, Move to Trash; assert order ends with Move to Trash and `actionGroups.last?.isDestructive`), `testActionsSelectionScrollsMinimally` (reuse the visible-ID guard from `CommandPanelView.swift:736-746`).

**Step 2: Run** Expected: FAIL.

**Step 3: Implement.** A 32 pt filter field at the bottom of the actions surface bound to `actionFilter`, `bodySecondary`. Header: the result's 16 pt icon plus title in `caption` `textSecondary`, no kicker. Groups with quiet labels ("Open with", "Foundry"); destructive group last behind a 1 pt `separator` with 4 pt padding, icon and title in `destructive`. Popover radius 18 (row 10 + inset 8), `Motion.overlayIn`/`overlayOut`, anchor `.bottomTrailing`. Keycaps flat: `fillTint`, radius 6, 19 pt, `caption` `textSecondary`.

**Step 4: Run** Expected: PASS. Render `actions-light.png` and `actions-dark.png`; look at them.

### Task 2.5: The search field holds still and tells the truth

Findings: panel.md 3 P1 ×4, P2; 1 P0 note on keeping the query. `PanelChrome.swift:170-192` `fitTextToWidth`; `:151` Shift-Tab opens AI; `:149-160` `cancelOperation:`/`moveUp:`/`moveDown:` not intercepted; `CommandPanelView.swift:913-930` "Searching…"/"N results" flicker.

**Files:** Modify `Sources/Foundry/UI/PanelChrome.swift:140-192`; Modify `Sources/Foundry/UI/CommandPanelView.swift:486-495, 913-930`; Modify `Sources/Foundry/UI/CommandPanelState+Lifecycle.swift:27` (keep the query inside the pop-to-root window, select all); Test `Tests/FoundryTests/PanelKeyboardTests.swift`.

**Step 1: Write the failing tests** `testShiftTabDoesNothingInSearch`, `testReopenInsideWindowKeepsQuerySelected` (reopen within the window, assert `query == "sa"` and `fieldSelectsAllOnFocus == true`), `testLoadingHairlineAppearsOnlyAfter150ms` (set loading, advance the test clock 100 ms, assert hidden; 200 ms, assert shown), `testFooterHasNoResultCount`.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement.** Delete `fitTextToWidth` (20 pt fixed, scrollable). `doCommandBy` returns true for `cancelOperation:` (→ `onEscape`), `moveUp:`/`moveDown:` (→ selection), `insertTab:` only. A 1 pt indeterminate hairline under the header, `accent` at 0.6, shown after 150 ms of loading. Remove the clear button's dead transition.

**Step 4: Run** Expected: PASS.

### Task 2.6: The first keystroke does not move the list

Finding: panel.md "ten changes" 6. The accessory strip, favorites and What's New sit above the list at Home and vanish on the first keystroke, so the list jumps about 70 pt.

**Files:** Modify `Sources/Foundry/UI/CommandPanelView.swift:595-615, 658-700` (strip moves below the list, above the footer; favorites and layout rows become the first rows of the Home list with a fixed-height header slot); Test `Tests/FoundryTests/PreviewSnapshotTests.swift`.

**Step 1: Write the failing test** `testListTopEdgeIsFixedBetweenHomeAndSearch`: render Home and a search; find the first row's y in each render (the first `RowBackground` frame via a preference key exposed for tests); assert equal.

**Step 2: Run** Expected: FAIL.

**Step 3: Implement.** **Step 4: Run** Expected: PASS. Live capture Home then type one letter; compare.

### Task 2.7: No dead ends

Findings: panel.md 4 P0, P1 ×2, P2 ×2. No-results is a tile (`CommandPanelView.swift:585-591`); loading replaces the list (`:567, 581, 583`); two empty-state components (`FeatureSurface.swift:187-231`, `FoundryControls.swift:235-276`); message truncates at one line; no search error state.

**Files:** Modify `Sources/Foundry/UI/CommandPanelView.swift:563-591`; Modify `Sources/Foundry/UI/ResultSections.swift` (expose fallback rows as navigable); Delete `EmptyState` in `FeatureSurface.swift:187-231`, keep `FoundryEmptyState` (56 pt tile, `Radius.overlay`, `body` title, `bodySecondary` text, `lineLimit(2)`, `maxWidth 420`, optional action); add `InlineNotice(.warning)` row for a provider failure; Test `Tests/FoundryTests/PanelKeyboardTests.swift`, `ResultSectionTests.swift`.

**Step 1: Write the failing tests** `testNoResultsOffersNavigableFallbacks` (query "zzzq", assert `navigableResults` contains Ask AI, Search the Web, Search Files, and Return on the first runs it), `testColdHomeShowsSkeletonNotSpinner` (no cache, assert the view model reports `.skeleton(5)`), `testProviderFailureShowsNoticeRow`.

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** Copy: "Spotlight isn't responding. File results may be missing." **Step 4: Run** Expected: PASS. Render `no-results-light.png`.

### Task 2.8: The keyboard reaches everything

Findings: panel.md 6 P0, P1 ×4. Favorites and the layout row are outside `navigableResults` (`CommandPanelView.swift:684-699`, `PanelSession.swift:88-100`); Esc in feature modes skips the filter (`PanelRouter.swift:224`); only ↑/↓ move (`PanelController.swift:392-413`); visibility tracking via `onAppear` (`PanelRowViews.swift:458-461`).

**Files:** Modify `Sources/Foundry/UI/PanelSession.swift:88-100, 319-335`; Modify `Sources/Foundry/Shell/PanelController.swift:392-413`; Modify `Sources/Foundry/UI/PanelRouter.swift:215-224`; Modify `Sources/Foundry/UI/PanelRowViews.swift:134, 458-461` (`onScrollVisibilityChange(threshold: 1.0)` on macOS 15, fallback to the current path); Modify `CommandPanelView.swift:684-699` (⌘1–⌘8 for favorites; holding ⌘ fades in a `caption` keycap under each tile over `Motion.hover`); Test `Tests/FoundryTests/PanelKeyboardTests.swift`.

**Step 1: Write the failing tests** `testCommandDigitOpensFavorite` (⌘3 runs the third favorite), `testControlNAndPMoveSelection`, `testCommandArrowsJumpToEnds`, `testPageDownMovesSevenRows`, `testEscapeClearsFeatureFilterBeforeGoingHome` (clipboard with query "a": first Esc clears, second goes Home; this replaces `testEscapeInFeatureModeGoesHome` at `PanelKeyboardTests.swift:78`).

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** Expected: PASS.

### Task 2.9: VoiceOver hears the selection, and contrast steps up

Findings: panel.md 9 P0, P1, P2 ×2. No announcement on selection change (`PanelSession.swift:319-335`); Increase Contrast leaves tertiary text at 0.56 (`FoundryTheme.swift:102-105`); shortcuts read as glyph names (`+Surfaces.swift:78`, `PanelChrome.swift:78`).

**Files:** Modify `Sources/Foundry/UI/PanelSession.swift` (post `NSAccessibility.post(element: NSApp, notification: .announcementRequested, …)` with "\(title), \(kind), \(i) of \(n)", high priority); Modify `FoundryTheme.swift:102-105` (environment-aware tertiary 0.74 and quaternary 0.60 under Increase Contrast); add `HotkeyFormatter.spoken(_:)` in the one hotkey formatter (Phase 5.8 of the previous plan) returning "Command Return"; Test `Tests/FoundryTests/CommandContractsTests.swift` for the spoken formatter, `PanelKeyboardTests.swift` for the announcement (inject an announcer spy).

**Step 1: Write the failing tests** `testSelectionChangeAnnounces`, `testSpokenHotkeyNames`. **Step 2: Run** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** Expected: PASS. Manual: VoiceOver on, arrow through five results, hear each.

### Task 2.10: The pointer is a Mac pointer

Findings: panel.md 8 P1 ×4. `pointerCursor()` hand on every control (`FoundryControls.swift:159-166`); hover not gated on `foundryHoverHighlightsArmed` for `FavoriteTile`, `CompactLayoutButton`, `FamilyTab`, `AgentWidgetRow`; padding outside `Button` so only glyphs are clickable (`PanelPromptOverlay.swift:65-96`, `FeatureSurface.swift:267-274`, `FoundryControls.swift:263-270`); "View all" ≈ 14 pt tall (`WindowLayoutPicker.swift:22-33`).

**Files:** those sites. Test: a UI-geometry test is not meaningful; the check is a capture with the cursor over each target plus the lint rule `pointerCursor\(` allowance 0 except link-style controls.

**Step 1: Set the ratchet** `pointerCursor(` to 2 (the "View all" link and the agent ↗). Run lint. Expected: FAIL. **Step 2: Implement** `.pointerStyle(.link)` on those two, remove elsewhere; move padding into labels with `.contentShape(.rect)`; 24 pt minimum on "View all". **Step 3: Run lint** Expected: PASS. Capture: hover a row shows the arrow.

### Task 2.11: Copy pass on the panel

Findings: panel.md 10. "Utility" (`CommandPanelView.swift:879-880`) → "System"; browser kinds → "Tab", "Bookmark", "History"; "Click" keycaps (`:274, 312`) → real keys (after Task 4.2); casing per D6: "Loading Home" → "Loading home", "Search Files" → "Search files", "Take the Tour" → "Take the tour", "Window management"/"Window layouts" → "Window Layouts"; keycap spelling `↵ ⌘K esc ⇥ ⌫ ⇧⌘C`; "Open with X — Default" → "Open with X" plus a `caption` "Default" accessory; "Tone ·" → "Skin Tone"; status item "⌥Space Is Taken. Choose Another Shortcut…"; "Ranking reset" → "Ranking Reset".

**Files:** the sites named. Test `Tests/FoundryTests/LocalizationTests.swift` (every changed string present in `Localizable.xcstrings`), `scripts/lint-l10n.sh`.

**Step 1: Run** `scripts/lint-l10n.sh` after the edits. Expected: FAIL for any literal not routed through `LocalizedStringResource`. **Step 2: Fix.** **Step 3: Run** Expected: PASS.

### Task 2.12: The transient HUD has one timing

Finding: panel.md 1 P2. `TransientNoticeController.swift:19-31` vs `ActionFeedbackPresentation.swift:20-21`.

**Files:** both. Use `Motion.toastIn`, hold 1.6 s, `Motion.toastOut`. Test `PanelShellTests.swift` `testToastTimings` with an injected clock.

### Phase 2 gate

Full suite, lints, ratchet counts lower than Phase 1. Live captures of home, search, actions, no-results, in light and dark, Reduce Transparency, Increase Contrast, into `docs/qa/2026-11-01-last-20/phase2/`. A fresh-context critic (Opus 5.5, read-only, given only the PNGs and the bar in section 0) scores restraint, truth, and consistency out of 10 and names what to remove. Fix anything under 8 before moving on. Record the scores in `progress.md`.

---

## Phase 3 — Onboarding and first run: the masterpiece

Activation moment (onboarding.md A):

> The user presses ⌘Space over another app, types two or three letters of something of their own, presses Return, and sees it open faster than they could have done it themselves.

The flow is rebuilt backward from that event. Four screens (D2). The brand language stays: ink, chalk keycaps, Geist, one orange full stop. Everything the user rejected in rounds 4 and 5 stays rejected (progress.md): no molten cast, no cursor light, no confetti, no centred three-line stacks, no default prominent button.

### Task 3.1: Four steps, and a step model that can be tested

**Files:** Modify `Sources/Foundry/UI/Onboarding/OnboardingState.swift:10-18` (`enum OnboardingStep { welcome, shortcut, bringYourStuff, done }`), `OnboardingView.swift` (remove the preferences, permissions and ai bodies; keep their components where reused), `OnboardingSnapshotTests.swift`; Test `OnboardingStateTests.swift`.

**Step 1: Write the failing tests** `testFlowHasFourStepsAtMost`, `testBringYourStuffIsSkippedWhenNoRivalIsInstalled` (inject `LauncherRival.detected == []`, advance from shortcut, assert `.done`), `testBringYourStuffShowsWhenAlfredIsInstalled`.

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** The AI choice is made silently: Apple Intelligence if available, else a detected local model, else nothing; it is reported on Done (Task 3.5). Permissions become just-in-time cards (Task 3.7). The ⇧⌘V and menu-bar toggles move to Settings, where they already exist.

**Step 4: Run** Expected: PASS. Regenerate the onboarding snapshots; look at each.

### Task 3.2: Shortcut and Try become one screen whose job is a real launch

Findings: onboarding.md A, C1 (`OnboardingView.swift:224-226`), C2, C5. Today Try it succeeds when the panel closes. `ShellController.swift:309-311` already reports `resultExecuted` to `completeTryIt()`.

**Files:** Modify `Sources/Foundry/UI/Onboarding/OnboardingView.swift:160-272` (one screen: shortcut field "Shortcut ⌘ Space · Change", the chalk keyboard, the lead "Open \(appName) with it." where `appName` is a running app that is not Foundry, Finder or the frontmost app, else "Open Safari with it."); Modify `OnboardingState.swift:141-156` (`completeTryIt` now requires an executed result; the opened-then-closed path shows "Now try opening something: type sl and press Return."); Modify `CommandPanelState.searchHint` to carry that hint while the step is active; Test `OnboardingStateTests.swift`.

**Step 1: Write the failing tests** `testTryItCompletesOnlyWhenAResultRuns` (open and close the panel: not complete; `resultExecuted(id:)`: complete, and the diagnostics log carries the id), `testTryItLeadNamesARunningApp`.

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** The primary appears only after the launch works; before that the footer holds Back and "Skip" (quiet). Delete the "The same keys close it. So does Esc." line. The demo press plays once, not in a loop; a second pass only after 6 s idle.

**Step 4: Run** Expected: PASS.

### Task 3.3: Ask before touching other apps, and detect "pressed but nothing happened"

Findings: onboarding.md C1 (`:192, :209-211`), C5. The shortcut step quits Raycast or Alfred and disables Spotlight on appear (`OnboardingView.swift:171-173`).

**Files:** Modify `OnboardingView.swift:165-215`; Modify `OnboardingState.swift:171-230` (`claimCommandSpace` becomes two steps: `detectRivals()` and `moveRival(_:)` after consent; `useCommandSpace` polls the real registration, not its own write); Modify `Sources/Foundry/Shell/HotkeyController.swift` (expose a local `flagsChanged`+Space observation while the step is active: if ⌘ is held and Space reaches the local monitor, Carbon did not take the key); Test `OnboardingStateTests.swift`.

**Step 1: Write the failing tests** `testShortcutStepDoesNotMoveRivalsWithoutConsent`, `testMoveRivalAfterConsentRewritesHotkeyAndQuits`, `testUnclaimedChordOffersOptionSpace` (simulate the local-monitor signal, assert `offersAlternative == .optionSpace`).

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** Copy: "Raycast uses ⌘ Space. Move Raycast to ⌥ Space?" [Move Raycast] [Keep Raycast, use ⌥ Space for Foundry]. Carbon failure: "Another app has ⌘ Space." [Use ⌥ Space] [Record your own]. **Step 4: Run** Expected: PASS.

### Task 3.4: Bring your stuff (only when there is stuff)

Finding: onboarding.md E row 1. Alfred snippets are readable JSON in the preferences bundle `LauncherRival` already locates (`LauncherRival.swift:75-81`); Raycast snippets and quicklinks import already exists (`SnippetActions.swift:117`, `Quicklinks.swift:81`).

**Files:** Create `Sources/Foundry/UI/Onboarding/BringYourStuffStep.swift`; Create `Sources/Foundry/Features/Snippets/AlfredSnippetImporter.swift`; Modify `OnboardingState.swift` (import results: `importedSnippets`, `importedQuicklinks`, `importSource`); Test new `AlfredSnippetImporterTests.swift` with a fixture under `Tests/FoundryTests/Fixtures/alfred-snippets/`.

**Step 1: Write the failing tests** `testImportsAlfredSnippetsFromPreferencesBundle` (fixture with 3 snippets, 1 duplicate keyword; assert 3 imported, duplicate flagged), `testRaycastExportDropImportsSnippetsAndQuicklinks`.

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** Screen: headline "Bring your snippets." One row per source with a count ("12 snippets in Alfred") and one button "Import". Raycast: "Export snippets from Raycast, then drop the file here." with a drop target. Primary: "Continue" (after import it reads "Continue" still; the receipt is on Done). Skip is quiet.

**Step 4: Run** Expected: PASS. Snapshot the step with Alfred detected and with nothing detected (the step is absent).

### Task 3.5: Done is a personal receipt with one next action

Findings: onboarding.md C1 (`:418`), C6, C7, F4, F5. Today Done is a generic cheat sheet.

**Files:** Modify `OnboardingView.swift:410-470`; Modify `OnboardingState.swift` (a `Receipt` struct built from what actually happened: shortcut claimed, rival moved, imports, AI chosen, launch at login); Modify `AppDelegate.swift:115-130` (register the login item on finish when the row is on, D3); Test `OnboardingStateTests.swift`.

**Step 1: Write the failing tests** `testReceiptListsOnlyWhatHappened` (no rival, no import, Apple Intelligence available → exactly ["⌘ Space is yours", "Apple Intelligence answers Tab"]), `testFinishRegistersLoginItemWhenRowIsOn`, `testFinishDoesNotRegisterWhenRowIsOff`.

**Step 2: Run** Expected: FAIL. **Step 3: Implement.** Headline "⌘ Space is yours." Rows: the receipt lines in Geist 16, a "Starts when you log in" row with a switch on by default, and "Foundry lives in the menu bar" with a short line pointing up-right toward the status item (static, no animation; the item itself is visible above the window). Primary: "Open Foundry" with ↵. The panel opens with Task 3.6's first-open placeholder and the first suggestion preselected.

**Step 4: Run** Expected: PASS. Snapshot Done with a full receipt and with the minimum receipt.

### Task 3.6: The first panel after setup, and the first proof of value

Findings: onboarding.md C8, C9. `CommandPanelView.swift:470` stock placeholder; `resultExecuted` only feeds Try it.

**Files:** Modify `Sources/Foundry/UI/CommandPanelState+Lifecycle.swift` (`firstOpenAfterOnboarding` from local state; placeholder "Type an app, a file, or something you copied"; first navigable row preselected); Modify `Sources/Foundry/UI/CommandPanelState.swift` (after the first executed result ever, show one `.info` feedback line once: "That's it. ⌘ Space, a few letters, Return."); Test `CommandPanelStateTests.swift`.

**Step 1: Write the failing tests** `testFirstOpenAfterOnboardingUsesTaskPlaceholderOnce`, `testFirstEverRunShowsOneAcknowledgementOnce`. **Step 2: Run** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** Expected: PASS.

### Task 3.7: Just-in-time permission cards

Finding: onboarding.md B table, F7. First paste, snippet expansion, window tiling or OCR without permission fails after the attempt with a toast and no path to fix. The picked clipboard item may be lost (`DirectPasteService.swift:112`).

**Files:** Create `Sources/Foundry/UI/PermissionCard.swift` (an in-panel `PanelPrompt` variant: icon, one line naming the outcome, [Allow] [Not now]); Modify `Sources/Foundry/UI/CommandPanelState+Paste.swift`, `Sources/Foundry/Shell/SnippetExpansionService.swift:33`, `Sources/Foundry/Features/WindowManagement/WindowManager.swift`, `Sources/Foundry/Features/Images/ImageActions.swift:435` (preflight `CGPreflightScreenCaptureAccess()`); Modify `DirectPasteService.swift:105-125` so a failed paste leaves the pasteboard holding the chosen item; Test `DirectPasteServiceTests.swift`, `CommandPanelStateTests.swift`.

**Step 1: Write the failing tests** `testPasteWithoutAccessibilityShowsCardAndKeepsItemOnPasteboard`, `testOCRWithoutScreenRecordingShowsCardBeforeCapture`, `testAllowOpensExactlyOneSystemSurface`. **Step 2: Run** Expected: FAIL. **Step 3: Implement.** Copy: "Allow Accessibility to paste into \(appName)." / "Allow Screen Recording to read text from the screen." **Step 4: Run** Expected: PASS. Render the card.

### Task 3.8: Day two: earned tips, and a What's New that does something

Findings: onboarding.md C10, step table "What's New". `WhatsNew.swift:7-8` is a seven-item sentence; "Take the Tour" opens first-run.

**Files:** Create `Sources/Foundry/UI/Tips.swift` (`Tip` list, max five, one per day, dismissible, shown after `launchCount >= 5`; first tip: "⇧⌘V opens everything you've copied." with a `KeycapHint`); Modify `Sources/Foundry/UI/CommandPanelView.swift:68-75` (one slot above the list for either What's New or a tip, never both); Modify `WhatsNew.swift` (one feature, one action: "New: window layouts. Try ⌃⌥→" with a button that runs it); Test new `TipsTests.swift`, `CommandPanelStateTests.swift`.

**Step 1: Write the failing tests** `testTipShowsAfterFiveLaunchesOncePerDay`, `testDismissedTipNeverReturns`, `testWhatsNewActionRunsTheFeature`. **Step 2: Run** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** Expected: PASS.

### Task 3.9: Keyboard and VoiceOver parity, and a quieter cast

Findings: onboarding.md D. Toggles and choice rows need the mouse; step changes post no announcement; Done rows read as three stops; chalk tiles flash orange on landing (`CastMark.swift:107-109`); the recording dot uses `easeInOut` (`OnboardingView.swift:528-530`); "Skip setup" contrast unmeasured.

**Files:** Modify `OnboardingComponents.swift` (choice lists take ↑/↓ and Space; the shortcut field takes Return to record, Esc to cancel, ⌫ to clear), `OnboardingView.swift` (post an announcement on step change and on Try-it state change; Done rows `.accessibilityElement(children: .combine)`), `CastMark.swift:107-109` (chalk lands chalk; only the full stop carries orange), `:528-530` (`Brand.Motion.state`); Test `OnboardingSnapshotTests.swift` (add Try-it opened and success, recording, hotkey-failed, rival-consent, reduced motion renders; assert a mid-cast frame has orange only inside the full-stop tile's rect), `OnboardingStateTests.swift` for keyboard moves.

**Step 1: Write the failing tests.** **Step 2: Run** Expected: FAIL. **Step 3: Implement.** Measure "Skip setup" (`Brand.faint` on `Brand.ink`) with a contrast calculation in the test; if under 4.5:1, use `Brand.muted`. **Step 4: Run** Expected: PASS.

### Task 3.10: Launch-at-login and menu bar discoverability outside onboarding

Finding: onboarding.md C6, C7. After a restart without login item, ⌘Space does nothing and Spotlight's shortcut is already off.

**Files:** Modify `Sources/Foundry/Application/AppDelegate.swift` (if the login item is not enabled and onboarding completed, show one in-panel `.info` line on the second launch: "Foundry won't open after a restart. Turn on Start at login?" [Turn On]); Test `CommandPanelStateTests.swift`.

**Step 1–4** as above.

### Phase 3 gate

Full suite, lints. Snapshot every step and state in light (offscreen) and record the real window with the user's consent for a frame-by-frame look at the cast and the Try-it success. Fresh-account walk on a second user account: install, finish setup by keyboard only, time from first launch to the activation event (target under 45 s by the `onboarding.*` diagnostics timestamps). Blind critic (Opus 5.5) on the PNGs against Arc, Dia and Apple first run; fix anything it names under 8. Record in `progress.md`.

---

## Phase 4 — Feature surfaces: every mode to the same bar

The shared mechanics come first (4.1–4.4) because each surface task then becomes small.

### Task 4.1: ⌘K on every list

Finding: features.md Shared P0. `CommandPanelState+Input.swift:29` gates the action panel on `.search`.

**Files:** Modify `Sources/Foundry/UI/PanelFeature.swift` (`func actions(for selection: Any?) -> [CommandAction]`, default empty), `CommandPanelState+Input.swift:25-40`, `CommandPanelView.swift:270-320` (the `.actions` footer spec in every list mode with a non-empty action list); Test `PanelKeyboardTests.swift`.

**Step 1: Write the failing test** `testCommandKOpensActionsInClipboardMode` (clipboard with one text item: actions are Paste ↵, Copy ⌘↵, Paste as Plain Text ⌥↵, Open Link ⌘O, Extract Text ⌘E, Add to Shelf, Remove ⌫, Clear History… ⇧⌘⌫ last and destructive). **Step 2–4** as above.

### Task 4.2: Arrows and Return on every surface, no "Click" keycaps

Findings: features.md Shared P1 (`CommandPanelView.swift:274, 312, 291-292, 314`), Shelf P1, Developer Tools P1, Media P1, Agents, drop chooser P1.

**Files:** Modify `PanelFeature.swift` conformers for shelf (↵ open, space Quick Look, ⌘O reveal, ⌘A select all), developer tools (↵ copies the first output), media (↵ opens the file, ⌫ removes), agents (↵ opens or toasts "\(provider) doesn't support jumping to a session yet."), drop chooser (↑↓ selection, ↵ on the selected row, ⌘1–4 shown as keycaps); footers updated to the real keys; Test `PanelKeyboardTests.swift` one test per surface.

### Task 4.3: One copy-and-paste confirmation rule

Finding: features.md "ten changes" 4. Every copy or paste shows "Copied …" / "Pasted …" through the transient HUD when the panel dismisses, or the in-panel line when it stays.

**Files:** Modify `PanelFeature.swift:189-192`, `CommandPanelView.swift:334, 346-349` (emoji and clipboard Return), `DeveloperToolsState.swift:142`, `TranslatorView.swift:207-217`, `MediaDownloadsView.swift:586`, `SnippetState.swift:180-207` (import and export results: "Imported 12 snippets · 3 already in your library", "No new snippets in that file", "Exported 40 snippets to foundry-snippets.json"); Test per state file.

### Task 4.4: Esc peels one layer everywhere

Findings: features.md Shared P1 (`PanelRouter.swift:215`), Snippets P1 (`pendingSnippetArguments` not checked at `:192`).

**Files:** Modify `Sources/Foundry/UI/PanelRouter.swift:185-225`; Test `PanelKeyboardTests.swift` `testEscapeClosesSnippetArgumentPromptFirst`, `testEscapeClearsQuickAIComposerBeforeLeaving`.

### Task 4.5: Clipboard

Findings: features.md Clipboard P1 ×6, P2 ×3.

**Files:** Modify `Sources/Foundry/UI/ClipboardHistoryView.swift:32-61, 73-74, 127-131, 178, 190-192, 257-281, 348`.

Changes: the bordered Pause button becomes `FoundryActionButton` with a `pause.fill` glyph, and a paused state shows `InlineNotice(.warning, "Capture paused. New copies aren't saved.", actionTitle: "Resume")`; the in-body title row goes (count moves to the footer status slot, Clear moves to ⌘K); the row hover action reads "Paste" for every kind and "Paste as Plain Text" (⌥↵) only for text; the preview header keeps Copy and Paste, the rest live in ⌘K; the clear prompt reads "Clear all \(n) items, including \(p) pinned? This can't be undone." [Clear All]; the filtered-empty copy reads "Nothing matches “\(query)”" / "Search covers text, file names and source apps. Press esc to clear."; rows adopt the root anatomy (40 pt, `Spacing.sm`, `Radius.row`, `body`, 26 pt icon); the segmented filter becomes chips with counts ("Images 4"); keyboard `scrollTo` without animation.

Tests: `ClipboardHistoryTests.swift` for the copy and the paused notice; `PreviewSnapshotTests.swift` references regenerated and inspected.

### Task 4.6: Snippets

Findings: features.md Snippets P1 ×5, P2 ×5.

**Files:** `SnippetsView.swift:30, 131, 141, 164, 182-207, 243, 277-285, 292, 325, 482, 523, 575, 621, 631-681`; `PanelFeature.swift:102-120`.

Changes: duplicate-keyword notice becomes `.warning`: "“\(kw)” is used by \(n) snippets. Rename one to turn expansion back on."; the static secure-field line and the in-panel Auto-expand switch go, replaced by one warning only when expansion is off or Accessibility is missing: "Keywords won't expand. Allow Accessibility in Settings › Snippets."; ⌘N new (focus to title), ⌘⌫ delete (existing confirm), ⌘D duplicate; the argument prompt renders in `FoundryGlassSurface(.floatingOverlay)`; row subtitle is the first content line with the keyword in a trailing mono badge, use count and date move to the editor footer; headers through `FoundrySectionHeader`; editor font 13 regular (`bodySecondary`) or `mono` behind the same toggle Clipboard uses; `RelativeDateTimeFormatter(.abbreviated)`; radii and the hover fill to tokens; D6 casing ("Clear Filters", "Insert Placeholder").

Tests: `PanelKeyboardTests.swift` for ⌘N/⌘⌫/⌘D; snapshot of the editor and the argument prompt.

### Task 4.7: Quick AI

Findings: features.md Quick AI P1 ×4, P2 ×3 (P0s done in 1.6).

**Files:** `QuickAIState.swift:59-72`, `QuickAIView.swift:88, 135-140, 232-240, 371, 408-410, 426-453, 466-470`, `PanelRouter.swift:187`.

Changes: no empty thread persisted until the first message; model menu does not change the global default; empty Return is a no-op and Send dims while the composer is empty; `QuickAIActivityLabel` with `ProgressView().controlSize(.mini)`; a keyboard thread list (↑↓, ↵ opens, ⌘⌫ deletes, relative date trailing); composer 20 pt with the placeholder at `textContainerInset` + `lineFragmentPadding` in `placeholderTextColor`; "AI Settings…" in both places; the empty state drops the title and keeps three suggestions with the shortcuts in the footer only.

Tests: `AIChatStoreTests.swift` `testOpeningQuickAIDoesNotCreateEmptyThreads`, `testModelMenuDoesNotChangeDefaultProfile`.

### Task 4.8: File Shelf and drag-and-drop

Findings: features.md Shelf P1 ×3, P2 ×2; drop P1 ×3, P2 ×2.

**Files:** `FileShelfView.swift:27, 44-54, 68-72, 131, 152, 171, 183`; `CommandPanelState+Drop.swift:58-66, 83-108`; `CommandPanelView+Surfaces.swift:28-53`; `CommandPanelView.swift:628`.

Changes: "BEN2" leaves the chrome (menu items "Remove Background", "Remove Background (Detailed)" with a "One-time model download" note; "Remove model data…" moves to Settings with a confirm "Delete the background-removal model? You can download it again later."); Clear Shelf moves to ⌘K as "Clear Shelf…" ⇧⌘⌫; headers "3 Files" / "2 of 3 Selected"; fallback copy "This image couldn't be read. Try a PNG or JPEG."; dropping onto the shelf surface shelves directly; the drop chooser has a selected row; "Couldn't add those files" names the reason ("Folders can't go on the shelf. Drop the files inside."); OCR on N images runs sequentially into one text file; the overlay reads "Drop to shelve, convert or compress".

Tests: `FileConversionTests.swift` or new `FileShelfStateTests.swift` for the drop routing and the error reasons.

### Task 4.9: File Conversion

Findings: features.md Conversion P1 ×4, P2 ×4.

**Files:** `FileConversionView+Actions.swift:56-68, 191, 214-251, 377-384`; `FileConversionView.swift:84, 89, 105, 467, 507`; `FileConversionState.swift:199, 249`.

Changes: `.defaultAction` only when idle; cancel on ⌘. with "Cancel ⌘." in the footer; `status` carries a level rendered through `InlineNotice`; drop target uses `selectionBorder` + `fillSelected`, progress tint `accent`; name chips render real output names from the first source ("photo-converted", "photo-2026-11-01"); "Longest Edge: Original / 4096 / 2048 / 1024 / 512 px"; result-row buttons 24 pt; Convert button through `FoundryGlassSurface(role: .prominentControl)` at `Radius.control`.

Tests: `FileConversionTests.swift` `testSecondReturnWhileConvertingDoesNotCancel`, `testStatusCarriesLevel`.

### Task 4.10: Media Downloads

Findings: features.md Media P1 ×4, P2 ×4; D7.

**Files:** `MediaDownloadsView.swift:100, 136, 148-283, 187, 196, 315, 329-335, 346, 359, 371, 508, 572, 586`.

Changes: the link composer moves into the panel header slot; folder and "Change" move to ⌘K; "Supported links" moves to the empty state; selection uses `RowBackground`, keyboard-first; favicons follow the Site icons setting (D7); the completion card goes through `showActionFeedback` ("Saved ‘\(title)’ · Open ↵"); skipped-links copy "\(n) links aren't supported and were left in the box."; token radii; D6 casing.

Tests: `MediaDownloadTests.swift` for the favicon policy and the skipped-links message; `MediaNetworkPolicyTests.swift` asserts no request to `icons.duckduckgo.com` when the switch is off.

### Task 4.11: Translator

Findings: features.md Translator P1 ×4, P2 ×3.

**Files:** `TranslatorState.swift:32, 38-39, 107`; `TranslatorView.swift:54-58, 63, 207-217, 255`; `CommandPanelView.swift:308`.

Changes: persist the language pair; `isTranslating` after the debounce with a reserved status-row height; "Try Apple Intelligence" only for backend errors, and for unavailable languages "Download \(language) in System Settings › General › Language & Region › Translation Languages."; "Replace ⌘↵" everywhere with help "Replace the selection in \(appName)"; source defaults to Detect via `NLLanguageRecognizer`; the list from `LanguageAvailability().supportedLanguages`; pane radius 14.

Tests: new `TranslatorStateTests.swift` `testLanguagePairPersists`, `testLoadingStateWaitsForDebounce`.

### Task 4.12: Emoji

Findings: features.md Emoji P1 ×4, P2 ×3.

**Files:** `EmojiPickerView.swift:16-19, 29, 59, 92-107`; `EmojiPickerState.swift:64, 75-85`; `CommandPanelView.swift:280-286, 334`.

Changes: one flat navigable list with section-scoped ids; cells render the tone-applied emoji; Return pastes through `directPasteService` with copy fallback and a HUD; footer "Paste ↵ · Skin Tone ⌘T" with the selected emoji's name in the status slot; cells use `RowBackground` at `Radius.row`, no hover scale; `FoundryEmptyState` "No emoji for “\(query)”" / "Try a feeling or an object, like “happy” or “pizza”."; the columns control moves to Settings or is removed (12).

Tests: `EmojiPickerStateTests.swift` `testRecentAndAllHaveDistinctIDs`, `testArrowsReachRecents`, `testCellValueCarriesSkinTone`.

### Task 4.13: Developer Tools and Calculator

Findings: features.md Developer Tools P1 ×3, P2 ×4; Calculator P1, P2 ×3.

**Files:** `DeveloperToolsView.swift:38-77, 144, 186, 219, 393`; `CommandPanelView.swift:362`; `CalculatorViews.swift:10, 14, 86, 155-161`.

Changes: header "Developer Tools", chip shows the tool, section header removed; Base Conversion gets the same surface; `destructive` token; middle truncation with `.help(value)` instead of scaling to 7 pt; one chip row; even padding; calculator drops the dead gear, uses curly quotes, "=" for arithmetic and "→" for conversions, scale floor 0.6, shows the trimmed query instead of "Calculation".

Tests: `DeveloperToolsProviderTests.swift` and `CalculatorProviderTests.swift` for the separator rule and the copy.

### Task 4.14: Agents

Findings: features.md Agents P1 ×4, P2 ×2.

**Files:** `AgentShelfView.swift:8, 29-53, 85-86, 153, 238`; `AgentMonitorState.swift:311-320`.

Changes: the body title row goes; "2 active" in the footer status; a warning only when the socket is off ("Live updates are off. Open Settings › Agents."); tabs built from providers present; rows that cannot open stay enabled and explain on ↵; empty state "No agent sessions yet" / "Install a bridge in Settings › Agents to see Claude Code, Codex, Cursor and OpenCode here." with "Open Agent Settings"; Running merges into Working; the `recent` status label hides.

Tests: `AgentMonitorTests.swift` `testTabsFollowPresentProviders`, `testStatusVocabularyHasOneGreen`.

### Task 4.15: Settings window behaves like a Mac window

Findings: features.md Settings P1 ×8, P2 ×9 (P0s done in 1.10).

**Files:** `SettingsWindowController.swift:20-24`; `SettingsView.swift:9, 59-126, 405, 419, 443, 490, 513-597, 619-622, 819-851, 998`; `SettingsComponents.swift:28-31, 149-165, 157, 233-262, 287, 519`; `QuicklinksSettingsPane.swift:36-58`; `SettingsPaneRows.swift:245-262`.

Changes: `center()` only when `setFrameUsingName` fails; the last pane remembered; the rail becomes `List(selection:)` with `.listStyle(.sidebar)` in a `NavigationSplitView` (arrows, focus ring, type-select); text fields commit on blur; the shortcut recorder takes Space or Return to record, esc to cancel, ⌫ to clear, with a focus ring; widget reorder controls rest at 0.5 opacity; quicklink minus gets an Undo toast; one row component per quicklink; Appearance merges into General as "Panel contrast"; "Pop to root" → "Return to Home after" with help "Reopening sooner than this resumes where you left off."; "Rectangle-style" → "Suggested shortcut"; one 140 pt trailing control column; `SettingsGroup` radius 10 with a `separator` stroke; error indent 82; D6 casing on every button; delimiter and Return-key choices through native controls; retention picker 100 / 250 / 500 / 1,000 / 5,000; Settings › Agents tracked sessions removed.

Tests: `SettingsSearchTests.swift` still green; new `SettingsWindowTests.swift` `testWindowRestoresFrameAndPane`; snapshot of General, Clipboard, Quicklinks in light.

### Task 4.16: Camera is cut (D4)

**Files:** Delete `Sources/Foundry/UI/CameraPreviewView.swift`, `CameraPreviewState.swift`, `Features/Camera/`; remove the `.camera` mode and command; remove `NSCameraUsageDescription` from `scripts/build-app.sh`; Delete `Tests/FoundryTests/CameraPreviewTests.swift`. Update `README.md` and the release notes.

**Step 1: Run** `swift build` Expected: errors at every reference. **Step 2: Remove each.** **Step 3: Run** `swift build && swift test` Expected: clean.

### Phase 4 gate

Full suite, lints, ratchet counts lower than Phase 3. Offscreen renders of every surface in light; live captures of clipboard, snippets, Quick AI (idle, streaming, error), shelf, conversion, media, emoji, Settings. Blind critic on the set; fix anything under 8. Record in `progress.md`.

---

## Phase 5 — Cuts that make the product smaller and better

The audits named surfaces that are settings dressed as chrome or duplicates of other surfaces. Each removal is one commit with a test that the replacement path works.

| Cut | Where | Replacement | Done in |
|---|---|---|---|
| Camera mode | `UI/Camera*`, `Features/Camera` | none | 4.16 |
| Settings › Appearance pane | `SettingsView.swift:619-622` | "Panel contrast" in General | 4.15 |
| Settings › Agents tracked sessions | `SettingsView.swift:819-851` | the Agent Shelf | 4.15 |
| In-panel snippet Auto-expand switch | `SnippetsView.swift:192-207` | Settings › Snippets | 4.6 |
| BEN2 controls in the Shelf header | `FileShelfView.swift:44-54` | engine menu + Settings | 4.8 |
| Clipboard in-body title row and Clear button | `ClipboardHistoryView.swift:32-48` | footer count + ⌘K | 4.5 |
| Media second header (folder row, capabilities menu) | `MediaDownloadsView.swift:148-283` | header composer + ⌘K + empty state | 4.10 |
| `EmptyState` (duplicate component) | `FeatureSurface.swift:187-231` | `FoundryEmptyState` | 2.7 |
| `HomeResultRow` (duplicate row) | `PanelRowViews.swift:69-99` | `ResultRow` | 2.3 |
| Emoji columns control | `EmojiPickerView.swift:29` | fixed 12 | 4.12 |
| Dead transitions and the drop pulse | `CommandPanelView.swift:81, 105-121, 494, 529, 636-640` | none | 2.1 |

Task 5.1: after Phase 4, run `ponytail` over `Sources/Foundry/UI` for anything else that only exists to support a removed surface. Delete it. `swift build` clean, `swift test` green.

---

## Phase 6 — One vocabulary, proven by lint

### Task 6.1: Radius, control height and spacing scales

Findings: panel.md 11 P1 ×2, P2; features.md Shared P2 ×2.

**Files:** `FoundryTheme.swift` (`Radius.popover = 18`; `Control.mini 24, compact 30, field 36, row 40, rowTall 48`; `Panel.headerHeight 60, footerHeight 38`; `Overlay.width 340, Overlay.shadow`); every site listed in panel.md 11 and features.md Shared P2.

Mapping: radii 9 and 7 → 8; 5 and 4 → 6; 11/12/13 → 10; 15/16/18/20 → 14 or `popover`; literal 14 → `Radius.overlay`. Heights 26/28 → 24 or 30; 32/34 → 30 or 36; 42/46 → 40. Spacing 6 → 8, 10 → 12, 14 → 16, 18/20/22 → 24 except named optical cases, which get a named token.

**Step 1: Set the ratchet** for `cornerRadius: [0-9]` and `frame(height: [0-9]` to 0. Run lint. Expected: FAIL with the full list. **Step 2: Replace.** **Step 3: Run** Expected: PASS. Regenerate and inspect every snapshot reference.

### Task 6.2: Colours and type collapse

Findings: panel.md 11 P2 ×3.

**Files:** `FoundryTheme.swift:102-135, 286-290, 60-98`; sites of `sectionHeader`, `fillEmphasis`, `rowTitle`, `Strip` sizes under 10.

Changes: `sectionHeader` → `textSecondary`; `selectionBorder` and `fillEmphasis` → one 0.15; agent `.working` → `success`, `.reviewReady`/`.completed` → `accent`; `rowTitle` 13.5 → `body` 13; strip floor at 10 with semibold labels at 11; `Glyph.xs` never used as a text style. Lint: `Color\.(red|green…)` and `FoundryTheme\.(dark|light|primary)\(` allowances to 0.

### Task 6.3: Delete the ratchet

**Files:** Delete `scripts/lint-design-ratchet.txt`; `scripts/lint-design.sh` fails on any violation. `.github/workflows/test.yml` already runs the lints.

**Step 1: Run** `scripts/lint-design.sh` Expected: PASS with no allowances.

---

## Phase 7 — The gauntlet: a fresh pass finds nothing

This is the perfection loop. It repeats until a full pass finds nothing above P2, and P2s are either fixed or written down with a reason.

### Task 7.1: Measure what must not regress

Repeat Task 0.3's measurements into `docs/benchmarks/2026-11-01-last-20-after.md`:

| Metric | Before (Task 0.3) | Bar |
|---|---|---|
| `panel.show` p95 | recorded | not higher |
| `search.immediate` p95 | recorded (12.11 ms at last measure) | ≤ 16 ms |
| Hotkey → first frame with rows | recorded | ≤ 50 ms, and frame 1 has rows |
| Idle CPU, panel open, static | recorded (≈7–8% last known) | ≤ 1.5% |
| Idle CPU, panel closed | 0.0% | 0.0% |
| RSS after 1,000 clipboard items | +1.34 MB | not higher |
| Test count | recorded | higher |
| Lint violations | ratchet counts | 0 |

The open-panel idle number needs the panel on screen for 20 s. If the `HomeAccessoryStrip.swift:209` 10 s pasteboard poll is the cause (panel.md 7 inventory), change it to read on open and on `changeCount` only, under a test.

### Task 7.2: Walk the product as four users

On a clean user account with the signed build, by hand, recording each walk:

1. **Keyboard only.** Install, onboard, launch three apps, paste from history, expand a snippet, tile a window, convert a file, ask AI, change a setting. Every step reachable; every footer true.
2. **VoiceOver on.** The same walk. Every row, state change and step announced.
3. **Reduce Motion + Reduce Transparency + Increase Contrast on.** Capture every surface. Nothing invisible, nothing muddy, nothing moving.
4. **Mouse only, trackpad, 1× external display, light mode.** Hover states, targets, cursor, panel position (`visibleFrame.height / 7`).

Each defect found becomes a task appended to this plan under "Phase 7 findings", with a test or a snapshot.

### Task 7.3: Blind critics

Three fresh-context critics (Opus 5.5, read-only, PNGs and recordings only, the bar from section 0, and the reference set: Raycast, Linear, Things 3, Arc, Dia). Each scores Restraint, Truth, Consistency, Craft out of 10 and lists what to remove before what to add. Fix everything under 9. Run again. Stop when a round names nothing new.

### Task 7.4: Ship

Bump `VERSION` to 1.3.0 (note: pushing `VERSION` triggers `.github/workflows/release.yml`). Write `docs/release-notes/1.3.0.md` in the `prose` register: what changed for the person using it, not the file list. Update `README.md` feature list for the cuts. Update `docs/HANDOFF.md` to point at this plan. `progress.md` carries the perfection report: the 80% version, the last 20% item by item with evidence paths, and what is still imperfect with why.

---

## Appendix A — Task index with suites

| Task | Suite to run | Evidence |
|---|---|---|
| 0.1–0.4 | full | counts in progress.md, before captures, ratchet seeded |
| 1.1, 1.2 | OnboardingStateTests | red→green, manual quit/relaunch |
| 1.3, 1.4, 1.6, 1.7 | CommandPanelStateTests, ClipboardHistoryTests, QuickAIStateTests | red→green, error render PNG |
| 1.5 | SnippetStateTests | red→green |
| 1.8, 2.8, 4.1, 4.2, 4.4 | PanelKeyboardTests | red→green |
| 1.9, 2.3, 2.6, 2.7 | PreviewSnapshotTests | reference diff inspected |
| 1.10, 4.15 | SettingsActionsTests, SettingsWindowTests | red→green |
| 1.11, 4.16 | ResourcePackagingTests | red→green, clean-account check |
| 2.1, 2.10, 6.x | lint-design.sh | red→green |
| 2.2, 2.12 | PanelShellTests | red→green, frame-1 PNG |
| 2.9 | CommandContractsTests, PanelKeyboardTests | red→green, VoiceOver walk |
| 2.11 | LocalizationTests, lint-l10n.sh | green |
| 3.x | OnboardingStateTests, OnboardingSnapshotTests, AlfredSnippetImporterTests, TipsTests | red→green, step PNGs, fresh-account timing |
| 4.5–4.14 | the surface's suite | red→green, surface PNGs |
| 7.x | full | benchmarks, walks, critic scores |

## Appendix B — What this plan deliberately does not do

- No new feature surfaces, no extension runtime, no calendar, no sync, no account.
- No distribution work (notarization, Sparkle, Homebrew) beyond the 1.3.0 version bump; still out of scope per `docs/HANDOFF.md`.
- No website (`anvil/`), ad (`foundry-ad/`) or film (`launch-film/`) changes.
- No conversion of Developer Tools or Translator into inline results (D5). If the user wants it, it is a separate plan.
