# Foundry first-run audit

Read-only audit of the source. Nothing was built, run or edited. Claims about runtime behaviour come from reading the code; the ones that need a live check say so.

## Fix before anything else

**If the user quits mid-flow, onboarding never comes back.**

- `CommandPanelState.swift:159`: on a fresh install, `markWhatsNewSeen()` writes the config file as soon as the panel state exists.
- `OnboardingState.swift:117`: every step change writes `onboardingStep` into that file.
- `OnboardingState.swift:97-99`: onboarding only shows automatically when `configExistedAtLaunch == false`.
- Result: quit, crash, or close the window with the red button (`OnboardingWindowController.swift:38`, `windowWillClose` at :65 does not finish) at any step, and the next launch shows nothing. The saved step (`OnboardingState.swift:90`) is dead in practice. The only way back is the menu bar's "Welcome Guide", which restarts at Welcome.
- `OnboardingStateTests.swift:19` asserts the buggy gate (`configExistedAtLaunch: true` → false). `testStepPersistsAndResumes` (:24) tests the store, not the gate, so the combination is never covered.
- Fix: show when `onboardingCompletedVersion == nil && (configExistedAtLaunch == false || onboardingStep != nil)`. Acceptance check: quit on Try it, relaunch, and onboarding opens on Try it.

---

## A. The activation moment

> **The user presses ⌘ Space over another app, types two or three letters of something of their own (an app they use, a file, the thing they just copied), presses Return, and sees it open or paste faster than they would have done it themselves.**

The current flow does not reach it.

- Try it (`OnboardingView.swift:220-251`) teaches open and close. Its success state is the panel *closing* (`:95-101`), with the headline "That's the whole idea." The user proves the key works, not that Foundry is useful.
- The code already counts running a command as success (`ShellController.swift:309-311` → `completeTryIt()`), but the copy steers the user to close the panel instead.
- The first chance to activate is after Done: "Open Foundry" opens the panel (`ShellController.swift:93`) with no task and a mostly generic Home (see C9). Skip setup, Esc and the close button don't open the panel at all, so those users get no first panel.

## B. Step table

| Step | User job | Effort requested | Value received | Verdict |
|---|---|---|---|---|
| welcome | Know what this is | One Return, after a ~1.25 s beat | Brand moment, one-line promise | **Keep.** Shorter beat; the CTA should name the next thing |
| shortcut | Own ⌘ Space | None by default. Foundry quits Raycast/Alfred and disables Spotlight **on appear, without asking** (`OnboardingView.swift:171-173`) | Conflicts cleared | **Combine** with tryIt into one screen, and ask before touching other apps |
| tryIt | Prove the key | Press the chord twice | Muscle memory for open/close | **Combine** with shortcut. Change the job to a real launch (see A) |
| preferences | Set 4 toggles | Read 4 rows | Low today. The defaults are already right except launch at login | **Remove** as a step. Launch at login moves to Done. ⇧⌘V is offered on first clipboard use |
| permissions | Grant Accessibility | One "Allow…" that opens two system surfaces at once (see below). The second row has no action | Nothing visible until the user pastes, expands or tiles | **Defer** to just-in-time cards |
| ai | Pick a provider | Read 4 rows, then Return | Only matters on the first Tab | **Defer.** Apply the recommended choice silently and show it on Done. Ask on first Tab when nothing is available |
| done | Know what to do next | Return | A generic cheat sheet, then the panel | **Keep**, as a personal receipt plus one next action |
| What's New | Upgraders learn 1.2 | Read a 7-item sentence (`WhatsNew.swift:7-8`) inline on Home (`CommandPanelView.swift:68-75`) | A list, with no way to try anything | **Rewrite.** "Take the Tour" opens the first-run flow (`CommandPanelState.swift:165`), not a 1.2 tour. Point at one feature with a working action |

**macOS permission prompts after onboarding**

