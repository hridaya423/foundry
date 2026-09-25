---
agent: devin-local
session: healthy-freesia
created: 2026-09-25T20:39:23Z
---
# Foundry Premium: polish, parity, onboarding, performance

Take Foundry (the macOS app, not the film or site) from a capable prototype to a premium launcher: a signed, auto-updating release; a polished first-run experience; a refined visual system; the launcher features people expect from Raycast and Tinycast; every existing feature brought up to that bar; measured performance gains; and a code and copy deslop, all delivered as gated phases of commits on main.

## 0. Decisions locked with the user

| Topic | Decision |
| --- | --- |
| Feature scope | **Core parity**: root file search, Quicklinks, Script Commands, Apple Shortcuts, a searchable ⌘K with per-action shortcuts, a preview pane, Settings search, backup and import. **Out of scope**: calendar, the notes editor, an extension runtime, dictation, OCR, color conversion. |
| Distribution | Developer ID signing, notarized DMG, **Sparkle** auto-update (the first external dependency), and a Homebrew cask. |
| Visual latitude | The earlier "preserve glass" direction no longer applies. Redesign where it is genuinely better. There is a design review gate before the design is rolled out everywhere. |
| Cuts | Collapse the 50+ "Open X Settings" commands into one System Settings provider. Audit other low-value surfaces and propose cuts for approval. |
| Onboarding | A dedicated guided window, built to a premium standard. |
| Default hotkey | ⌥Space for new installs. Onboarding offers ⌘Space and walks the user through freeing it from Spotlight. |
| Menu bar | A status item, on by default, that can be hidden in Settings. |
| Performance | Measure first, then set budgets about 20% better than the baseline, and gate every phase on them. |
| Settings | A separate, resizable, searchable Settings window. The panel becomes a pure launcher. |
| Clipboard storage | System SQLite (libsqlite3, no new dependency) for metadata, images as files, retention by days, count, and size. One-time migration from the JSON archive. |
| Delivery | Phased, passing commits on main. Each phase exits through a gate with screenshots and performance numbers. Bump VERSION to 1.1.0 at the end. |

## 1. Current state (evidence from research)

### Architecture
- Swift 6.2 SPM package, macOS 14+, with three targets: `Foundry`, `FoundryDomain`, and `FoundryServices`. The code has no external dependencies, about 39k LOC including tests, and 445 passing tests.
- The shell is `AppDelegate` → `ShellController` → `PanelController`, which hosts a borderless nonactivating `FoundryPanel` at a fixed 750×495. The panel hosts `CommandPanelView`, which is driven by `CommandPanelState`.
- `CommandPanelState` is a god object: about 1,091 LOC, 30+ `@Published` properties, and every feature state created eagerly. `CommandPanelView` is 1,282 LOC and uses 12-branch `if state.mode ==` chains for the header, content, footer, and contentID.
- Search runs through `CommandRegistry`, which has 14 providers, immediate and deferred tiers (80 ms and 250 ms), usage ranking, aliases, favorites, and per-command hotkeys. This part is solid.
- Settings is `UI/WidgetSettingsView.swift`: 1,426 LOC inside the panel, with a 148 pt rail and seven categories.
- Release (`.github/workflows/release.yml`): ad-hoc signature (`CODE_SIGN_IDENTITY: "-"`), zip only. It **deletes and recreates** the release for each version, and there is no notarization and no updater.

### Onboarding reality (confirmed in code)
1. First launch shows no window. `LSUIElement` is set, so there is no Dock icon, and there is no menu bar icon.
2. `AppDelegate.configureLoginItem` shows a modal NSAlert, "Launch Foundry at login?".
3. `FirefoxConnectorInstaller.configureMainBrowser()` then shows a second modal, "What is your main browser?". **Bug:** "Not Now" saves nothing, so this alert returns on every launch.
4. The default hotkey is ⌘Space, which Spotlight normally owns. If registration fails, the failure only reaches the log, so the user has no working way to open Foundry.
5. **Bug:** the migration in `FoundryConfig.init(from:)` rewrites a saved `.optionSpace` to `.commandSpace`.
6. No permission is explained before macOS asks for it. Clipboard capture is on by default, and nothing tells the user.

### UI observations (film captures in `foundry-film/captures`, stills in `foundry-film/assets/stills`)
- Home: one lonely half-width "Left" window-layout tile followed by a large gap. The row label "Application" repeats on every row. Suggestions can include junk such as "Bluetooth File Exchange". The storage widget shows "4.09 GB Storage" without saying whether that is free or used.
- Feature headers (Downloads and the others) are centered, while search is leading-aligned. This is the unfixed P13.
- Quick AI opens on a blank void with the placeholder "Ask follow-up…" on a new chat. It shows no model, has no suggestions, and has no per-message copy button.
- Selection highlight is neutral grey (`primary` at 10%). The accent color is unused.
- The panel has no shadow (`hasShadow=false`) and no open or close motion.
- The Settings button is a bare "…" glyph.
- Result rows have no shortcut or alias badges and no running-app indicator. Search results have no sections.
- The Actions panel (⌘K) cannot be searched, and actions have no keyboard shortcuts.
- The panel resets fully on every open (`resetForOpen`). There is no "pop to root after N seconds" behavior.
- Clipboard is a three-column card grid. Return copies and dismisses instead of pasting. The snippets footer says "Copy · Click" even though Insert exists.
- **Finder cannot be searched**: `AppSearchProvider` roots skip `/System/Library/CoreServices`.
- Release builds ship the developer-only "Rebuild Foundry App" command and describe "Quit Foundry" as "Stop the local prototype process".