| Prompt | Triggered at | Explained before macOS asks? |
|---|---|---|
| Accessibility (onboarding) | `PermissionHealthState.swift:84-90`: `AXIsProcessTrustedWithOptions(prompt: true)` returns false on first ask, so the code **also** opens System Settings immediately. That is two dialogs at once | Yes, by the row text "Paste into apps, expand snippets, and arrange windows." |
| Accessibility (paste) | `DirectPasteService.swift:121` throws → `SettingsStore.swift:376-378` → a toast saying "Couldn't paste: Accessibility access is required." The toast is a 1.4 s, mouse-ignoring panel (`TransientNoticeController.swift:26,60`) with no action. The `defer` at `DirectPasteService.swift:112` likely restores the old clipboard, so the item the user picked is gone too (needs a live check) | **No.** The failure comes after the attempt, with no path to fix it |
| Accessibility (snippets) | `SnippetExpansionService.swift:33`, from Settings › Snippets | Partly. Settings says "Accessibility required" |
| Screen Recording (Extract Text / OCR) | `ImageActions.swift:435` runs `/usr/sbin/screencapture -i`. TCC charges it to Foundry. No preflight (`CGPreflightScreenCaptureAccess` is never called) | **No.** If denied, the capture likely holds only wallpaper and the action reports "no text" (needs a live check) |
| Camera | `CameraPreviewState.swift:52-53`. The purpose string is "Foundry uses the camera to show a live preview when you open Camera." (`scripts/build-app.sh:180`) | Only by the system string. The panel shows "Requesting camera access…" while macOS asks |
| Automation (Notes, tabs, System Events) | `osascript` in `AppleNotesProvider.swift:36,90`, `SystemCommandProvider.swift:95-237`, `AgentMonitorState.swift:212` | The onboarding row says "macOS asks the first time you use them." The generated Info.plist has **no `NSAppleEventsUsageDescription`**, so the system prompt likely has no reason line (needs a live check on a clean account) |
| Contacts | Not used anywhere in `Sources` | n/a |

## C. Findings

### C1. Copy (quote → rewrite)