### Performance baseline (docs/benchmarks, 2026-08-29, M4 Pro)
- Warm footprint is about 163 MB. Raycast v2 measures about 526 MB. Tinycast claims under 100 MB.
- Window registration is about 29 ms p50. This is a diagnostic only, not a first-frame measurement.
- The 2026-09-17 deep-scan remediation already fixed the per-keystroke waste, moved icons off the main thread, and removed dead code. The remaining structural cost is the god-state re-rendering the whole panel on every published change, plus eager feature-state construction.

### Competitor gaps (Tinycast README, Raycast v2 manual and changelog)
Foundry lacks the following, and all of them are in scope: root file search, Quicklinks with placeholders, custom or script commands, Apple Shortcuts, a searchable Action Panel, a compact window mode, Settings search, backup and import, a menu bar item, a signed Homebrew install, clipboard pinning and paste-as-plain-text, Finder in app search, "running apps" and "quit app" actions, a Rectangle-grade set of window actions (Tinycast has 34; Foundry has 21), and a real onboarding flow.

Foundry's differentiators are worth amplifying: the coding-agent monitor, local AI with provider fallback, media downloads, file conversion and background removal, developer tools, the translator, live widgets, and the memory footprint.

## 2. Guiding rules for every phase
- Load the skills `ponytail`, `code-deslop`, `clean-copy`, and `prose`. Add `design-engineering` and `emil-design-eng` for UI work, `onboarding-design` for Phase 3, `architect` for changes to ownership or contracts, and `test-driven-development` for behavior changes.
- Use no new dependencies except Sparkle. Stay with SwiftUI, AppKit, Foundation, Carbon, CoreServices, and libsqlite3.
- Every behavior change gets one regression test at the state or service boundary that fails on the old behavior. Do not write layout-presence tests.
- Every UI change gets before and after screenshots at the same size in Light, Dark, Reduce Transparency, and Reduce Motion. Keyboard-only and mouse paths must produce the same result.
- Honor Reduce Motion. Do not animate high-frequency changes such as keystrokes or selection moves beyond at most one 80 ms highlight.
- One passing commit per vertical slice. Stage exact files, never the dirty film or site worktree (`foundry-film/`, `foundry-launch/`, and `.devin/` are untracked and must stay out of commits).
- Verification commands: `swift test --filter <Suite>` per slice. `swift test`, `./scripts/build-app.sh`, `./scripts/verify-packaging.sh`, and `git diff --check` at each phase gate. Never run the release build at the same time as `swift test`.
- Evidence lives in `docs/qa/2026-09-25-premium/<phase>/`: screenshots, performance JSON, and a `coverage.md` row per surface.
- First execution step: copy this plan to `docs/plans/2026-09-25-foundry-premium-plan.md` and mark the 2026-08-23 roadmap and 2026-09-05 polish plan as superseded where they overlap.

## 3. Phases

The order is P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7. P6 (performance) and P7 (deslop) also apply continuously as budgets inside each phase. P1 can run in parallel with P2 once the user supplies credentials.

---

### P0 — Laboratory and baseline (no product changes)
**Goal:** tools that let us prove "smoother" and "faster" instead of asserting them.

1. **Signposts.** Add `os_signpost` intervals through the existing `DiagnosticsService` spans:
   - `panel.show`, running from the hotkey callback to the first `CATransaction` commit after `makeKeyAndOrderFront`, using `CATransaction.setCompletionBlock` or a `displayLink` first callback. This is the real first-frame proxy.
   - `search.immediate` and `search.complete`, running from keystroke to publish.
   - `mode.switch`.
   - `app.launch.ready`.
2. **Bench command.** Extend `scripts/benchmark-launchers.swift` with a `--foundry-only` mode that produces:
   - cold launch to ready,
   - warm open first frame p50 and p95 over 50 cycles,
   - keystroke to immediate and complete p95 over a scripted query list,
   - idle footprint,
   - footprint after opening and closing every surface three times,
   - idle wakeups per second (`top -stats pid,idlew` sample) with the panel hidden.
   Store the output as JSON in `docs/benchmarks/`.
3. **Visual rig.** Reuse `foundry-film/tools/drive.swift` and `record.swift` (ScreenCaptureKit, filtered by PID) to script a screenshot of every surface in every state, in both appearances. The output is `docs/qa/2026-09-25-premium/p0/*.png`.
4. **Coverage matrix.** Carry over the rows from `docs/qa/2026-09-05-product-polish/coverage.md` and add the new surfaces.
5. **Budgets.** Record the budgets in the plan copy as baseline × 0.8 for first frame, immediate search p95, idle footprint, and post-sweep footprint. Idle wakeups must be ≤ baseline. Any number that cannot improve 20% gets a written reason and an approved replacement.