| Where | Now | Rewrite |
|---|---|---|
| `OnboardingView.swift:506` | "Get started" | "Set up ⌘ Space" (names the next job) |
| `:144` | "Everything on your Mac, one keystroke away." | Keep. It is the right promise |
| `:192` | "⌘ Space is taken by another app. Record a different shortcut." | "Another app has ⌘ Space." plus a one-tap **Use ⌥ Space** and "Record your own" |
| `:209-211` (status shown while it happens) | "Moving Raycast to ⌥ Space" | Ask before acting: "Raycast uses ⌘ Space. Move Raycast to ⌥ Space?" [Move Raycast] |
| `:224` | "That's the whole idea." / "Open it from anywhere. Close it the same way." | Replace the task: "Open Slack with it." / "Press ⌘ Space, type sl, press Return." (use a running app's name) |
| `:226` | "The same keys close it. So does Esc." | Drop it. Closing needs no lesson; Esc is universal |
| `:279` | "Make it yours." / "Change any of these later in Settings." | Step removed. The lead was a disclaimer, not a benefit |
| `:322` | "Each one unlocks a few commands." | Name them in the just-in-time card: "Allow Accessibility to paste this into Notes." |
| `:370` | "Not available on this Mac yet." | "Needs Apple Intelligence turned on in System Settings." or "Not supported on this Mac." "Yet" promises something the app can't know |
| `:378` + `OnboardingState.swift:276-277` | "Cloud provider" / "Add an API key in Settings when you're ready." Choosing it does **nothing** (`case .later: break`) | "Decide later" / "Tab asks you to pick a model the first time." Or open Settings › AI with the key field focused |
| `:418` | "You're set." / "The keys worth remembering." | "⌘ Space is yours." / one line per real change: "Raycast moved to ⌥ Space. Apple Intelligence answers Tab." |
| `CommandPanelView.swift:589` | "Find apps, commands, emoji, system tools, and shelf actions." | "Find apps, files, and commands." ("Shelf actions" is internal jargon) |
| `StatusItemController.swift:47`, `OnboardingWindowController.swift:42`, `CommandPanelView.swift:71` | "Welcome Guide", "Welcome to Foundry", "Take the Tour" | One name, "Welcome to Foundry", for the window and the menu item. "Take the Tour" goes away with the What's New rewrite |

Smaller copy bugs:
- `OnboardingView.swift:468-476`: with ⇧⌘V already owned by another Foundry command, the "Clipboard shortcut" toggle silently stays off.
- `:386`: local-model detection runs once, on appear. Starting Ollama while on the step never enables the row.

### C2. One primary action per screen
- The footer holds one primary on every step (`:482-499`). Good.
- Try it has four exits on a screen whose job is one key press: Continue (outline), "Nothing happened? Choose another shortcut", Back, and Skip setup.
- Shortcut can show four controls at once: Shortcut field, "Use ⌘ Space instead", "Open Keyboard Shortcuts", Continue.
- Merged Shortcut + Try should keep the shortcut field and one fallback. The primary appears only after the launch works.

### C3. Back / skip / exit predictability
- **Esc ends setup from any step**: `.onExitCommand { state.finish() }` at `OnboardingView.swift:103`. Try it's own copy tells the user to press Esc, so a second Esc after the panel closes can end onboarding.
- **Skip setup, Esc and close all have side effects.** `finish()` claims ⌘ Space when it hasn't been claimed (`OnboardingState.swift:122`). That disables Spotlight's shortcut, restarts `cfprefsd` (`:54-59`) and quits Raycast/Alfred (`LauncherRival.swift:23`). It even does this from Welcome via Esc. Skipping should be inert.
- After a skip the user lands nowhere: the panel opens only when `step == .done` (`ShellController.swift:93`). Skip should open the panel once, with the shortcut shown in the placeholder.
- Back is bare ← (`:489`). That works, but no hint shows it, and the window closes without confirmation.

### C4. Relaunch mid-flow
Broken. See "Fix before anything else".

### C5. When ⌘ Space can't be claimed
- **Carbon failure**: `ShellController.swift:129-136` sets `launcherHotkeyFailed`. The shortcut step shows the warning (`:191-193`) and the menu bar shows "…is unavailable — Choose Another Shortcut…" (`StatusItemController.swift:31`). There is no one-tap ⌥ Space; the only remedy is recording a shortcut.
- **Spotlight**: `useCommandSpace` (`OnboardingState.swift:187-205`) polls `isEnabled`, but that reads back Foundry's own write. "Spotlight's ⌘ Space turned off" therefore shows almost at once, whether or not SystemUIServer let go. Only Try it actually tests the key. progress.md confirms the takeover was never tested live.
- **Rival failure** (`:211`) says to change the hotkey in the rival's settings but gives no button.
- **On Try it**: the demo loops forever (`:254-272`). "Nothing happened?" appears after 0.6 s and sends the user back. The flow never detects "pressed but nothing happened" (for example via `flagsChanged` showing ⌘ held plus a Space keyDown reaching the local monitor, which means Carbon didn't take it). With that signal, Try it could offer ⌥ Space in place.

### C6. Launch at login
- Off by default. It is the first toggle on Preferences (`OnboardingView.swift:283-288`) and needs consent (`AppDelegate.swift:115-130`).
- For a launcher this is the biggest day-2 leak: after a restart, ⌘ Space does nothing, and Spotlight's shortcut is already off. The user ends up with no launcher at all.
- Recommendation: show it on Done as a row that is on by default ("Starts when you log in"). Register on finish if the row was left on. macOS shows its own login-item notice, so it isn't hidden.

### C7. Menu bar discoverability
- The app is `LSUIElement` (no Dock icon). The menu bar icon is on by default (`ConfigService.swift:18`).
- Onboarding never points at the icon. Turning the icon on or off in Preferences does change the real menu bar live (`ShellController.swift:253-255`). That is a free "every answer visibly changes the product" moment, and nothing points at it.
- Done should say where Foundry lives: "Foundry lives in the menu bar" with an arrow toward the icon.

### C8. The first panel after onboarding
- Home is half personal. Suggestions are running apps (`CommandModels.swift:141-145`, up to 5). Commands are the ranker's default top 5 with no usage behind them (`CommandRegistry.swift:177-210`).
- Nothing in the panel acknowledges that this is the first open: no hint, no reference to what was just set up. What's New is suppressed for fresh installs (`CommandPanelState.swift:159`). The placeholder is the stock "Search for apps and commands…" (`CommandPanelView.swift:470`).
- Proposal: on the first open after Done, the placeholder says "Type an app, a file, or something you copied" and the first suggestion is preselected.

### C9. The first proof of value (first command run)
- The only first-success moment in the app is file conversion (`FileConversionState.swift:489`, `conversionFirstSuccessCelebrated`).
- Outside onboarding, the first app launch, paste or calculation gets no acknowledgement. `resultExecuted()` only feeds Try it (`ShellController.swift:309-311`).
- No confetti, per the bar. A quiet one-time line under the search field after the first run is enough: "That's it. ⌘ Space, three letters, Return."

### C10. The day-2 surface
- Nothing teaches the second feature. Fresh installs never get What's New. There is no tip system, and the Done cheat sheet is seen once.
- The natural second feature is Clipboard History (⇧⌘V). It is already a surface of its own (Foundry's "Little Arc"), but its shortcut is opt-in, and onboarding shows it beside a warning that it collides with Chrome and Slack.
- Proposal: one earned tip line on Home. It shows after real usage (for example 5 launches), names one key, can be dismissed, appears at most once a day, and stops after five tips.

## D. Motion and accessibility

**Motion inventory.** Every token uses the curve (0.23, 1, 0.32, 1), from `FoundryTheme.swift:258-264`.

| Motion | Duration / easing | Purpose |
|---|---|---|
| Step change, crossfade plus 4 pt blur (`OnboardingView.swift:107-109`, `:79`) | 0.30 s `step` | Two steps read as one change |
| `Reveal` stagger (`OnboardingComponents.swift:257-273`) | 0.45 s `enter`, 6 pt rise, 50 ms stagger | Reading order |
| Welcome cast (`CastMark.swift:37-41,86-110`) | Tiles land in 0.45 s, cubic ease-out, bottom-up over 0.55 s plus 0.08 s jitter. The stop lands at 0.75 s. Total 1.45 s | Brand signature. **Each chalk tile flashes orange as it lands (`:107-109`).** That dilutes the full stop's orange, and it is the last trace of the rejected molten idea. Let chalk land chalk |
| Welcome headline and footer wait (`:32`, `:63`) | 0.8 s, then 0.45 s | Let the cast play alone |
| Try-it demo press (`:254-272`) | 1.4 s wait, 140 ms per key, 320 ms hold, 1.6 s rest, looping | Shows which keys |
| Key dip (`ChalkKeyboard.swift:203-209`) | 0.12 s press, 0.22 s release | Mirrors the real keyboard |
| Flash when the panel opens (`ChalkKeyboard.swift:104-111`) | 180 ms | Carbon eats the key, so this is the only echo |
| Hot keys and glow on success (`OnboardingView.swift:43-47`) | 0.45 s | Success |
| Auto-advance after success (`OnboardingState.swift:148`) | 1.2 s | Lets the success land |
| Primary press (`OnboardingComponents.swift:62-65`) | scale 0.97, 0.12 / 0.22 s | Press feedback |
| Recording dot (`OnboardingView.swift:528-530`) | 0.5 s `easeInOut` pulse | Recording state. It is the one curve off the token set |
| Panel entrance | Spring from 0.97 (`replayPresentation`, per progress.md) | Panel. It does not match onboarding's no-spring rule; the user chose it |

**Reduced motion.**
- The cast shows its final frame (`CastMark.swift:13-14`).
- `Reveal` drops the rise but keeps a 0.45 s fade with stagger.
- Steps crossfade without blur. The welcome beat is 0.
- The demo press is off (`:255`), and the static lit keys still teach the chord. The recording dot doesn't pulse.
- This path is sound. It has no snapshot coverage.

**Keyboard-only completion.**
- The Return-only path finishes: Welcome → Return; Shortcut → Return; Try → the chord twice (auto-advance); Preferences, Permissions, AI → Return; Done → Return.
- **Changing anything needs the mouse** unless Full Keyboard Access is on. Toggles, AI rows, "Allow…" and the shortcut field are plain or custom `ButtonStyle`s with no arrow-key model. The AI list can't be moved with ↑/↓. The shortcut field has no key equivalent.

**VoiceOver.**
- Good: headlines combine with the header trait (`OnboardingComponents.swift:31-32`); progress reads "Step n of 7" (`:251-252`); the mark and keyboard are hidden; the shortcut field has a label and hint (`OnboardingView.swift:599-600`); toggles have `accessibilityRepresentation`; AI rows carry `.isSelected`.
- Gaps:
  - A step change posts no announcement and doesn't move focus.
  - Try it's three states (`:223-229`) change silently. Success is visual plus haptic only.
  - Done rows read the label, then "command", then "space" as separate stops (`:445-456`). They need `.accessibilityElement(children: .combine)`.
  - The `.working` StatusLine spinner has no label.
  - Check the contrast of "Skip setup" in `Brand.faint` on ink against 4.5:1.

**Test coverage.**
- `OnboardingStateTests` covers the gate (with the bug encoded), step persistence, finish, telemetry, try-it scope, the Spotlight paths and the rival rewrites.
- `OnboardingSnapshotTests` renders the 7 base steps and asserts only that the top and bottom edges are brand ground.
- Not covered:
  - Try it's opened and success states, recording, the hotkey-failed, Spotlight-still-holds and rival-failed states, AI with a provider available, reduced motion.
  - The relaunch gate combined with a written config.
  - Esc or Skip side effects.

## E. What Arc and Dia do that this flow doesn't

| They do | Concretely | Fits a launcher? |
|---|---|---|
| **Import from the previous app** | Arc's first real screen imports bookmarks, logins and history from Chrome/Safari, so the sidebar is already yours. Dia does the same | **Yes, and it's mostly built.** Foundry already detects Raycast and Alfred (`LauncherRival.swift`) and already imports Raycast snippets (`SnippetActions.swift:117`) and quicklinks (`Quicklinks.swift:81`). Alfred snippets are readable JSON in the preferences bundle `LauncherRival` already finds (`:75-81`). Raycast needs its export file: "Export snippets from Raycast, then drop the file here." Show this step only when a rival is detected |
| **Every answer visibly changes the product** | Arc's colour pick repaints the window live | Partly. The menu bar toggle already changes the real menu bar live, so point at it. A theme picker would be bloat |
| **A signature moment** | Arc's launch animation; Dia's first "ask this page" | It's there: the real keyboard lighting while the panel lands over the window. Make it land on the user's own content (a running app), not an empty panel |
| **A personal end state** | Arc ends in your sidebar with your stuff; Dia ends on a real page with a suggested question | **Yes.** Done becomes a receipt: "⌘ Space is yours · Raycast on ⌥ Space · 12 snippets from Alfred · Apple Intelligence answers Tab", then "Open Foundry" with a preselected suggestion |
| **A second surface taught later** | Little Arc appears when you open a link from another app, and Arc names it then | **Yes.** Clipboard History is Foundry's Little Arc. Teach it the first time the user copies twice in a minute (one earned tip), not during setup |
| **Personality in copy** | Short, warm, first person | Foundry's copy is already exact and calm. Add warmth only on Done. No mascot |
| **Account, sync, membership card** | Arc's sign-in and card | **No.** Bloat for a local launcher |

## F. The ten changes that would most change how first run feels

Ranked. Fix the relaunch bug first regardless; it is a bug, not a feel change.

1. **Make Try it a real launch.** One screen holds the chord and the keyboard. Its job is "Open <a running app> with it". Success is `resultExecuted` on that result. *Check: Try it completes only when a real result runs, and the diagnostics log carries that result's id.*
2. **Cut to four screens**: Welcome → Shortcut and Try → Bring your stuff (only when a rival is detected) → Done. Preferences, Permissions and AI leave the flow. *Check: `OnboardingStep.allCases.count <= 4`, and a Return-only run takes under 45 s by the `onboarding.*` timestamps.*
3. **Ask before touching other apps, and make every exit inert.** The shortcut step names the rival and offers [Move Raycast]. Esc, Skip and close never call `claimCommandSpace`. *Check: with Raycast on ⌘ Space, Esc on Welcome leaves `raycastGlobalHotkey == "Command-49"`, Raycast still running, and Spotlight's entry 64 still on.*
4. **A personal Done receipt** that lists what actually changed, with one next action. *Check: after moving Raycast and accepting Apple Intelligence, Done shows "Raycast moved to ⌥ Space" and "Apple Intelligence", and shows nothing that didn't happen.*
5. **Launch at login on by default, shown on Done; point at the menu bar.** *Check: finishing without touching anything leaves `SMAppService.mainApp.status == .enabled`, and Done shows the row and the menu bar pointer.*
6. **Import from the previous launcher.** Alfred snippets in one click; Raycast by dropping its export file. *Check: with Alfred snippets on disk, one click imports N and Done says "N snippets from Alfred".*
7. **Just-in-time permission cards, and fix the double dialog.** The first paste, snippet, tile or OCR without permission shows an in-panel card with one Allow. The clipboard item survives. Allow raises the macOS prompt only, not System Settings as well. Add `NSAppleEventsUsageDescription`. *Check: with Accessibility off, pasting shows the card, the item is still on the clipboard, and exactly one system surface opens on Allow.*
8. **A first-open panel and a first-run acknowledgement.** The first panel after Done has a task placeholder and a preselected suggestion. The first successful run shows one quiet line, once. *Check: a fresh install's first open shows the new placeholder; the second open shows the stock one.*
9. **Earned day-2 tips, starting with ⇧⌘V.** One line on Home; at most one a day; dismissible; five in total. What's New points at one 1.2 feature with a working action, not the first-run flow. *Check: on day 2 after 5 launches, Home shows the ⇧⌘V tip once; once dismissed it never returns; "Take the Tour" no longer opens Welcome.*
10. **Keyboard and VoiceOver parity, and a quieter cast.** ↑/↓ moves any choice list and Space toggles a row. Step and Try-it changes post announcements. Done rows combine. Chalk tiles land without the orange flash. *Check: with Full Keyboard Access off, change the shortcut and a choice by keyboard alone; VoiceOver reads "Now press it again" when the panel opens; a mid-cast frame shows orange only on the full stop.*

---

Model: Claude Opus 5.5 (`claude-opus-5-5`).