**Exit:** baseline JSON and screenshots are committed, and the budgets table is filled in.

---

### P1 — Ship foundation: signing, notarization, Sparkle, menu bar, config fixes
**Lead-only prerequisites:** the user supplies the GitHub secrets `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID` or `NOTARY_API_KEY`, `TEAM_ID`, and `SPARKLE_ED_PRIVATE_KEY`. The user generates the Sparkle EdDSA key pair locally and keeps the private key. Execution stops and asks for these; it never fabricates them.

1. **Sparkle.** Add it with `swift package add-dependency` at a release at least 7 days old, pinned to an exact version. Package it through `scripts/build-app.sh`:
   - Copy `Sparkle.framework` into `Contents/Frameworks`.
   - Sign the framework's inner XPC services and the Autoupdate helper individually before signing the app, replacing `--deep`.
   - Add the Info.plist keys `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks`.
   - Keep the existing resource-bundle checks.
2. **Release workflow.**
   - Sign with Developer ID and run `notarytool submit --wait` and `stapler staple`.
   - Build a DMG with `hdiutil`: an Applications symlink and a background image.
   - Generate an EdDSA-signed `appcast.xml` with Sparkle's `generate_appcast` and publish it as a release asset or on GitHub Pages.
   - **Stop deleting and recreating releases.** Tags must be immutable per version and build.
   - Keep `swift test` and `verify-packaging.sh` as gates.
3. **Homebrew cask.** Create a `homebrew-foundry` tap repository with the cask. This is a separate repository, so it needs the user's consent to create.
4. **Update UI.** Add "Check for Updates…" in the menu bar and in Settings › About, with an automatic-check toggle.
5. **Menu bar status item** (`Shell/StatusItemController.swift`). A template-image Foundry glyph with a menu:
   - Open Foundry, showing the current hotkey
   - Clipboard History
   - Pause or Resume Clipboard
   - Settings… (⌘,)
   - Check for Updates…
   - Welcome Guide
   - Quit
   
   The setting `showMenuBarIcon` defaults to true. Clicking the item while the panel is open toggles the panel.
6. **Config fixes.** Add schema v7:
   - New installs default to `hotkey = .optionSpace`. Existing configs keep their saved hotkey.
   - Delete the rewrite of `.optionSpace` to `.commandSpace`.
   - Add `onboarding: OnboardingState { completedVersion: String?, steps: [String: Bool] }`, `showMenuBarIcon`, `popToRootAfter: Duration` (default 90 s), and `windowMode: .standard | .compact`.
   - Add a migration test for v6 to v7.
7. **Hotkey failure surfacing.** If the launcher hotkey fails to register at start, show a menu bar badge and a notice in Settings, and open onboarding's hotkey step. Do not fail silently.
8. **Remove launch-time modals.** Delete the login NSAlert from `AppDelegate` (onboarding replaces it). Move `FirefoxConnectorInstaller.configureMainBrowser()` into onboarding's optional browser step and Settings › Browser, and persist "Not Now". Fix the bug where the alert repeats on every launch.
9. **Release hygiene.** Compile "Rebuild Foundry App", `SourceRootLocator`, and the `defaults write foundry.sourceRoot` step only under `#if DEBUG`, or behind an env var for local builds. Change the "Quit Foundry" subtitle to "Quit Foundry and stop background features".

**Tests:** `ConfigServiceTests` (v7 migration, the ⌥Space default, and that a saved ⌥Space survives), `ResourcePackagingTests` (Sparkle framework present and signed, Info.plist keys), and a `StatusItem` menu-model unit test that checks items against state.

**Exit:**
- A notarized DMG from CI opens on a fresh macOS user account with no Gatekeeper prompt beyond the standard "downloaded from the internet" dialog.
- Sparkle updates build N to N+1 (test with a local appcast).
- The menu bar item works.
- Cold launch shows no modal alert.

---

### P2 — Design system and shell refresh (with a design gate)
**Goal:** one coherent visual language that every later phase builds on.

**Direction:** a native macOS 26 launcher. Keep Liquid Glass (`glassEffect`) on 26 and above, with a legacy visual effect and opaque fallbacks. Make it sharper and quieter: tighter type scale, accent-tinted selection, real depth, and motion that confirms rather than decorates.

#### 2a. Tokens (`UI/FoundryTheme.swift`, extended only with tokens that are used)

| Token | Values |
| --- | --- |
| Type | search 20 pt regular; row title 13.5 semibold-medium; secondary 12; meta 11 (tabular numbers where numeric); section header 11 semibold, uppercase, +0.4 tracking. |
| Spacing | 4, 8, 12, 16, 20, 24 |
| Radii | panel 20 (from 28; test 16, 20, and 24 at the gate); row 10; control 8 |
| Selection | `Color.accentColor` at 16% fill plus a 1 px at 28% border (this respects the user's System Settings accent). Hover is `primary` at 5%. Selected-row icon tile gets a 1.04 scale, no animation. |
| Depth | `panel.hasShadow = true` plus a custom 30 pt, 18% blur shadow layer. Add a 0.5 px inner highlight border on glass. |
| Motion | panel show is scale 0.97→1 with opacity 0→1 in 140 ms, `spring(response: 0.22, dampingFraction: 0.9)`; hide is 90 ms ease-in fade. Mode switches cross-fade in 120 ms. Nothing animates on keystroke or selection. Reduce Motion means opacity only. |

#### 2b. Shared components
- **`FeatureHeader`**: a fixed leading back button, an icon plus title (or search field) leading-aligned, and a trailing action slot. This replaces the 12-branch header chain and fixes P13.
- **`Footer`**: context primary action with its key on the left, secondary action (⌘↵), and "Actions ⌘K" on the right. Replace the "…" button with a small Foundry glyph menu for Settings, Welcome Guide, and Quit.
- **`ResultRow` v2:**
  - icon, title, and subtitle;
  - a trailing accessory stack with an alias badge, a hotkey badge, a running dot for apps, and a kind label shown **only** in mixed-type sections;
  - 44 pt rows (38 pt in compact mode).
- **Sectioned results**: Top Hit, then Applications, Commands, Files, Snippets and Quicklinks, Browser, Fallback. The section order comes from the ranker's top hit, never from a hard-coded order that could bury an exact match.
- **`EmptyState`** and **`InlineNotice`** (info, warning, error, with an action) as the only patterns for empty and error states.
- **Mode routing**: `CommandPanelView` switches over `Mode`, with one `FeatureSurface` view per mode. This deletes the parallel `contentID`, header, and footer chains, because each surface supplies its own header, footer, and content.

#### 2c. Panel behavior
- **Prewarm**: create the panel hidden at launch, so the first open does no view construction.
- **Pop to root**: `resetForOpen` only resets when the panel has been closed longer than `popToRootAfter`. Otherwise it restores the mode, query, and selection, as Raycast does.
- **Compact mode**: only the search bar shows until the user types, and the panel height animates to the content height. Resizing uses `setFrame(_:display:animate:)` with the top edge anchored. Add it as an option in Settings › Appearance.
- **Home redesign**:
  - Favorites row (pinned via ⌘K "Add to Favorites"): up to 8 icon tiles.
  - Recent: the top 5 by usage, with cold-start filtering so helper apps are not suggested before any usage exists. Maintain a small denylist of utility apps plus a rule that suggestions come from running and recently used apps via `NSWorkspace`.
  - Window layouts: either the four common layouts in one row, or hidden until used. Never a single tile.
  - The widget strip shows "free" or "used" explicitly.

#### 2d. Settings window
Create `Shell/SettingsWindowController.swift` and split the current `WidgetSettingsView.swift` into `UI/Settings/*.swift`, one file per pane, renaming it `SettingsView`.
- A standard `NSWindow` with a toolbar-style sidebar, 760×560 minimum, resizable. The window remembers its frame.
- **Search field** in the sidebar. It covers every pane and every command, and matches by setting title plus keywords, using a static index of `SettingItem(title, keywords, pane, anchorID)` and scrolling to the anchor.
- Panes:
  - General: hotkey, launch at login, menu bar, pop to root, compact mode.
  - Appearance
  - Commands: today's catalog, plus inline hotkey and alias editing.
  - Clipboard
  - Snippets: expansion, import, and export.
  - Quicklinks
  - Scripts
  - File Search: scopes and exclusions.
  - AI
  - Agents
  - Browser
  - Widgets
  - Permissions: a live health table with Grant and Open Settings buttons.
  - Advanced: config folder, reset, export and import.
  - About: version, updates, credits, NOTICE.
- ⌘, from the panel hides the panel and opens the window. The Settings mode is removed from the panel.

#### 2e. Design gate (a stop for user review)
Produce two variants (radius 16 vs 20, and accent-tint vs neutral selection) as screenshots of Home, search results, ⌘K, Clipboard, and Settings in Light and Dark. The user picks one, and only then does the design roll out to every surface.

**Tests:** `CommandPanelStateTests` covers:
- pop to root before and after the timeout (use an injected clock);
- compact-mode height state;
- sections keeping the top hit first;
- Home cold-start filtering.

**Exit:** the chosen variant is applied to the shell, Home, search, the Actions panel, and Settings. The screenshot matrix passes. First-frame and footprint budgets hold, with the shadow and glass cost measured.

---

### P3 — Premium onboarding
The approach follows the `onboarding-design` skill: reach first value within 30 seconds, and ask for each permission only at the moment it is needed.

Files: `UI/Onboarding/OnboardingWindowController.swift`, `OnboardingView.swift`, `OnboardingState.swift`, and `UI/PermissionHealthState.swift`.

#### Trigger
- Shown on first launch when `onboarding.completedVersion == nil` **and** no pre-existing config file exists.
- Existing users get no forced onboarding. Instead, a one-time "What's new in 1.1" sheet appears the first time they open the panel.
- Can be re-opened from the menu bar ("Welcome Guide") and from the `Welcome to Foundry` command.

#### Window
A 640×460 borderless titled window, centered, with glass background and the P2 tokens. It has a step indicator (dots), ←/→ and Return/Escape navigation, and every step can be skipped. Transitions between steps are a 200 ms horizontal slide with fade (fade only under Reduce Motion).

#### Steps
1. **Welcome.** The Foundry mark with a one-time subtle reveal. Headline: "Everything on your Mac, one keystroke away." Button: Get Started.
2. **Your shortcut.**
   - A large keycap rendering of ⌥Space and the ShortcutRecorder.
   - A "Use ⌘Space instead" button. It detects the Spotlight conflict by reading `com.apple.symbolichotkeys` key `64` enabled (read-only `UserDefaults(suiteName:)`, falling back to `defaults read`). If Spotlight holds the shortcut, show a 2-step inline guide and a button that opens System Settings › Keyboard › Keyboard Shortcuts › Spotlight via its `x-apple.systempreferences` URL. Poll every 1 s until the conflict clears, then register the shortcut and show a success tick.
   - Registration failure shows inline, never in the log only.
3. **Try it.** "Press ⌥Space now." The window listens for the panel `panel.show` event. The panel opens over onboarding with a coach mark ("Type an app name, press Return"). When the first command runs, onboarding advances with a checkmark. A "Skip" link is available.
4. **Make it yours.** Three toggles with one-line explanations:
   - Launch at login (`SMAppService.mainApp`, showing the real status).
   - Show in menu bar.
   - Clipboard history, with the privacy line "Stored only on this Mac. Password managers are always excluded." The default is on, and the user sees that choice.
5. **Superpowers (optional permissions).** Cards for:
   - Accessibility: paste into apps, snippet expansion, window layouts.
   - Automation: Notes and browsers, requested only when a card is enabled.
   - Files: search scopes.
   
   Each card shows the live status (polled from `AXIsProcessTrusted` and similar) and a Grant button. Nothing is requested unless the user clicks. "Later" is prominent.
6. **AI (optional).**
   - Detect Apple Intelligence availability (`SystemLanguageModel.default.availability`).
   - Detect a running Ollama or LM Studio instance on its localhost port.
   - Offer "Use Apple Intelligence", "Use local model", "Add API key later", or "Turn AI off".
7. **You're set.** A cheat sheet of five keys: ⌥Space, Tab (Ask AI), ⌘K (Actions), ⌘, (Settings), and ⇧⌘V (Clipboard, the suggested default command hotkey, offered as a toggle). Button: Open Foundry.

#### Persistence and health
- The state of each step persists, so quitting midway resumes at the same step.
- `completedVersion` is set on finish or skip.
- **Permission health**: `PermissionHealthState` is the single source for Accessibility, Automation per app, Camera, Full Disk Access (only if file search needs it), and notifications. It drives the onboarding cards, the Settings › Permissions pane, and any feature that needs a permission, so a feature shows "Needs Accessibility — Grant" inline instead of failing.

**Tests:**
- `OnboardingStateTests`: trigger rules (fresh install vs existing config), resume, skip, completion.
- The Spotlight conflict detector against fixture plists.
- A `PermissionHealth` mapping test.

**Exit:**
- A fresh macOS user account reaches a working launcher within 30 seconds without granting any permission.
- Each denied permission has a recovery path.
- A screen recording of the full flow in Light and Dark is in `docs/qa`.
- Cold launch shows no NSAlert.

---

### P4 — Launcher core parity
Each item is its own slice with its own tests.

1. **Action Panel v2.**
   - Add `shortcut: ActionShortcut?` to `CommandAction`. The standard map:
     - ↵ primary
     - ⌘↵ secondary
     - ⌘C copy
     - ⇧⌘C copy path or URL
     - ⌘⇧F reveal in Finder
     - ⌘Y Quick Look
     - ⌘D add to Favorites
     - ⌘E edit
     - ⌃X delete (with confirmation)
     - ⌘⇧, configure command
   - Shortcuts fire from the result list without opening ⌘K. Handle them in `FoundryPanel.handleShortcut`, routed through `CommandPanelState.performShortcut`.
   - ⌘K opens a floating actions popover anchored bottom-right, as in Raycast, with its **own filter field**. Typing filters actions, not the root query. Actions are grouped and each row shows its shortcut.
   - "Add to Favorites", "Set Hotkey…" (records inline), and "Add Alias…" become standard actions on every result.
   - Escape returns to the same query and selection.
2. **App search completeness.**
   - Add `/System/Library/CoreServices` (Finder, and the Screenshot helpers are already special-cased) plus `/System/Library/CoreServices/Applications` with an allowlist, so helper apps are excluded.
   - Show a running-app indicator using `NSWorkspace.runningApplications`, cached and updated on launch and terminate notifications.
   - App actions: Quit, Force Quit (with confirmation), Hide, Show in Finder, Copy Bundle ID, Show Info.
   - Add "Quit All Apps" and "Running Apps" commands.
3. **System Settings consolidation.** Replace the 50+ individual `settingsCommand` results with one `SystemSettingsProvider`. It keeps a static pane table with title, keywords, and URL, and returns pane results only when the query matches (for example "System Settings › Wi-Fi"). Empty and Home queries do not see them. The Commands catalog shows **one** "System Settings" entry, with pane enablement nested.
4. **Root file search.**
   - `Features/FileSearch/`: `NSMetadataQuery` with scopes from config (default: Home, excluding Library, `node_modules`, and `.git`) and cancellation per generation.
   - Uses the deferred tier: 3 or more characters, at most 4 results in root.
   - A dedicated "Search Files" command shows recent files (`kMDItemLastUsedDate`), filters (Kind: folder, image, document, code), a preview pane, Quick Look via `QLPreviewPanel` (⌘Y), and drag-out.
   - Actions: Open, Open With…, Reveal, Copy File, Copy Path, Add to File Shelf, Convert.
   - Spotlight-disabled volumes show a clear notice.
5. **Quicklinks** (`Features/Quicklinks/`, stored in `~/.config/foundry/quicklinks.json`).
   - Fields: name, URL, file or deeplink, optional `{argument}` placeholders plus `{clipboard}`, `{date}`, and `{selection}` (the last only with Accessibility), open-with app, and icon (favicon fetched once and cached, with opt-out).
   - Selecting a quicklink that takes an argument shows an **inline argument field** in the search bar, as in Raycast. Tab moves between arguments.
   - Create, edit, and delete in Settings plus a "Create Quicklink" command. Six seeded defaults (Google, GitHub, YouTube, Maps, Translate, and "Search in Finder"), each deletable.
   - Import from a Raycast Quicklinks JSON export.
6. **Script Commands** (`Features/Scripts/`).
   - Scan configured directories for executables using Raycast directives: `@raycast.title`, `mode` (silent, compact, fullOutput, inline), `argument1…3`, `icon`, `packageName`, and `refreshTime` (ignored in v1).
   - Execute through `ProcessRunner` with a timeout and an output cap.
   - Directories require trust: the first run prompts once per directory. Unknown directives are ignored with a warning.
   - Full-output mode opens an output surface. Compact mode shows a toast.
7. **Apple Shortcuts.** List the user's shortcuts with `shortcuts list` (cached and refreshed every 60 s in the background, never per keystroke) and run them with `shortcuts run <name>`, passing input from an argument or the clipboard. Aliases and hotkeys come from the existing preferences.
8. **Preview pane.** A shared `SplitResultsView` (list 42%, preview 58%) used by Clipboard, File Search, Snippets, and Quicklinks. The preview shows text with a monospace toggle, images (thumbnail, decoded off-main), files (Quick Look thumbnail through `QLThumbnailGenerator`), and a metadata footer (source app, date, size).
9. **Fallback commands.** When nothing matches, show a configurable list: Ask AI, Search Google (Quicklink), Search Files, and Define (off). This replaces today's single "Ask AI about …" row and is ordered in Settings.
10. **Backup and import.** "Export Foundry Settings…" writes a `.foundrybackup` zip containing the config (secrets excluded; Keychain stays), snippets, quicklinks, script directories list, and usage ranking. Import validates the schema and asks before overwriting. The existing Raycast snippets import stays.
11. **Window management depth.**
    - Add two-thirds (left and right), first, center, and last fourth, almost maximize, make smaller and larger (already present), maximize height, move to next and previous display, center half, and restore. The target is about 34 actions, to match Rectangle and Tinycast.
    - Add per-layout default hotkeys as opt-in suggestions (off by default).
    - Show the layout picker grid only with the "window" query or the dedicated command.

**Tests (add to existing suites):**
- `CommandPanelStateTests`: action filtering is independent of the query, and shortcut dispatch works.
- `AppSearchProviderTests`: Finder is found and helper apps are excluded.
- New `SystemSettingsProviderTests`: no results on an empty query, and pane matches.
- New `FileSearchTests`: scope enforcement, cancellation prevents publish, and ignore rules.
- New `QuicklinkTests`: placeholder expansion and encoding, and the argument model.
- New `ScriptCommandTests`: directive parsing, the trust gate, timeout, and output cap.
- New `ShortcutsProviderTests` with a stubbed CLI runner.
- `ConfigServiceTests`: backup round-trip.
- `WindowLayoutEngineTests`: the new placements.

**Exit:** the manual sweep passes:
- Find Finder, a file, a folder, a quicklink with an argument, a script, and a shortcut.
- Filter ⌘K and fire an action by its shortcut without opening ⌘K.
- Quick Look a file.
- Export, delete, and re-import settings.

Rapid typing must never publish stale results. Budgets hold, and root search p95 stays within budget with file search enabled.

---

### P5 — Existing-feature polish sweep
This covers every surface and folds in the leftover P03–P14 items from the 2026-09-05 plan. For each feature, the plan lists its current defects and the target behavior.

- **Clipboard** (includes the storage upgrade):
  - `ClipboardHistoryPersistence` moves to SQLite: a WAL database at `~/.local/share/foundry/clipboard.sqlite`, images as content-addressed files, and an FTS5 index on text.
  - The one-time idempotent migration keeps `clipboard.json` as `.migrated`. If migration fails, the previous archive stays intact.
  - Retention defaults to 3 months, 1,000 items, and 1 GB, all configurable. Pinned items are exempt.
  - UI moves from the card grid to `SplitResultsView`:
    - Return pastes into the previous app (the existing direct-paste flow).
    - ⌘↵ copies and ⇧↵ pastes as plain text.
    - ⌘P pins.
    - Type filter chips cycle with ⌘1–5: All, Text, Images, Files, Links.
    - Show the source app icon.
  - Pause status stays visible in every state.
  - Sensitive-content exclusion covers concealed types, password-manager bundles, and token-like strings.
- **Snippets**:
  - Return inserts and ⌘↵ copies.
  - Supported placeholders: `{cursor}`, `{clipboard}`, `{date:format}`, `{time}`, and `{argument name="…"}`, which prompts inline before insertion.
  - Duplicate keywords are flagged before save.
  - Unsaved edits are protected when switching or leaving.
  - Separate the "no snippets" state from the "no matches" state.
  - Export to JSON.
- **Quick AI**:
  - A new chat shows an empty state with the model chip (provider and model, click to switch), 3 contextual suggestions, and the placeholder "Ask anything…". "Ask follow-up…" appears only once a thread exists.
  - Per-message Copy.
  - A Stop button during streaming (⌘.).
  - ⌘N starts a new chat.
  - The thread list moves into a searchable ⌘K-style popover.
  - Tool events become a typed `AIChatMessage.Tool { name, state, result }` instead of the `"running:"` and `"complete:"` string prefixes, with a backward-compatible decode.
  - Errors are actionable: Retry, Switch model, Open AI Settings.
- **Downloads** (P03–P05):
  - Each download snapshots its destination.
  - Saved URLs are structured, and Open and Reveal work.
  - Missing files are explained.
  - Errors are expandable and selectable.
  - "Clear history" is labelled with its real scope.
  - Batch dedupe with rejected entries reported.
- **Translator**: late results never overwrite newer input. Unavailable language packs link to their download. Swap-languages action (⌘S). Copy and replace-selection actions.
- **Developer tools**: finish P10 and P11 (explicit seconds vs milliseconds). Every tool gets inline errors with an example, copy feedback, and ⌘1–9 tool switching.
- **Calculator**: a copy-answer toast, a history of the last 10 calculations (optional), currency staleness shown ("rates from 2 h ago"), and a unit-conversion alternatives row.
- **File Shelf and Convert**: drag in and out, supported-combination gating, a progress and cancel pattern shared with Downloads, and Reveal output. Dependency-setup copy gets rewritten to explain which tool is needed, why, and where to get it.
- **Agents**: loading, empty, live, stale, and disconnected states. Open goes to the exact session. Status age is accurate. Unsupported actions are hidden.
- **Widgets**: explicit stale and offline states. The storage label shows "free" or "used". Polling only runs while visible (already true; verify).
- **Emoji**: grid-column option, persistent recently used, skin-tone picker (⌥ on selection), and a separate "no matches" state.
- **Browser and Notes**: a local cache off the keystroke path. The "unavailable integration" state is distinct from "empty".
- **Feature-cut audit**: deliver a table with each surface, its value, cost, and a recommendation, for approval before anything is cut. The initial proposal:

  | Surface | Proposal |
  | --- | --- |
  | Camera preview | Hide by default; the command stays and can be enabled. |
  | Rebuild App | Debug builds only (done in P1). |
  | Firefox connector | Opt-in only (done in P1). |
  | 14 legacy widget kinds | Already resolved. |

  Anything else found during the sweep is added to the table.

**Exit:** every coverage row reads "passed" with screenshots in both appearances, or names an explicit, accepted limitation.

---

### P6 — Performance (applied continuously, closed out here)
1. **Observation migration.** Move `CommandPanelState` and the feature states from `ObservableObject`/`@Published` to the `@Observable` macro (macOS 14+). Views then re-render only for the properties they read, which fixes the "any change re-evaluates the whole panel" problem. Do this state by state, keeping `ShellController` wiring unchanged.
2. **Lazy feature states.** `camera`, `translator`, `fileConversion`, `developerTools`, `emojiPicker`, and `quickAI` are created on first entry to their mode, not in `init`. The emoji TSV loads lazily.
3. **Launch path.** Defer the `AgentMonitorState.startSocket`, browser, and AI provider setup until after the first panel open, or until 2 s after launch, whichever comes first. Measure the effect with `app.launch.ready`.
4. **Memory.**
   - Put byte limits (`totalCostLimit`) on the icon and image caches.
   - Release feature caches on panel close, except the search caches.
   - Keep the clipboard image thumbnail cache bounded.
   - Check `footprint` after the sweep. The target is under 130 MB idle, or the P0 budget if that is lower.
5. **Idle cost.** With the panel hidden: zero timers (check `widgetBoard` and agent polling), no main-thread wakeups above baseline, and an event tap only when snippet expansion is enabled.
6. **Search.**
   - File search stays on the deferred tier with a hard cap.
   - Shortcuts and Scripts come from caches only.
   - Ranker sorting is computed once per publish.
   - Verify p95 against the budgets.

**Exit:** all P0 budgets are met or beaten, with before and after JSON committed and a short report in `docs/benchmarks/2026-xx-foundry-1.1-report.md`.

---

### P7 — Deslop and final gate
1. **Code.** Run `code-deslop` and `thermo-nuclear-code-review` on the full diff since the P0 commit.
   - Remove leftover mode chains.
   - Remove stringly-typed status: `diagnosticsSummary.contains("result")` in the footer becomes a typed footer status.
   - Remove the ad-hoc `NotificationCenter` bridges for snippet accessibility; call through the shell directly.
   - Run `periphery scan` locally at zero new findings. CI adds a `periphery` step only if it stays within the budget of one tool and no new package dependency.
2. **Copy.** Run a `clean-copy` pass over every user-facing string. Examples to replace:
   - "Stop the local prototype process"
   - "Apple Foundation Models first, with optional Ollama tools"
   - "Checking apps, commands, and connected tools."
   
   Use sentence case, verbs on buttons, and state what happened plus what to do next in every error.
3. **Accessibility.** VoiceOver labels on every icon button (48 exist today; audit all), focus order, Increase Contrast, keyboard-only completion of every flow, and Dynamic Type not required (macOS).
4. **Final sweep** on a fresh macOS user account:
   - Install from the notarized DMG → onboarding → search → clipboard paste → snippet insert → quicklink with argument → file search plus Quick Look → download and reveal → convert → dev tool → AI → Settings search → export backup → Sparkle update to the next build.
   - Test the upgrade from a 1.0.0 config with clipboard JSON.
5. **Release.** Bump `VERSION` to 1.1.0, write release notes naming user-visible changes and known limits, update the README feature list and install instructions (DMG and brew), and cut the release through the new workflow.

**Final acceptance criteria ("premium" means all of these):**
- A fresh install is notarized, shows no launch-time modal, completes onboarding in 30 seconds or less to first command, and every permission is just-in-time and recoverable.
- Every coverage row passes, in Light and Dark, with Reduce Transparency and Reduce Motion, and keyboard-only.
- No known wrong-target action, false success, lost input, stale publish, or dead-end error.
- Core parity features ship and appear in root search with aliases, hotkeys, favorites, and ⌘K actions.
- P0 budgets are met, and before and after numbers are published.
- `swift test`, `build-app.sh`, `verify-packaging.sh`, and `git diff --check` are green on the final revision, and the visually tested binary is the released binary.

## 4. Files touched (overview)

**New:**
- `Shell/StatusItemController.swift`, `Shell/SettingsWindowController.swift`
- `UI/Onboarding/*`, `UI/Settings/*` (split), `UI/Components/{FeatureHeader,Footer,SplitResultsView,EmptyState,InlineNotice,ActionPopover}.swift`, `UI/PermissionHealthState.swift`
- `Features/FileSearch/*`, `Features/Quicklinks/*`, `Features/Scripts/*`, `Features/Shortcuts/*`, `Features/System/SystemSettingsProvider.swift`, `Features/Clipboard/ClipboardSQLiteStore.swift`
- Matching tests.

**Heavily modified:**
- `CommandPanelState.swift` and `CommandPanelView.swift` (split per surface, `@Observable`)
- `PanelController.swift` (prewarm, animation, compact mode, shadow)
- `ConfigService.swift` (v7)
- `AppDelegate.swift` (no alerts, onboarding and status item)
- `FoundryTheme.swift`, `PanelRowViews.swift`, `CommandModels.swift` (action shortcut)
- `AppSearchProvider.swift`, `SystemCommandProvider.swift` (settings panes removed)
- `ClipboardHistory*`, `Snippet*`, `QuickAI*`, `MediaDownloads*`, `WindowLayout*`
- `scripts/build-app.sh`, `scripts/verify-packaging.sh`, `scripts/benchmark-launchers.swift`, `.github/workflows/release.yml`, `Package.swift` (Sparkle), `README.md`

**Deleted:** `UI/WidgetSettingsView.swift` (after the split), the settings-mode branches in the panel, and the launch-time NSAlerts.

## 5. Risks and considerations
- **Sparkle packaging outside Xcode**: the XPC services must be signed inside-out and `--deep` must be dropped. `verify-packaging.sh` must check `codesign --verify --strict` and `spctl -a -t exec`. This carries notarization risk and is tested early in P1.
- **Credentials are lead-only**: P1 CI steps stay blocked until the user adds secrets. Local signing can proceed with a keychain identity.
- **Spotlight hotkey detection** reads an undocumented plist key, 64. Detection is best-effort, and the flow still works if it is wrong: the user records a shortcut, and registration failure surfaces inline.
- **`@Observable` migration** touches every view. Do it state by state, with existing tests plus the screenshot rig after each one.
- **Clipboard migration** carries data-loss risk. The migration is idempotent, keeps the old archive, uses a transaction, and gets a corrupt-input test.
- **Breadth**: this is a large program. Phase gates and one commit per slice keep it reviewable, and the cut audit keeps scope from growing.
- **Raycast directive compatibility** is a documented subset only. Anything unsupported is ignored with a warning, never emulated.
- **Bundle size** grows by about 3 MB with Sparkle. That is acceptable; record it in the benchmark report.

## 6. Stop points needing the user
1. P1: signing, notary, and Sparkle secrets, and consent to create the Homebrew tap repository.
2. P2e: pick the design variant.
3. P5: approve the feature-cut table.
4. P7: approve the release and version bump.
