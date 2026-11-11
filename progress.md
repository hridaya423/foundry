# Foundry progress

## Current state (2026-11-09)

- Version 1.3.0 is released (`d5519b4`, tag `v1.3.0`). `origin/main` is at `d5519b4`.
- Local `main` is at `e0feee5` and is not pushed. Seven commits follow the release, one per audit plan except 002, which has two: 001 conversion output staging (`d40d3df`), 002 numeric crash guards (`6d22bd9`, `e0feee5`), 003 snippet expansion (`796421c`), 004 command logic fixes (`892ba63`), 005 AI and sign-in hardening (`e8f7d04`), 006 README and release text (`af8e2d5`). Plan 003 is not yet tried in the running app.
- A fix-all run is in progress. Each agent works in its own worktree under `~/.t3/worktrees/anvil/`, branched from `e0feee5`, and the coordinator merges the branches. This file belongs to the docs hygiene branch `t3/fix-all-docs-hygiene`.
- Nothing from the fix-all run is pushed. No push, PR or `VERSION` change happens without the owner.
- Distribution (signing, notarization, DMG) is covered by `docs/distribution.md`.

Everything below this section is the historical log, oldest first. Sections stay as written, with these corrections:

- Evidence paths in the system temp folder no longer exist. They read "scratch captures, not kept".
- The refs `refs/minicmp/old-mini` and `refs/backup/2026-11-03/*` do not exist in the repository. The branch backup is the bundle `~/Honey/.backups/anvil-2026-11-03/refs.bundle` (see "Branch consolidation").
- The tags `v1`, `v1.0.0` and `v1.1.0` exist. The "Branch consolidation" note says they were deleted.
- Sections that describe goals or open work from October (installer, onboarding, logo, website gauntlet, Awwwards and SOTD passes) are superseded by the 1.3.0 release and the 2026-11-01 plan.

## Installer, onboarding, and logo overhaul (October 2026, superseded)

Design source: Paper file "Foundry — Mark, Installer, Onboarding" (01M5DNZWNYY4BFG9J1TPGJJQQV).
Brand source: the website in anvil/ (ink ground, chalk tiles, Geist, an orange full stop that closes each headline).

## Bars (each part must pass before it counts as done)
- Icon: sits in a real Dock row next to Raycast, Cursor, Obsidian, Safari, and Notes on light and dark Docks without looking weaker. Readable at 16 px. Built from the site's own language, not a new metaphor.
- Onboarding: every step screenshotted from the real app. It must look like the website made it. One job per step and one focal visual. Motion carries meaning. No default bordered-prominent button, no centred three-line stack, no confetti.
- DMG: the Finder window itself is screenshotted. No tracked-caps "DRAG TO INSTALL" eyebrow.
- Code: scripts/lint-design.sh, lint-l10n.sh, and swift build pass; swift test passes.

## Done
- Icon: the site's tiled "f" in chalk tiles plus a 2x2 orange tile full stop, on ink, Apple 824/1024 grid (scripts/render-icon.swift, Supporting/AppIcon.icns). Rejected along the way: glowing letter F, forged keycap ("gaming keyboard render"), pour mark (unrelated to the site).

- Onboarding in the site language: Geist, ink, chalk keycaps, orange full stops. Welcome casts the icon's "f." tile by tile. Seven steps screenshotted from an isolated QA copy (bundle com.hridya.foundry.qa); no overlaps, Geist loads.
- ⌘Space is the default. Onboarding turns off Spotlight's ⌘Space and moves Raycast or Alfred to ⌥Space (LauncherRival.swift). README and the download gate say ⌘Space.
- swift build, full swift test (656 tests, 0 failures) and the three lint scripts pass.

- Onboarding pass 2: the footer waits for the cast to finish; Try it plays a slow demo press of the chord until the panel opens; Done rows share one type style and the ⇧⌘V row shows key chips and why it is off.
- DMG: chalk ground, because Finder draws icon labels in black. Seven tiles warm toward Applications and end in the orange full stop, over "Drag Foundry into Applications." in Geist. Shipped as a multi-resolution TIFF so Retina is sharp. Icon size is now 112. Checked in a real mounted Finder window.
- Menu bar: a solid "f." template image at 14 pt (MarkTiles.menuBarImage) replaces the SF "command" symbol. Checked in the live menu bar.

- Launcher panel: removed the spring settle on open (PanelController.show); it now only fades in over 0.18 s. Asked by the user. Not yet in the installed app.

## Session 2026-10-21
- Shortcut step redesigned: the two giant chalk slabs are now a full MacBook keyboard in ink, with the chord cast in chalk (orange once the panel runs). Real key presses dip the keys. The "Record a new shortcut" button became one Raycast-style field: "Shortcut ⌘ Space · Change"; recording lights held modifiers live. Mock: Paper artboard "Onboarding · 2 Shortcut v2". Evidence: scratch captures, not kept (offscreen), scratch captures, not kept (real QA app), scratch captures, not kept.
- Unsigned-build warnings: already gone from the tree (DownloadNotice quarantine prompt, website modal + CSS, README). Verified by grep.
- build-app.sh now prefers the Developer ID identity (it used to take "Apple Development", which notarization rejects).
- package-dmg.sh: the mount-point parse took the last line of `hdiutil attach`, which is a partition row with no mount, so the branded layout silently fell back to a plain DMG. It now takes the `/Volumes/` row.
- Signed: build/Foundry-1.2.0-build-1.dmg (app + DMG, Developer ID, hardened runtime, timestamp). `codesign --verify --deep --strict` passes; `spctl` says "Unnotarized Developer ID" as expected. Finder reports the DMG window at 540x360. A screenshot of it was not possible because Stage Manager kept moving the window.
- Checks: swift test 656 tests, 0 failures; lint-design, lint-l10n, lint-lines pass.

- Round 2 (user feedback): Try it now teaches open + close: "Now press it" -> "Now press it again" -> closing the panel is the success (orange keys, warm glow, auto-advance). It used to leave the panel open. `completeTryIt()` replaces `panelDidRunCommand()`. Launch at login explains itself when unavailable (test build). AI step: no Continue; Return picks the recommended row, marked with a ↵ chip. Steps slide in the direction of travel (`OnboardingState.movedForward`). Checks: 656 tests, 0 failures; three lints pass.

- Round 3: "Press it again" now shows in the panel's search placeholder (`CommandPanelState.searchHint`), because the open panel covers the onboarding window. Motion: one token set `FoundryTheme.Brand.Motion` (ease-out 0.23,1,0.32,1; press 120 ms, state 220 ms, enter 450 ms, 6 pt rise, 50 ms stagger), no springs or overshoot left in onboarding; steps crossfade with a 4 pt blur. Welcome redesigned (Paper "Onboarding · 1 Welcome v2"): editorial left grid, two-line large headline bottom-left, the "f." mark top-right in chalk keycap tiles with sides; cast is quieter (6 pt rise, no scale, ~1.2 s). Filmstrip: scratch captures, not kept; render: scratch captures, not kept. QA copy deleted at the user's request; their Foundry is running. Checks: 656 tests, 0 failures; lints pass.

## Round 4 bar ("holy shit", not "clean")
- Welcome cast reads as real molten metal: white-hot landing, cooling ramp, emitted light on the ground that decays with the heat. Ember stays on the full stop.
- Chalk surfaces respond to the cursor as a light source (smoothed, subtle).
- Judged from a video of the real window, frame by frame, not offscreen stills.
- No showy motion: every movement still answers "why".

- Round 4 done: molten cast (heat model `MarkTiles.heat`, face cools white->yellow->orange->amber->chalk via `faceCoolRamp`, red only in the bloom; floor light decays with heat; the full stop keeps an ember). Cursor light on the mark (`CursorLight`: eased pointer, falloff + sheen); not verified live because synthetic mouse events need Accessibility. Bug found by live video: the window can open behind the frontmost app, so the opening played unseen; onboarding content now waits for the window to become key (`windowSeen`). Evidence: scratch captures, not kept.

- Round 4 rejected by the user ("sloppier"): molten cast and cursor light reverted to the round-3 cast. Kept: the windowSeen fix.
- Round 5 bar: Raycast, Linear desktop, Things 3, Apple first-run. Restraint, exact type, one spacing scale, every state designed, quiet motion. Blind critic (Sonnet 5.5) running on scratch captures, not kept. Own findings so far: headline-to-content gap 44 vs 36 (Done); list surface diagonal gradient bands.
- Round 5 fixes (from critic r1 + own findings): one footer on every step (progress left, Back + primary right, primary label min width so Back holds still); "Skip setup" top-right, dimmed (`Brand.faint`, `BrandQuietButtonStyle(dim:)`). AI step is a real choice: four rows with `BrandSelectionMark`, recommended preselected, "No AI" row, Continue confirms via `chooseAI`. ⇧⌘V clipboard toggle moved from Done to Preferences. One `listGap` (36) under every headline. Keyboard: number row and top fade removed, sits 180 pt down. Shortcut lead no longer repeats the chord. Try-it link reads as a link; primary says "Skip" until the shortcut is pressed. Flat list fill (`rowBottom` deleted). SF "return" glyph in the CTA. "Allow…". Done rows 56 pt. Evidence: scratch captures, not kept. Checks: 656 tests, 0 failures; three lints pass. Blind critic r2 ran (scores 6–8/10); its fixes applied:
  - The CTA is a fixed 172 pt, so Back never moves.
  - Try it: Continue is a quiet outline with no Return until the shortcut works.
  - AI: squared radio plus a selected-row fill (`Brand.rowSelected`); titles "Local model", "Cloud provider".
  - Done hides "Ask AI" when AI is off.
  - Launch at login copy now matches Settings.
  - The Welcome lead reads "Everything on your Mac, one keystroke away." and sits on the mark's base.
  - The keyboard top is level with the lists, and "Change" is plain text.
  - Rows are 14 pt vertical padding; disabled rows are at 0.6 opacity.
  - Evidence: scratch captures, not kept. Checks: 656 tests, 0 failures; lints pass.
- Live recording attempt failed: the user was using the Mac, so other windows covered the onboarding window, and the synthetic ⌘ Space went to the frontmost app. Recording deleted. Do not run the live rig while the user is at the machine; ask first. Still open: the critic's "Permissions dead space" and "Try it repeats the keyboard" points.

- User-reported bug, fixed:
  - Cause: the onboarding view honoured the titlebar safe area. The 880x580 view sat 28 pt low, a bare-window band showed above it, and the bottom margin was squeezed to about 21 pt.
  - The "32 pt render artifact" in every earlier snapshot was this bug, wrongly dismissed.
  - Fix: `.ignoresSafeArea()` on the root view.
  - OnboardingSnapshotTests now hosts the view the way OnboardingWindowController does. It always runs, and only writes images when the dir is set. It asserts the top and bottom edges are brand ground. It was red without the fix and is green with it.
  - Evidence: scratch captures, not kept. Checks: 656 tests, 0 failures; lints pass.
  - The user's Foundry is restored and the QA copy deleted.

- Panel vs installed 1.1.0 (/Applications, built 2026-10-06 at 71a4726, 61 commits behind). Captures: scratch captures, not kept.
  - Position: Phase work had changed the top inset from 140 pt (280 px / 2) to 25% of the visible height, which is 245 pt on the user's 14" (979 pt visible). The user prefers the old slot, so it is now `visibleFrame.height / 7`, 140 pt here. Verified live: the branch panel sits at the same Y as the installed one.
  - Bug: home selected `homeResults.first`, which can be a row home hides (a non-suggestible app or a primary window layout). Nothing looked selected, and Return could act on an unseen row. Now it selects `navigableResults.first`. Test `testHomeOpensWithTheFirstVisibleRowSelected` was red before the fix.
  - "RAM" truncated to "R…": the 11 pt semibold label measures 25.3 pt in a 25 pt column. The column is now 30.
  - Not changed, waiting on the user: Title Case section headers (1.1 used tracked caps) and the selected row's missing border (1.1 had `selectionBorder`).
  - Checks: 657 tests, 0 failures; lints pass.

- Restored the v1.1.0 panel look (user asked); bug fixes kept.
  - Rows: 28 pt icons, 44 pt rows, detail line under the title (hidden for commands), filled hotkey badge, 13.5 medium titles via `FoundryTheme.rowTitle` / `rowDetail`.
  - Selection: `selectionBorder` outline; selected icon scales to 1.04.
  - Section headers: tracked caps (`FoundryTheme.sectionHeader`).
  - Widget strip: 1.1 font sizes via `FoundryTheme.Strip`; the RAM column is back to 25.
  - Entrance: the window appears at once and the content springs from 0.97 (`replayPresentation`). This is not the CASpring settle the user asked to remove earlier.
  - The pointer cursor is back (`pointerCursor()` in both shared button styles, rows and tiles).
  - Light-mode inner edge is back at black 0.06.
  - Kept deliberately: the window level stays `.floating`, because `.statusBar` drew the launcher over its own alerts and save panels (9a64ed3).
  - The `rows-light` reference was re-recorded and checked by eye.
  - Checks: 657 tests, 0 failures; lints pass.
- Live panel capture attempt 2 failed: the QA panel did not open, and the synthetic ⌘ Space and Esc reached the user's frontmost app. Do not send HID events again; ask the user to try builds themselves.

## Remaining (October, superseded: 1.3.0 is released)
- Notarize: no notarytool credentials on this Mac. Needs `xcrun notarytool store-credentials foundry --apple-id <id> --team-id DV6NC6KRYL` from the user, then `NOTARY_PROFILE=foundry zsh scripts/notarize-dmg.sh build/Foundry-*.dmg`.
- Rebuild and install to /Applications so the user's Foundry gets these changes (asked, not yet confirmed).
- Nothing open from the brief. Not tested live: the Spotlight, Raycast and Alfred takeover, because nothing holds ⌘Space on this Mac (unit tests cover it).

## Website gauntlet (anvil/, vs igloo.inc), 2026-10-22
- The first loop (jury round 0 plus gauntlet rounds 6 to 15) was discarded at the user's request: its critic counted motion, and the result read as slop. anvil/ was reset to 97ee8f1. The discarded version is in .jury/taste/snapshots/foundry-before-taste.tgz.
- New loop: taste first, against igloo.inc, with critics who judge restraint and name what to remove. No /jury skill. Live log: .jury/taste/progress.md.
- Servers: production `npx next start -H 127.0.0.1 -p 4471`. Recorder tools in ~/.cache/jury (record.mjs, still.mjs, fullpage.mjs).
- Open: metadataBase domain still to confirm with the user before deploy.

## Port from old mini line (d1d7323; its ref was deleted on 2026-11-03), 2026-10-23
Audit: 5 Sonnet 5.5 reviewers read all 85 old-mini commits against this tree. Deliberate redesigns (flat search list, neutral selection, radius 26, ⌘Space default, ⇧⌘R reveal, pop-to-root clears query, Disk widget) and the absent docs are out of scope.

Bugs
- [x] B1 Backup restore carries script-folder trust (config.json localState.trustedScriptDirectories)
- [x] B2 ⌃ chords never reach action shortcuts (PanelController.handleShortcut gates on ⌘) → ⌃X delete unreachable
- [x] B3 `f ` recent-files mode unreachable (query trimmed)
- [x] B4 Snippets ⌘↵ copy skips argument prompt (copies raw placeholders)
- [x] B5 Bare `{argument}` not recognised
- [x] B6 `~/` and `/` quicklinks not opened as files
- [x] B7 Lazy feature states built by resetTransientFeatures

Missing features
- [x] F1 Fallbacks: choose/order + Define, "When nothing matches" pane + search entry
- [x] F2 Script fullOutput in-panel surface, ⌘↵ Copy Output
- [x] F3 Script results: Show in Finder, Copy Path
- [x] F4 Shortcuts input: "Name with “text”", Run with Clipboard, subtitle hint
- [x] F5 ⌘E Edit Snippet / Edit Quicklink
- [x] F6 Suggested ⌃⌥ window-layout hotkeys
- [x] F7 DevTools Base64/JSON errors with example + parse location
- [x] F8 Settings panes: Permissions, File Search (folders, skipped names), Snippets, Browser; snippet export button
- [x] F9 Clipboard: skip API-key/token strings; retention menu 1 day … Forever
- [x] F10 Quick AI footer model menu; Switch Model on failure
- [x] F11 Translator ⌘↵ replace (copy fallback), ⇧⌘C copy
- [x] F12 Emoji skin-tone header menu, ⌘1–6
- [x] F13 "What's new" one-time notice
- [x] F14 Search footer "N results"
- [x] F15 App results: Show in Finder, Copy Path, Copy Bundle ID
- [x] F16 Increase Contrast selection (stronger fill, 2 pt accent outline)
- [x] F17 {selection} snapshot at panel open; Quicklinks help text
- [x] F18 Favicon global switch (disk cache skipped: CommandIconRepository already has a 32 MB disk URLCache)
- [x] F19 ⌘K "Set Hotkey or Alias…" title, filter Commands list
- [x] F20 Copy: Downloads "Clear List"; delete-confirm detail text
Notes: B4 also covered the Snippets-view Copy button and root-search snippet Insert/Copy, which all bypassed the prompt (root results now open the snippet and ask). Tests added per item; filtered suites green.
Visual QA pass (offscreen NSHostingView renders, temp test since deleted, scratch captures, not kept): fixed the Quick AI model menu (borderlessButton ignored its style, so it read bold white), "1 snippets" (now inflected), the "~" title in File Search (now the folder display name), the truncated `f` empty-state hint, and the dimmed empty script output.
Verification: swift build clean; swift test 677 tests, 7 skipped; 6 of 7 full runs had 0 failures, 1 run had 1 failure that did not repeat and was not identified; lint-design, lint-l10n, lint-lines pass. Not committed.
Open: SelectionSnapshot has no dedicated test; "Forever" retention is 3650 days.

## Website Awwwards pass (anvil/), started 2026-10-23
Source: the review in this session (critic: separate Opus 5.5, scores D6 U5 C7 Ct5). Baseline shots: scratch captures, not kept (ephemeral). Server: `npx next start -H 127.0.0.1 -p 4471` in anvil/. Playwright lives in ~/.cache/jury (run shoot.mjs with cwd there).
Decisions:
- Proof stat = speed, not memory: "19" ms (slower median of two runs, hotkey to on-screen window, Foundry 1.1.0, MBP M4 Pro, battery; docs/benchmarks/2026-09-29-foundry-1.1-tinycast-0.11.3-mbp-report.md). No competitor named on the site until the legal review the old methodology page mentions.
- Released v1.1.0 defaults to ⌥Space (git show v1.1.0), so the download dialog keeps ⌥Space.
- Media section and all third-party media removed; video download becomes a tool (LINK to MP4). Coast photo (no recorded source) replaced by the tile orange.
- The launcher panel stays a crisp replica of the real app (neutral selection), not tile-built. The tiles pass through it.
Plan (tick as done):
- [x] A1 speed section replaces memory; text shows only after tiles settle
- [x] A2 methodology rewritten (Foundry-only, no internal notes, no dashes); memory raw assets removed
- [x] A3 keyboard: `inert` gating replaced by data-active + scroll-on-focus
- [x] A4 collisions: PNG grid vs heading, ribbon, end trail
- [x] A5 404, OG image, robots, sitemap, metadataBase (env), JSON-LD, Anton removed
- [x] A6 axe fixes; A7 hero panel matches app; A9 clipboard simplified
- [x] B restraint: one orange period, underline tabs, nav logo only after hero, shorter tile texts, notes window + duplicates removed, dead CSS
- [x] C1 ribbon removed; C2 closing wordmark rebuild; C3 stiffer scroll spring, no per-frame blur, CTA hover; C4 shorter track
- [x] QA pass 1 + fresh critic (Opus 5.5, shots scratch captures, not kept): D7.5 U6.5 C7.5 Ct7.5, overall 7.2
  Fixed from its list: clipboard exit lift removed (heading slid under phone nav), CTA hover is a rising cream fill, skip link on every page, focus reveal jumps the spring (invisibleFocus 0), 404 title + shared SiteHeader/SiteFooter (app/foundry/site-chrome.tsx) on 404 and methodology, phone shelf tabs on one line, AI tool label "Draft, rewritten with Writing profile".
  Declined: "24 × 18" caption kept (it explains the 432 frame); inline "Foundry source" link exempt from target size; DPR not raised on phone (FPS cost); no page transition added.
  Pass-2 evidence (scratch captures, not kept): audit 0 FAIL 0 WARN; skipLinkFirst true on all pages; invisibleFocus 0; axe 0; home colorOnly 0; 404 returns status 404.
- [x] QA pass 2 + fresh critic (Opus 5.5, shots scratch captures, not kept): D7 U7 C7.5 Ct8, overall 7.2; Semantics 8, A11y 8, WPO 8, Markup 8, Animations 7, Responsive 7
  Fixed: tool captions switch input -> result (calculator caption only on 432, AI "Draft" -> "Writing profile · sample response", video "Video link" -> "Saved file"); nav Download hidden while the hero or closing CTA is on screen; current-page footer link underlined.
  Final crawl (scratch captures, not kept): audit 0 FAIL 0 WARN, axe 0, skip link first, focus all visible, no overflow, 0 console errors. Remaining flags are the current-page link and footer utility links (by design).
Open, not done (structural, need a decision):
- Throttled phone scroll 19-22 fps; phone wordmark tiles read as noise at 390 px. Fix = larger tiles / fewer instances under 480 px.
- Methodology page carries no tile language; no continuous home -> methodology transition.
- Inline "Foundry source" link 22 px tall (inline exception, left as is). Hero palette search looks like a field but is not one.
Evidence so far (shots and phone frames: scratch captures, not kept):
- Build clean. Home: 0 console errors, 0 axe violations (baseline 2 serious), no overflow, no small targets, mobile LCP 1.1 s, CLS 0.
- Scroll FPS (headless floor): desktop 26 (baseline 18), throttled phone 20 (baseline 7).
- Failed requests on every page are aborted `_rsc` prefetches only.
- Keyboard reaches every demo; "How we measured" flagged invisibleFocus by shoot.mjs because it shoots before the focus scroll settles; focus-check.mjs confirms it visible (opacity 1, ring drawn).
- Phone: HEIC tile no longer overlaps the shelf subtitle (anchors moved to 33%/47%); tool tab row fades at its edges.
- OG image: app/opengraph-image.png (1200x630 hero).

### User feedback round, 2026-10-24
User: liked the previous footer, wants "81% less memory" over "19 ms", finds the new clipboard lame.
- [x] Memory section restored (memory.tsx/.css/-motion.ts, renamed back from speed-*): tile "81%" + "115.2 MB", "vs 620.2 MB · Raycast 2.5.3", provisional context line, "Read methodology". Timeline: memoryStart = toolsEnd, settled +.18.
- [x] Methodology rewritten for memory (docs/benchmarks/2026-09-29-foundry-1.1-raycast-2.5.3-mbp-report.md, linked on GitHub). Old raw files in public/ stay deleted: they are the August run (69%), not the source of 81%.
- [x] Ending restored: two-line heading, tile trail + arrow into the CTA, footer = wordmark + GitHub + Release notes. SiteFooter now renders that footer on home, methodology, 404. Closing wordmark rebuild removed. Nav fully hidden at the close.
- [x] Clipboard restored: ribbon of the 48 removed background tiles, coast photo card, YouTube link card, detail line, Previous/Next, Copy item. Kept fixes: data-active gating (keyboard reach), card names from content (axe), no em dash, blur off on phones, ribbon shrinks out 1.5-1.58 before tools. Phone: heading at 11%, detail title/value hidden so the ribbon clears them.
Evidence (scratch captures, not kept): audit 0 FAIL 0 WARN; axe 0 on all pages; skip link first; invisibleFocus 0; 0 console errors.
Open: naming Raycast needs the legal review noted in the Sept report; coast.jpg has no recorded source.

### Round 3, 2026-10-24: clipboard belt, phone tiles, tile transition
- [x] Clipboard is one belt: `clipboardSelection` drives both the DOM cards and the GL ribbon (passed to the scene as `clipboardBelt`). Cards sit on the ribbon (anchored bottom-centre, tilted by the ribbon slope), land in turn from 1.01, loop so the right side never empties, and the belt carries everything off left at 1.5-1.58. Leftover shelf tiles now shrink in place (no rise into the heading). Phone belt amplitude halved; phone photo card 58% wide.
- [x] Phone tiles: "bigger, fewer tiles" is not possible without a shelf redesign (createShelfTiles needs all 272 full tiles). Root cause of the noise was the 1.25 DPR cap; phones now cap at 2. Throttled phone scroll on a real GPU (Metal, 4x CPU, DSF 3): median 16.7 ms, p90 18.3 ms. The crawler's 19-22 fps comes from SwiftShader (browser.mjs launches with --enable-unsafe-swiftshader), not the site.
- [x] "Read methodology" transition: the 81% tiles fly to the methodology figure (app/foundry/methodology-figure.ts, shared geometry), the rest fades, then router.push; methodology renders the same figure in DOM tiles and fades its content in (html[data-arriving]). Positions verified equal at 1440/1024/390 (figure top 132, tile centres match to 0.02 px). Back button returns to the memory stop (story progress kept in history.state).
Evidence: scratch captures and crawl, not kept (audit 0 FAIL 0 WARN, axe 0, focus all visible, 0 console errors).
Scripts (outside the repo; the ones in the temp folder are gone): ~/.cache/jury/{transition,back,profile-phone,hero-phone,figure-rect}.mjs.

## Prototype: tile world (removed 2026-10-24)

Built at `/world` on branch `website-tile-world`, then deleted at the user's request ("don't like world"). Nothing from it was committed.

## Craft pass, 2026-10-24 (branch `website-tile-world`, uncommitted)
Design: `anvil/docs/plans/2026-10-24-craft-pass-design.md`.
- [x] Step 1, real launcher. `app/foundry/launcher.tsx` + `launcher.css` copy the running app's panel (reference screenshots taken from Foundry.app, not kept). Sizes are in points through `--pt` (41.8vw / 750 on desktop, 1px on phone). Live: filter, arrow keys, Enter opens the story stop (`toolStop(i)` added to tools-motion), math via `app/foundry/calculate.ts` (copy answer on Enter). Hero panel at left 53%, top 31.55vw; tile flight path points in `tile-motion.ts` pulled toward the panel so the trail runs between the headline and the panel. Tools section: compact panel (query + action row) replaces the thin bar.
  Evidence: scratch captures, not kept; shoot.mjs: axe 0, 0 console errors, skip link first. shoot.mjs flags the launcher input as "noVisibleFocus" because the ring is drawn on the panel through `:has(input:focus-visible)`; scratch captures, not kept shows the ring.
- [x] Launcher cleanup (user request): removed the stats strip (sample numbers), Ask AI, repeated "Command" labels and the ⌘ / Actions footer items. Placeholder "Search commands...", hairlines under the search and above the footer, ↵ keycap only on the selected row, footer "↑↓ Select · ↵ Open" (hint hidden on touch). Panel height 360 pt. Flight path end retuned to the moved Convert Image row. Evidence scratch captures, not kept.
- [x] Launcher as a marketing piece (user: "doesn't need to be pixel perfect, make it really impressive"). Two columns: six commands left, live preview right. Self-running demo types clip, 24*18, hello, png in a loop (pauses when scrolled past 40 px, hidden tab, reduced motion; stops on pointer enter or focus, resumes on leave if empty). Selection glides (motion layoutId). Previews: clipboard cards from clipboardItems, calculator answer drawn in glazed tiles (tileText), Convert Image shows the tiled orange whose background tiles fall away on a loop, Translate, Snippets, Download Video with a progress bar. Rows never unmount (non-matches dim), so `#foundry-command-1` always exists for the tile flight gate. Glass gradient edge, warm halo. Evidence scratch captures, not kept; axe 0, console 0.
- [x] Calm pass (user: "looks ugly / like the gradient behind it too"). launcher.css: removed orange halo, gradient edge, orange focus ring, search and preview dividers; flat panel `#1b1917f2` with hairline; recessed preview; soft `#ffffff0f` selection; borderless cards, chips, keys. Focus is now a brighter hairline plus orange search icon. foundry.css: `.foundry-stage` radial gradient flattened to `#0f0d0c`.
  Evidence: scratch captures, not kept. The visible warm glow came from `.story-stage` in story.css (radial at 65% 45%), now flat too.
- [x] Type pass: shelf, clipboard and tools section heads share `clamp(44px, 5.2vw, 92px)`, line-height 1.04. Tools compact launcher `--pt` 41.8vw/620 (row text 14.5px at 1440).
- [x] Phone bleed fix: phone launcher was 997px tall in an 844px stage, so its last rows trailed under the nav after the hero left. Results now scroll inside 216pt with a fade, preview 170pt. Probe: launcher bottom -48px at scroll 4000.
  QA (shoot.mjs, `~/.cache/jury/.shots`): 0 axe violations, 0 audit FAIL/WARN, 0 console errors, CLS 0, mobile LCP 1.1s. Still flagged: launcher input noVisibleFocus (focus = brighter hairline + orange icon + caret; user rejected the ring).
  Critic pass 1 (Opus 5.5, evidence scratch captures, not kept): 7.15 (D7 U7 C7.5 Ct7.5). Fixes done from its list:
  - Handovers through black: hero tiles now stay on screen (`gatePassage` gate y clamped to >= 10% height in shelf-motion.ts); belt tiles carry into the tools glyphs (tools-motion `writeToolsTilePose` mixes from the prior pose; belt keeps 60% size, clipboard-motion exit); clipboard text out 1.47-1.55, tools in toolsEnter-.03 to +.05; closing headline in at downloadStart+.04 to +.12. Frames scratch captures, not kept.
  - Closing trail no longer ends beside "Your next" (3 desktop trail points removed, download-motion.ts).
  - Header Download flash: `data-quiet` no longer waits for the GL scene (story.tsx), SSR ships `data-quiet="hero"`.
  - Not bugs: `hover.covered` is a scrollIntoView artifact (each control hits at its own stop, `~/.cache/jury/probe-covered.mjs`); the PNG label fades in 0.79-0.825 by design.
  - Left: copy rewrites ("Small tasks. All here.", "Your next command starts here.") need the user's call; launcher focus ring rejected by user.
  Critic pass 2 (evidence scratch captures, not kept): 7.6 (D8 U7 C8 Ct7; dev Sem8 Anim7 A11y7 WPO8 Resp7 Meta8). Fixes done after it:
  - Hero shows the summon shortcut: `⌘ Space from anywhere` keycaps beside Download (hero-content.tsx, `.foundry-actions`/`.foundry-hotkey` in foundry.css). Default is ⌘Space per ConfigService.swift and README.
  - Hero launcher text up (search 24pt, rows 16.5pt, labels 13pt); panel geometry unchanged because the tile flight path is tuned to it.
  - Phone orphan "app." fixed with a non-breaking space in the shelf heading (`text-wrap: balance` does not act on the line after `<br>`).
  - Regression QA after: 0 axe, 0 audit FAIL/WARN, 0 console errors, CLS 0, mobile LCP 1.16s.
  Open from pass 2 (needs the user or a bigger change): launcher focus ring (rejected by user); generic heads "Small tasks. All here." and "Your next command starts here."; AI demo result reads "FREE TOMORROW" in tiles; phone tools stage has ~800px of empty space (m-04); tiles cross text during handovers; reduced motion shows flat slabs instead of tile results; methodology page transition.
- [ ] Step 2 tile material. [ ] Steps 3 and 4 type and grid. [ ] Step 5 motion.

## SOTD push, 2026-10-24 (user: perfect phone, fix collisions, fix copy, fix reduced motion; skip accessibility)
- Env surprise: `anvil/node_modules` and `~/.cache/jury/node_modules` both vanished mid-session (not by this session). Restored with `npm ci` and `npm install`.
- [x] Shelf stops: "Original" showed a lone HEIC; added a mold grid (dot per tile slot) on `.shelf-image-anchor` (story.css). Shows through as transparency after "Remove background".
- [x] Belt crossed the orange at the Remove background stop: `beltDrop` in clipboard-motion.ts keeps the belt below frame until 1.0-1.1; removed-tile stream sped up (head x14, +.5 offset after 1.0).
- [x] Heading overlap at 1.03 (desktop and phone): shelf out 1-1.035, clipboard in 1.035-1.085.
- [x] Tools to memory: unused tiles fade in the first 35% (memory-motion.ts); memory text in memorySettled-.04 to +.02, out downloadStart-.03 to +.01.
- [x] Copy: tools head "No new tab for that."; closing head "⌘ Space, then anything."; AI demo result "Are you free tomorrow?".
  Evidence: scratch captures, not kept.
- [x] Reduced motion / static mode: tools results drawn with `Tiles` (exported from launcher.tsx), source slab hidden, compact launcher shown, two-column grid on desktop; memory "81%" drawn with Tiles; static HEIC file has tile grout + label chip; static shelf tiles glazed; `.launcher-tiles i` animation off under reduced motion. Evidence scratch captures, not kept.
- [x] Methodology transition exists and works (81% tiles fly to the page header): scratch captures, not kept. Heading orphan fixed with nbsp.
- [x] 404 tiles moved to the glazed material (not-found.css).
- QA: 0 axe serious, 0 audit FAIL/WARN, 0 console errors, CLS 0, mobile LCP 1.10s.
- Critic pass 3 (stricter, 69 images): 7.1 (D7 U7 C7 Ct8; WPO 9). SOTD blocker: result glyphs switched to small flat LED cells mid-site. Fixed after it:
  - One glyph cell size: results capped at 7 chars per line, 2-line results get maxHeight .34 (tools-motion.ts). Snippet "Thank\nyou.", AI demo "can u call me" -> "Can you\ncall me?". Snippet caret fades at rest.
  - Mold grid painted over the hero launcher: moved to `.shelf-mold` child with `fileOpacity`.
  - Blank frame in methodology transition: `holdFigure()` in story.tsx puts an inline-styled copy of the landed 81% on body before router.push, removed by MutationObserver when `.methodology-figure` mounts (3s fallback). Methodology figure tiles glazed.
  - One header on every page: `SiteHeader` = `.foundry-nav` + Download + `GitHubLink` (shared from site-chrome.tsx); methodology figure margin 104px keeps y=132 for the flight target.
  - Phone tabs wrap to two rows (14px, no padding), `centerTab` deleted; phone glyph baseline .52, developer clock .455, label 34.5%.
  - Tools text fades in toolsEnter+.02 to +.08 so the belt passes first. Methodology table values nowrap. Static clipboard centers the selected card.
  QA: 0 axe serious, 0 audit FAIL/WARN, 0 errors, CLS 0, mobile LCP 1.24s.
- Critic pass 4: 7.6 (D7.5 U7.5 C8 Ct7.5; Anim 8, A11y 8, WPO 8.5). SOTD blocker: tools section = six identical beats, a third of the scroll. Fixed after it:
  - toolBeatLength .22 -> .15 (storyEnd 3.78 -> 3.36). New stops: tools 1.86/2.01/2.16/2.31/2.46/2.61, memory 2.92, end 3.36.
  - Demo content: AI "lol ok" -> "Sounds\ngood.", video input "youtu.be/aqz-KE-bpKQ".
  - Closing trail: only the 3 tiles below the headline + arrow (no clipped top-left segment).
  - Footers at the header gutter (2.87%, phone 20px) on home and 404. Story nav fixed in both modes (reduced motion keeps the header).
  - Handovers: hero copy out .28-.36, shelf heading in .35-.41, clipboard in 1.03-1.065.
  - Clipboard controls grouped in the right column under the heading (desktop ready); repeated value line hidden.
  - Phone tools launcher at 71%, developer date at .635H.
  QA: 0 axe serious, 0 audit FAIL/WARN, 0 errors, CLS 0, mobile LCP 1.28s.
- Critic pass 5: 7.1 (D7 U7 C7 Ct8; Anim/A11y/WPO/Sem/Meta 8). Critics swing 7.1-7.6; every pass names the same blocker: the tools section's six identical tab+output stops. Small fixes after it: tools heading fades in toolsEnter-.02..+.03, tabs and launcher toolsEnter+.04..+.09 (`controlsOpacity`, static override in tools.css); clipboard controls 14-15px; phone clock .47H, label 36%; 404 phone footer 20px. Not bugs: h-02 rest/hover pair captured mid hero-copy fade; `input "INPUT"` is the labelled clipboard search.
- [x] Tools section, "literal answers" pass (user asked for something more unique): calculator builds a 24x18 grid of 432 tiles, video link becomes a tile file icon with a play triangle (outline + dot fill, echoes the shelf mold), AI rewrite scatters into a cloud and recondenses. Translation flip, snippet caret and developer clock unchanged. Evidence: scratch frames, not kept; 0 console errors.
- [ ] Next: user feedback on the literal-answer direction; then a fresh critic pass.

## The last 20% plan, 2026-11-01 (superseded: executed, see the execution log below)
- Plan: docs/plans/2026-11-01-foundry-last-20-percent.md (7 phases, 50+ tasks, each pinned to a file:line finding).
- Evidence: three read-only audits (Opus 5.5) in docs/plans/2026-11-01-last-20-audits/{panel,features,onboarding}.md. P0 claims re-read in source before the plan was written.
- Open decisions D1–D8 at the top of the plan (entrance motion, four-step onboarding, launch at login default, Camera cut, keep DevTools/Translator as modes, casing rule, favicon policy, commit granularity). Tasks implement the recommendation; change the task, not the bar, if the user picks otherwise.
- Not started. The tree still carries the uncommitted mini port (Phase 0 lands it first).

## 2026-11-01: website "last 20%" plan
- Design: docs/plans/2026-11-01-foundry-last-20-design.md. Plan: docs/plans/2026-11-01-foundry-last-20.md (Phases 0, A brand, B truth, C craft, D verify).
- Done: Codex gpt-6.1-sol imagegen logo concepts in docs/brand/concepts/ (8 directions, CONCEPTS.md, RESEARCH.md); Sonnet 5.5 site research in docs/brand/RESEARCH-websites.md (25 ranked items, folded into the plan as R#). Shortlist in docs/brand/SHORTLIST.md. User chose Split Mould (Codex 02), Command Joint (05) as alternate.
- Not done: live screenshots of the site. npm registry was unreachable or at 3 KB/s; node_modules/@next/swc-darwin-arm64 is a truncated download and `next dev` fails to load SWC. Fix: reinstall that package when the network is back (Task 0.1 notes).
- Phase 0 done (3fbb8a2): port committed in three building commits; FoundryBackupTests compared re-encoded config bytes (the old intermittent failure), now compares decoded configs. Baseline in docs/benchmarks/2026-11-01-last-20-before.md. Design lint ratchet seeded. Not taken: panel.show and open-panel idle CPU (they put windows on screen).
- Phase 1 done: 1.1 resume after quit, 1.2 inert exits (abandon falls back to ⌥Space when ⌘Space is held), 1.3 Home paints on reopen, 1.4 truthful footer, 1.5 snippet browsing, 1.6 Quick AI error notice and stream follow, 1.7 clipboard feedback, 1.9 overlay fallback ground (luminance 0.57 → window background), 1.10 four destructive confirmations, 1.11 one Accessibility surface per request plus NSAppleEventsUsageDescription.
  - 1.8 was a false audit finding: navigableResults already returns [] outside search. Test kept as a guard.
  - Found by looking: prompt Cancel rendered black in dark mode; now textSecondary. docs/qa/2026-11-01-last-20/phase1/overlay-*.png.
  - Gate: 693 tests, 0 failures, 7 skipped; three lints pass.
  - Note: other sessions edit anvil/ and foundry-ad/ in this checkout concurrently. Stage exact paths.
- Phase 2 in progress (last-20 panel plan):
  - Done: 2.1–2.3 (d5a91fd) motion tokens, AppKit fade entrance, one row; 2.4 (2b487ab) destructive actions last behind a rule, flat keycaps, Radius.popover; 2.5 (e332b69) fixed 20 pt field, Shift-Tab inert, reopen keeps query selected, delayed loading hairline, no result count; 2.6 (bfc20d0) notices and widget strip moved below the list.
  - Deviation: 2.4 keeps the actions filter in the header field. Moving it into the popover needs a live focus check, and HID events are off-limits.
  - Deviation: 2.5 leaves Esc and arrows to the panel's own keyDown, which already handles them.
  - Renders: docs/qa/2026-11-01-last-20/phase2/. Offscreen renders cannot draw glass, so surfaces look tinted; judge structure only.
  - Done: 2.7 (acd7a9e) one empty state, cold-Home skeleton; 2.8 (9318169) ⌘1–8 favorites with hold-⌘ hints, ⌃N/⌃P, ⌘↑/⌘↓, page keys, Esc clears feature filter; 2.9 (755c070) VoiceOver selection announcements, spoken shortcuts, Increase Contrast alphas; 2.10 (7e02e0e) hand cursor only on links, whole-button hit areas; 2.11 (475f151) copy per D6; 2.12 (1fc2b4a) one toast timing.
  - Skipped in 2.7: "Spotlight isn't responding" notice. File search has a 250 ms deadline, so the notice would fire on ordinary slow queries.
  - Skipped in 2.8: onScrollVisibilityChange swap; the current visibility tracking works.
  - 2.9: AppKit will not construct a high-contrast appearance on request, so the theme reads NSWorkspace's Increase Contrast flag. Needs a live check with Increase Contrast on.
  - 2.11: applied D6 itself where the plan's item list contradicted it ("Take the Tour" stays a Title Case button, "Ranking reset" stays a sentence-case message). "Click" keycaps wait for 4.2.
  - Gate: 709 tests, 0 failures, 9 skipped; lints pass. Ratchet: corner-radius 124 → 117, pointing-hand 9 → 3. Under load from other sessions, one full run showed 4 failures that did not repeat.
  - Gate owed: live captures (light, dark, Reduce Transparency, Increase Contrast) and the fresh-context critic. Offscreen renders cannot draw glass, so a critic would judge render artefacts.
  - Next: Phase 3 onboarding.
- Phase 3 done (onboarding):
  - 3.1–3.5 (8d139c2): four steps (welcome, shortcut, bring your stuff, done). Try it lives on the shortcut step and completes only on a real launch (resultExecuted). ⌘ Space is taken only after "Take ⌘ Space"; "Use ⌥ Space" is the other answer. If ⌘ Space reaches the onboarding window, Foundry offers ⌥ Space or recording another chord. Alfred snippets import from the preferences bundle; Raycast imports from an exported JSON. AI is chosen quietly (Apple Intelligence, else a running local model). Done is a receipt plus a Starts-at-login switch (on) that registers on finish.
  - 3.6 (1a5c5ee) first panel after setup shows "Type an app, a file, or something you copied" once; the first launch shows "That’s it. ⌘ Space, a few letters, Return." once.
  - 3.7 (cd6bc8a) paste, snippet insert, window tiling and screen OCR ask for Accessibility or Screen Recording in the panel before acting; the item stays copied. New PermissionKind.screenRecording.
  - 3.8 (4dc9e5d) one notice slot above the footer; What's New 1.3 names ⌘1–⌘8 favorites (window layouts were not new, so the plan's copy would have been untrue); five tips after five launches, one a day, dismissals stick.
  - 3.9 (343d267) VoiceOver hears each step and the first launch; Skip setup contrast tested at 4.5:1 or better.
  - 3.10 (a7b3678) one-time "Start it at login?" notice on the second launch when the login item is off.
  - Not done in 3.9: chalk-lands-chalk in CastMark.swift. Another session has uncommitted edits to that file; left alone.
  - Removed from onboarding: the preferences, permissions and AI steps. ⇧⌘V is no longer offered during setup; it lives in Settings.
  - Gate: 733 tests, 0 failures, 9 skipped; lints pass. Renders in docs/qa/2026-11-01-last-20/phase3/.
  - Gate owed: a real-window recording of the cast and the Try-it success, a fresh-account keyboard-only walk timed to the first launch, and the blind critic. All need the user or a second account.
  - Flaky under load: AgentMonitorTests.testWorkspaceDiffIncludesStagedAndUntrackedFiles (passes alone).

### Execution log (plan docs/plans/2026-11-01-foundry-last-20.md)
- Task 0.1 done: anvil/scripts/qa.mjs + qa-routes.json + qa.test.mjs (3 tests pass). Baseline in docs/qa/2026-11-01-website/before/ and README.md there. Timings taken under load average 114 (about 16 agents); re-measure on a quiet machine.
- Task 0.2 done: first frame has no wordmark (CSS background loads late); SVG to WebGL swap pops brighter. Evidence before/trace/handover.png. Cold shader compile blocks the main thread (structural; no compileAsync).
- Fixed on the way: clipboard card hydration mismatch (pose values rounded). Console clean after.
- Task 0.3 running: Opus 5.5 critic writing docs/qa/2026-11-01-website/critique-before.md.
- Task A2 done: docs/brand/tokens.json -> app/foundry/tokens.css + tokens.ts (build-tokens.mjs, 5 tests). CSS role colours and the 3D scene read tokens. Pixel diff vs baseline: identical (a2-tokens/). Swift BrandTokensTests red on drift, green now. docs/brand/BRAND.md written.
- Not committed: the anvil/ tree carries the user's uncommitted 22-file polish diff, so per-task commits would sweep it in. Waiting on the user.
- Task A3 in progress (Split Mould): master `docs/brand/mark/mark.svg` on a 120 grid (5-unit coords, radius 10), hinted 16 px and mono variants; `anvil/scripts/mark.test.mjs` 5 tests. Site: `app/foundry/mark.tsx` in nav and footer, `app/icon.svg`, `apple-icon.png`, `favicon.ico` (hinted 16). App: `scripts/render-icon.swift` rewritten, AppIcon.iconset + icns re-rendered; menu bar glyph in `CastMark.swift`; `MenuBarMarkTests` red before, green after. build-app.sh + verify-packaging.sh pass.
  - Remaining A3: OG image, DMG background, onboarding cast still draws the old "f." tiles, live Dock/menu bar captures (needs the user's OK to run the app), BRAND.md construction section, app chalk ramp alignment.
- Critic HIGHs fixed: 768 shelf overlap, 768 memory text over tiles, first paint (SVG wordmark via next/image eager, ramp brightened, 160 ms crossfade). Evidence docs/qa/2026-11-01-website/after/ and c3-trace/ (README "After").
- Machine rebooted mid-session; scratchpad helpers lost. Servers: `next start -p 3124` from anvil/.
- User 2026-11-01: "we'll notarize the app don't worry. so remove the modal. fix the C3 and yeah make it 1.2.0". Done: modal deleted (B2 site side), version from ../VERSION (B1, shows 1.2.0), C3 chunked setup + compileAsync (longest task ~200-295 -> ~120-190 ms under load). Evidence in docs/qa/2026-11-01-website/README.md (B1, B2, C3). Notarization itself is the user's; publishing 1.2.0 is the user's.
- Next: C4 story details (critic MEDIUMs), A3 leftovers, B3-B5.

- Phase 4 in progress:
  - Found: every test that built CommandPanelState read and rewrote the real ~/.config/foundry/ai-chats.json and could write ~/.config/foundry/snippets.json. A new 4.1 test wrote two "Untitled Snippet" rows to the real snippets.json; they were removed (the file holds [] now, as before the run). Fix 93538e9: ConfigService.dataURL keeps data beside its config, so test configs get test data. Other default stores (ShellController, ActionRunner, CommandRegistry, SnippetExpansionService, LibraryProvider) still default to ~/.config and are only used with explicit stores in production.
  - 4.1 (4156dbe) ⌘K in Clipboard, Snippets, File Shelf via PanelClosureAction; listed shortcuts run without opening the list; Return on the shelf opens the selection.
  - 4.2 partial (06e448e) no Click keycaps; ⌘↵ copies the first Developer Tools output. Still owed: shelf ⌘A and space, Media ↵/⌫, Agents ↵, drop chooser keys.
  - 4.4 (6936445) Esc closes the snippet argument prompt first, then clears the Quick AI composer.
  - 4.3 (2f2eebe, 2e7b460) snippet import/export summaries; every copy confirms through notify(_:dismissed:): the HUD when the panel closes (emoji, clipboard ↵/⌘↵), the in-panel line when it stays (Developer Tools, Translator, Media "Copied link"). Deviation: no "Pasted" HUD; the pasted text landing in the target app is the confirmation. Suite 741 tests, 0 failures; user data unchanged (md5 before/after).
  - 4.5 (17acd79) Clipboard: filter chips with counts (empty kinds hide), Pause as FoundryActionButton, paused InlineNotice with Resume, count in the footer status slot, rows 40 pt / 26 pt icon / Radius.row, hover Paste + Remove, preview keeps Copy and Paste, merge/OCR/QR/shelf/open link in ⌘K, search covers source apps (bundle id). InlineNotice text is textPrimary now, glyph tinted (warning text was low contrast in light). Renders docs/qa/2026-11-01-last-20/phase4/clipboard-*.png. Deviation: no separate "Paste as Plain Text"; clipboard text payloads are plain already, so it would duplicate Paste.
  - 4.6 (59a00d5) Snippets: one duplicate-keyword warning (selected snippet's clash first), one expansion warning only when expansion is off or Accessibility is missing, with Open Settings (new SettingsDeepLink.snippets); Auto-expand switch and static secure-field line gone; rows show the first content line with the keyword as a mono badge; usage and "Edited …" in the editor footer (RelativeDateTimeFormatter, "just now" under a minute); editor 13 pt or 12 pt mono behind a toggle; ⌘N focuses the title (freshSnippetID); trash goes through the panel's confirmDeleteSnippet prompt (the view's own alert is gone); argument prompt on FoundryGlassSurface with PanelPromptOverlay's buttons. Renders snippets-*.png. Glass is transparent offscreen (actions overlay too), so the prompt surface needs a live look.
  - 4.7 (25049e3) Quick AI: blank chats are never saved and reopening reuses the one blank chat; the model menu no longer called setDefaultAIProfile (it did, a real bug) and now only sets the chat's model; empty Return is a no-op and Send un-emphasizes while empty; running steps show a mini ProgressView; chat list is keyboard-driven (↑↓, ↵, ⌘⌫ deletes, relative date) and lists only saved chats; composer 20 pt with the placeholder at the text inset in placeholderTextColor; "AI Settings…" on the retry row; empty state is the three suggestions. Render quickai-empty-*.png. Not done: the chat-list popover and the ⌘⌫ path need a live keyboard check.
  - 4.8 (d819f0c) File Shelf: header "3 Files" / "2 of 3 Selected"; BEN2 setup menu and the trash button gone (Clear Shelf… is ⇧⌘⌫ in ⌘K); background menu reads "Remove Background" and "Remove Background (Detailed)" with a "One-time model download" subtitle that downloads then runs; model removal lives in Settings › General with "Delete the background-removal model? You can download it again later."; drops onto the shelf shelve directly; the drop chooser has a selected row (↑↓, ↵ on the selection, ⌘1–4 keycaps); multi-image OCR runs in order and copies once (it raced before, last task won). Deviations: folders still shelve (the code accepts them), so the rejection copy names the real case: "Only files can go on the shelf. Drop them from Finder."; multi-image OCR copies to the clipboard like single OCR instead of writing a text file. Renders shelf-*.png, drop-chooser-dark/light.png.
  - 4.16 (4330f2e) Camera cut: view, state, capture service, provider, OpenCameraAction, route, NSCameraUsageDescription, camera entitlement (Foundry.entitlements is now an empty dict; checked that an empty dict signs and passes `codesign --display --entitlements :- | plutil -lint -`), README line. 530 lines deleted. Release notes for 1.3.0 (Phase 7) must say Camera is gone.
  - 4.9 (a3535e9) Conversion: the button's shortcut is ↵ when idle and ⌘. while converting ("Cancel ⌘."), so a second Return no longer cancels; status renders through InlineNotice with a level from the phase (InlineNotice gained .success); drop target fillSelected + selectionBorder, accent glyph and progress tint; Name and Longest Edge are native menus that show real names ("photo-converted", "photo-2026-11-01") and "Original / 4096 px …"; result rows fit the 30 pt icon buttons. Deviations: the Convert button keeps a token fill with a hairline at Radius.control, because FoundryGlassSurface(.prominentControl) blanked the whole settings card offscreen (verified by swapping it back); chips truncated, so the two long rows became menus. Render conversion-*.png.
  - 4.10 partial (deadf59) Media: favicons follow the Site icons switch (D7; tested that no icons.duckduckgo.com URL exists when off; the switch subtitle now names Media Downloads); "\(n) links aren’t supported and were left in the box."; selection is RowBackground instead of an accent stroke; radii on tokens. Owed: composer into the header slot, folder/Change into ⌘K, "Supported links" into the empty state, keyboard-first selection (selection is view @State today, so ↑↓/↵/⌫ need it moved into MediaDownloadManager), completion through showActionFeedback (kept the card: it carries Reveal and Open).
  - 4.11 (see git log) Translator: the language pair persists (injected UserDefaults; tests use their own suites) and survives reset; the spinner starts after the debounce; status row holds its height; errors render as InlineNotice and offer "Try Apple Intelligence" only for backend failures; "Replace" with help "Replace the selection in \(app)"; pane radius on tokens. Owed: Detect source (NLLanguageRecognizer) and the list from LanguageAvailability.
  - 4.12 (148426b) Emoji: cells have section-scoped ids ("recent:🔥", "all:🔥"), one flat navigable list so arrows reach Recent; cells render the tone-applied value; Return pastes through directPasteService (copy fallback with a HUD, Accessibility prompt path copies and stays); footer "Paste ↵ · Skin Tone ⌘T" with the selected emoji's name in the status slot; RowBackground cells, no hover scale; FoundryEmptyState "No emoji for “query”"; columns fixed at 12 (control and cycle removed). Render emoji-*.png.
  - Translator follow-up in the same commit: the pair moved from UserDefaults to LocalStateStore (it leaked between tests through .standard); opening Translator into the current source language swaps instead of producing French→French.
  - 4.13 (0126e33) Developer Tools: header "Developer Tools" with a tool chip (FeatureTitle gained `detail`), values truncate in the middle with the full value in help (no 0.55 scaling), destructive token, radii and fills on tokens. Calculator: "=" for arithmetic and "→" for conversions, curly quotes in "Use “…” with…", the dead gear gone, scale floor 0.6, the trimmed query instead of "Calculation". Not done: one chip row (the 4×2 tool grid stays) and Base Conversion's surface.
  - 4.14 (699f85c) Agents: the in-body title row is gone (refresh sits beside the tabs; "N active" in the footer status); tabs list only providers with sessions; a warning only when the socket is off, with Open Settings (new SettingsDeepLink.agents); rows that cannot jump stay enabled and explain on click ("Codex doesn’t support jumping to a session yet."); empty state "No agent sessions yet" with "Open Agent Settings"; Running reads as Working; the "Recent" status label hides. The agents render showed the user's real session titles, so it is not committed and the render was removed from the test.
  - 4.15 partial (6af312e) Settings: the window keeps its saved frame (center() ran after setFrameAutosaveName and overrode it; test fails on the old order, passes on the fix); the last pane is remembered (@AppStorage "settings.lastPane"); "Pop to root" → "Return to Home after" with "Reopening sooner than this resumes where you left off." (search index keeps "pop to root" as a keyword); "Rectangle-style" → "Suggested shortcut"; clipboard item limit is a menu of 100 / 250 / 500 / 1,000 / 5,000 (keeps an unusual current value). Owed from 4.15: sidebar List in NavigationSplitView, commit-on-blur fields, recorder keys and focus ring, widget reorder opacity, quicklink Undo toast, Appearance merged into General, 140 pt control column, SettingsGroup radius/stroke, error indent, D6 casing sweep, native delimiter/Return controls, Agents tracked sessions removal.
  - 4.15 done (898aaf1) Settings rail is `List(selection:)` in a `NavigationSplitView` (sidebar 210 pt, pane title in the toolbar, full-size content); Appearance merged into General as Panel contrast (search anchor general.contrast); Agents tracked sessions removed; recorder: Space/Return record, esc cancels, ⌫ clears where clearing exists, focus ring, accessibility button (ShortcutRecorderTests); fields commit on blur (CommitOnBlur); quicklink removal shows Undo; widget controls rest at 0.5; one 140 pt control column (Control.settingsColumn); SettingsGroup radius Radius.row with separator stroke; error indent 82; delimiters are checkboxes, Return key a segmented picker; D6 on the last four sentence-case buttons. Settings renders now use `screencapture -l` on a real window (the sidebar table does not draw offscreen). Suite 763, 0 failures; ratchet corner-radius 54, opacity-expression 12.
  - 4.2 + 4.10 done (d2e806c) File Shelf: ⌘A selects all (⌘A goes to the field only when it has text), Space is Quick Look, footer shows it. Media: the link field is the header (featureSearchField), selection lives in MediaDownloadManager (arrows walk active then recent), ↵ downloads, or opens/retries the selected row when the field is empty (footer label follows), ⌘⌫ removes, ⌘K lists Open/Show in Finder/Retry/Cancel/Open Source Page/Copy Link/Open Download Folder/Change Download Folder…; "Supported links" sits under the empty state; speed and count moved to the footer status. Agents: arrows select (provider filter now in AgentMonitorState), ↵ opens or explains. Kept: Media completion card (it carries Reveal and Open).
  - Surprise fixed in d2e806c: `UsageRankingStore` defaulted to the real `~/.local/share/foundry/usage.json`, so 37 test sites read and wrote the user's ranking file (it holds test records such as `test.background-download` with 132 opens). The URL is now a required argument; tests use `UsageRankingStore.scratch`. The golden ranking table had been recorded against that live history; four cases re-recorded on a clean store (sys, center, trans, settings). On a clean store "trans" ranks "Open Transfer or Reset Settings" above "Translate" and "settings" no longer shows "Open Foundry Settings" in the top 3. The test pollution already in the user's usage.json was left alone (user data). The md5 check now covers usage.json too.
  - 4.11 + 4.13 done (see git log, "Phase 4.11/4.13") Translator: "Detect Language" is the default source (NLLanguageRecognizer), the menu label reads "French (Detected)", swap turns the detected language into the target, undetectable text says so. Deviation: the language list stays the 12-language table; LanguageAvailability needs an identifier-keyed language model (the stored pair and parser are name-based) and is macOS 15 only. Developer Tools: one chip row with short names (Base, Bits, Base64, JSON, Case, Timestamp, Words), full name in the header chip and help; section titles dropped for one hint line; Base Conversion sits on the shared surface; even 14 pt padding. Suite 769, 0 failures.
  - Phase 4 complete except the gate items that need the user (live captures, blind critic).
  - 5 done: all cuts landed in Phase 4; 5.1 (de2485e) deleted 114 lines that only served removed surfaces. Kept Brand wordmark/legend tokens (other session's icon work is live there).
  - 6 done (809faed) radius/height/opacity/colour literals replaced by tokens (Radius.tile; Control.track/glyph/line/mini/compact/field/row/rowTall/rowDouble/editor/preview; Panel header/footer; hairline; Backdrop washes; onLightFaint); 26→24, 28/32→30, 34→36, 42/44→40, 46→48 snapped; selectionBorder and fillEmphasis 0.15; sectionHeader = textSecondary; agent working = success, review/completed = accent; rowTitle 13; strip floor 10, small labels 11 semibold; pointer cursor removed (no links used it); ratchet deleted, new frame-height rule; lint passes with no allowances. Suite 769, 0 failures. Renders in docs/qa/2026-11-01-last-20/phase6.
  - 7.1 (452c93d) Home clipboard widget reads the clipboard history instead of polling the pasteboard every 10 s (WidgetBoardTests); after-benchmarks in docs/benchmarks/2026-11-01-last-20-after.md: search.immediate p95 14.6–16.6 ms across four runs vs 15.61 ms for the baseline commit re-run the same afternoon (bar ≤ 16 ms: on the bar, inside this machine's noise). The disk filled during the paired run (machine at 100%, ~750 MB free; not this work's scratch, 14 MB); the baseline worktree was removed.
  - 7.4 (0f23e20) VERSION 1.3.0, docs/release-notes/1.3.0.md (Camera removed is the first line). Committed, not pushed: pushing VERSION starts the release workflow. README has no Camera or Appearance mention, so no change. docs/HANDOFF.md not touched: another session has uncommitted edits there.
  - Perfection report:
    - The 80% version (before): working features with per-surface chrome, a 7-allowance lint ratchet, Camera, an Appearance pane, tracked sessions in Settings, mouse-only Media/Agents, tests writing the user's ranking file.
    - The last 20%, with evidence: Phases 1–6 lines above; renders in docs/qa/2026-11-01-last-20/{phase1,phase2,phase3,phase4,phase6}; suite 770 tests, 0 failures; design lint 0 violations with no ratchet; user data md5 unchanged after every full run (snippets.json, ai-chats.json, usage.json).
    - Still imperfect, and why: (1) no live captures in light/dark/Reduce Transparency/Increase Contrast, no blind critic, no four-user walks, no panel.show/idle CPU/RSS numbers: each needs the app on screen or a second account, and the user was at the machine. (2) Search latency p95 is on the 16 ms bar; needs an idle-machine re-run of both commits. (3) Translator languages stay a fixed 12. (4) Media keeps its completion card. (6) The user's usage.json still holds test records written before d2e806c.
  - Headers (user chose normal case over the 1.1 tracked caps): uppercase and tracking removed from section and field labels in Calculator, Window Layouts, Conversion, Developer Tools, drop chooser, Home, Agents (now FoundrySectionHeader); file-type badges keep caps. Snapshot references re-recorded and inspected. Suite 770, 0 failures.
  - Phase 4 status: 4.1, 4.3, 4.4, 4.5–4.9, 4.12, 4.14, 4.16 done; 4.2, 4.10, 4.11, 4.13, 4.15 partial (owed items listed on each line above). Suite 760 tests, 0 failures, 10 skipped; lints pass; ratchet corner-radius 116 → 58, opacity-expression 17 → 14, named-colour 8 → 7. User data checked unchanged (md5 of ~/.config/foundry/snippets.json and ai-chats.json) after every full run.
  - Phase 4 gate owed: live captures of every surface (offscreen renders cannot draw glass; the drop chooser, argument prompt and actions overlay surfaces render transparent), the blind critic on the set.
  - Next: Phase 4 owed items above, then Phase 5 cuts, Phase 6 token collapse, Phase 7 gauntlet (version 1.3.0, release notes that say Camera is gone).
- User 2026-11-01: "finish the plan". Answers: MIT licence; live app captures "Not now"; skip /vs/raycast.
  - Done: B3 /proof, B4 /privacy + LICENSE, B5 /changelog + feed, A4 /brand (helpers, Sonnet 5.5 and Opus 5.5); C2 ⌘K palette + section hashes; C4 critic MEDIUMs except the calculator grid (user decision); C5 focus ring, theme colour, colour scheme, 404 hint; C6 harden checks; A3 OG image and onboarding cast; D3 HANDOFF website section and design-doc decisions.
  - Evidence: docs/qa/2026-11-01-website/README.md "Final". Home Lighthouse performance 71 to 75 under load; budget not met.
  - Surprise: anvil/node_modules was deleted twice by something outside this session (disk 99% full, 7.7 GB free). Reinstalled with `npm ci` both times.
  - D1 critique: "ship with fixes"; both HIGHs, both MEDIUMs and the LOW fixed and recaptured (README "D1"). Open: critic #9, #11, #14.
  - Nothing committed; anvil/ still mixes the user's uncommitted diff with this work.

## Branch consolidation (2026-11-03)
- main now holds website-tile-world (merge 6bf3fdf3) and polish/timezone-and-audit (merge 8a6af88a). Checks: three lints pass; swift test 806 tests, 0 failures (baseline before the merges: 770).
- Deleted locally: raycast-quality-overhaul, local/p5-snippet-preview, imgbot, minicmp/old-mini, cline and codex checkpoints, tags pre-squash-backup, v1, v1.0.0, v1.1.0, and the mini/* and origin/* tracking refs (except mini/polish). GitHub and the mini Mac still have their copies.
- Backup: ~/Honey/.backups/anvil-2026-11-03/ (refs.bundle, refs.txt, wip-worktree.tgz, wip.diff). Restore a branch with `git fetch ~/Honey/.backups/anvil-2026-11-03/refs.bundle refs/heads/<name>:refs/heads/<name>`.
- Left untracked on purpose: launch-film/, .jury/, inspo/, docs/qa/2026-11-01-website PNGs, docs/brand/concepts, literal film media.

## Paper-cut sweep (2026-11-10, main thread, no subagents)

User installed a build of main over 1.1.0 and reported five rough edges, then asked for all such edges to be found and fixed.
Tools: `Tests/FoundryTests/ZZBatteryTests.swift` (prints top results for a query list, `FOUNDRY_BATTERY=<file>`) and
`Tests/FoundryTests/ZZGalleryTests.swift` (renders the real panel per query, `FOUNDRY_GALLERY_DIR`, `FOUNDRY_GALLERY_QUERIES="a|b"`).
Both are scratch, untracked, and must be deleted before the final commit. Offscreen renders paint the glass backdrop red; ignore the colour.
An `async` XCTest never runs SwiftUI `.task` bodies during `RunLoop.main.run`; render from synchronous tests.

Reported by the user:
- [x] A1 Clipboard image preview never appeared (`7b4178b`).
- [x] A2 Widget strip is back under the search field (`ef9033c`, seen in a gallery render).
- [x] A3 "time in SF now" and other filler-word forms answer (`ef9033c`, `testFillerWordsAroundAPlaceStillAnswer`).
- [x] A4 Time conversions use the answer card (`ef9033c`, seen in a gallery render).
- [x] A5 Settings has its own rail and pane title again (`d51f64b`, every pane rendered offscreen, dark and light).

Found by the sweep:
- [x] B1, B2 Answers rank first (`ef9033c`, `testAnAnswerRanksFirstAndOnlyFallbacksFollowIt`).
- [x] B3 Unit conversion with a target, from one table in `UnitConversion.swift` (`aa79cc2`, `testConversionToANamedUnit`).
- [x] B4 "15% of 200", "10 mod 3", "1,000 * 3", worded operators (`aa79cc2`, `testWordedArithmetic`).
- [x] B5 Fallbacks follow an answer instead of unrelated commands (`ef9033c`).
- [x] B6 Time rows: no "Wed" prefix, one default row when local is on UTC (`aa79cc2`, `testALocalZoneOnUTCGetsOneDefaultRow`).
- [x] B7 Home Ask AI row has no subtitle (`ef9033c`).
- [x] B8 Quit rows skip Foundry itself and show the app icon (`aa79cc2`). In the test process the installed Foundry still lists, which is correct.
- [x] B9 Hashes, URL coding, bare timestamps, colours, "255 to hex"; value rows are labelled (`aa79cc2`, `DeveloperToolsProviderTests`).
- [x] B10 "force quit <app>", "volume 50", "my ip", "fullscreen" (`aa79cc2`). "hide all" and bare "kill" followed in D1.
- [x] B11 A copy made while Foundry is frontmost records no source (`27bba06`, `testACopyMadeWhileFoundryIsFrontmostHasNoSource`).
- [x] B12 Currency rate date sits in the card header (`ef9033c`).
- [x] B13 Fuzzy matching was too loose ("kill" -> Maximize Window). Subsequence only on titles from a word start, typos from five letters (`aa79cc2`).
- [x] B14 Three SF Symbol names did not exist, so rows drew blank icons. `SymbolNameTests` checks every name (`aa79cc2`).
- [x] C Visual pass from offscreen renders: every Settings pane, clipboard, snippets, emoji, shelf, conversion, dev tools, media, Quick AI,
  window layouts, onboarding (`27bba06`). Fixed: clipboard rows truncated in the middle, links said "Text", tags placeholder clipped.
  Overlays (actions menu, drop chooser, confirm prompts) draw without their glass offscreen, so their overlap was not judged.

Second pass, "fix all of this" (`3cc01e7`). Every item that was left open is done:
- [x] D1 "hide all" finds Hide All Apps; bare "kill" lists running apps as Force Quit rows (`testHideAllFindsItsCommand`,
  `testQuitQueriesNameAnAppByWordPrefix`).
- [x] D2 "5 ft 10 in to cm", 5'10" and "1h 30m 15s in seconds" add up before converting (`testSeveralUnitsOfOneKindAddUp`). The card
  shows "5 ft 10 in" whole (`testAnswerCardSplitsEachKindOfAnswer`).
- [x] D3 Date maths: offsets and counts answer with a Date card (`DateMathTests`, `Sources/Foundry/Features/Time/DateMath.swift`).
- [x] D4 Overlays judged from real captures. A borderless panel placed below the desktop window level renders its glass and
  `screencapture -l <windowNumber>` reads it, so nothing shows on screen. The capture test was scratch and is deleted. Found and fixed:
  - A prompt replacing another with more fields crashed with "Index out of range" (`testAPromptThatReplacesAnotherStartsFromItsOwnFields`).
  - The actions menu was always 320 pt tall. It hugs its rows and scrolls with an 8 pt margin past 320.
  - Opening the actions menu on home dropped the section headers and reflowed the list. Home keeps its layout.
  - The footer in clipboard mode ignored the open menu, and was empty for the drop chooser (`testAnOpenActionsMenuOwnsTheFooterInEveryMode`).
  - Prompts and the drop chooser dim the panel behind them. A click on the dim cancels.
  - Light mode drew destructive text in pale pink. Status colours have light values; `prompt-confirm-light.png` is re-recorded.
  - A first run listed five commands alphabetically. It leads with the main tools (`testAFreshHomeLeadsWithTheMainTools`).

Third pass, from the user's screenshots (`10de478`):
- [x] E1 Home: the first row sat against the widget strip with no "Recent" header. Selecting row one called `scrollTo(row, .top)`,
  which hides the header and padding when the list is taller than the panel. Reproduced in a capture with ten rows, fixed by
  scrolling the whole list to its top or bottom for the first and last rows, and by using scroll content margins.
- [x] E2 Settings looked flat grey. Offscreen renders had hidden this; a real capture matched the user's screenshot. It now uses
  `FoundryBackdrop` like the panel. Quicklinks rows are rebuilt. Every pane was captured in a real window, dark and light.
- [x] E3 "Settings opens with the launcher": `showPanel` activated the app, which raises a Settings window left behind another app.
  It now skips activation while another Foundry window is up. Not driven live and not covered by a test.

Not verified live: the Mac mini is locked. The panel states above were captured from the real view with real glass, but no key was
pressed in a running app. Hide All Apps and Force Quit were not executed.
`./scripts/check.sh` passed and `swift test` ran 930 tests with 0 failures on `10de478`.
`/Applications/Foundry.app` is a build of `10de478` (the previous install is in `~/.Trash/Foundry-pre-10de478-*.app`).

Fourth pass, the Settings window to 100% (`d2325cd`), from the user's screenshot of the live window:
- [x] F1 Windows behind Settings showed through the cards. Settings is opaque on `FoundryTheme.windowGround`. E2's backdrop is undone.
- [x] F2 The window stayed 680 x 480 although `minSize` was 720 x 560. Cause: the hosting view replaces the window's minimum with the
  SwiftUI content's own on first layout (it read 379 x 138, then 0 x 0 with `sizingOptions = []`). The content now states the minimum
  and the hosting view has no safe area. The window also opened at 720 x 560 instead of 820 x 600
  (`testTheWindowKeepsItsDefaultAndMinimumSizeOnceItsContentLaysOut`, red first). A traced 680 x 480 saved frame restores as 720 x 560
  with the title bar in place.
- [x] F3 Reopening Settings on the Commands pane showed "No commands match this search": only a rail click loaded the catalog
  (`testReopeningOnTheCommandsPaneLoadsItsCatalog`, red first). Found from a capture, not from the screenshot.
- [x] F4 Stock blue switches, checkboxes, bordered buttons, menu pickers and the stepper are replaced by `SettingsControls.swift`
  (`FoundrySwitchStyle`, `FoundryCheckboxStyle`, `SettingsButtonStyle`, `SettingsMenuPicker`). A labelled switch had no VoiceOver name
  until it got a real toggle as its accessibility representation (`testEverySwitchAndCheckboxIsNamedForVoiceOver`, red first).
- [x] F5 Layout: cards are a fill without a border, the title shares the search field's line, the first card is level with the first
  rail item, row padding is 12 everywhere, the scroll edges fade, icon buttons share `SettingsIconButton`, a permission's status sits
  beside its name. Copy that wrapped at the minimum width is shorter.
- [x] F6 The rail selection glides (`matchedGeometryEffect`, `Motion.state`, off under Reduce Motion). Checked mid-flight in a
  capture with the animation slowed to 6 s; the detail pane does not animate.

Every pane was captured in the real window at 720 x 560 in dark and at 820 x 600 in light. The capture test was scratch and is deleted.
The segmented control (Snippets) and the slider (General) stay stock; both render neutral.
Not verified live: hover, press and focus states, the open picker menu, and VoiceOver reading the panes. The Mac mini is still locked.
`./scripts/check.sh` passed and `swift test` ran 933 tests with 0 failures on `d2325cd`.

Fifth pass, rough edges in the launcher itself (2026-11-10). Driven live on the locked Mac mini (en_GB, no battery):
a scratch test drove the real panel with in-process key events and captured each frame. The driver is deleted.
- [x] R1 The user's own zone label depended on the system locale: "Your time (GMT+5:30)" instead of "IST" on en_US, "GMT-7"
  instead of "PDT" on en_GB. The local zone, UTC and cities found by zone identifier now use the curated abbreviations
  (`testTheLocalZoneUsesItsCuratedAbbreviationInEveryLocale`, `testACityFoundByItsZoneIdentifierUsesTheCuratedAbbreviation`, red first).
- [x] R2 Home showed a Battery widget reading "—" on a Mac without a battery. Home leaves it out there; the saved layout keeps it
  (`testHomeLeavesOutTheBatteryWidgetOnAMacWithoutABattery`). Seen in a mini frame.
- [x] R3 The clear button followed the query, not the field: it showed over an empty actions filter and cleared the query under
  the open menu. It now follows the field's own text. Seen in mini frames with and without a filter.
- [x] R4 The footer said "Copy Result" for the calculator and "Copy" everywhere else. It says "Copy".
- [x] R5 "settings" put Foundry's own Settings below the fold. The command is "Foundry Settings" and ranks second
  (golden table, red first). Third on the mini, where the System Settings app sits second.
- [x] R6 Return or Copy on an empty Snippets list asked for Accessibility with "Your item is copied", or said "Copied snippet".
  Neither happens now (`testInsertingFromAnEmptySnippetListAsksNothingAndCopiesNothing`, red first). Found in a mini frame.
- [x] R7 Return on an empty Clipboard History showed a red "Select an item to paste." under the empty state. It does nothing now.
Left: "1/0" gives no answer; the launch-time layout-recursion warning and two first-responder warnings in the log are not traced.
Not verified live: Esc and arrows in feature modes, which go through SwiftUI commands that need a key window; the mini is locked.
`./scripts/check.sh` passed and `swift test` ran 937 tests with 0 failures.

Sixth pass, the parts not swept before (2026-11-10 and 11): Ask AI, File Shelf, Quick Look, compact mode, light and dark, onboarding.
Driven live on the locked Mac mini with the same scratch driver, now with a shell that forwards Quick Look, compact resizing and notices.
- [x] S1 Quick Look did not follow the selection, in the File Shelf or in search: the panel kept the first file. The shelf now reports
  selection changes (`testQuickLookFollowsTheSelectedShelfFile`, red first) and the preview panel reloads its item. Seen live:
  the preview went from "Holiday photo.png" to "Meeting notes.txt".
- [x] S2 Empty File Shelf, Clipboard History, Snippets and Convert File showed footer hints that do nothing. They show Home
  (Snippets: New Snippet and Home). Seen live.
- [x] S3 Onboarding's progress tiles and Back sat 10 pt lower on the shortcut step. The footer has one height
  (`testRenderEveryStep` now compares the tile row on every step, red first).
- [x] S4 The emoji grid left 72 pt empty on the right. It has 13 columns and spans the panel. Seen live.
- [x] S5 Translate reopened with "English (Detected)" over an empty field (`testResetForgetsTheDetectedLanguage`, red first).
- [x] S6 Shelf paths truncate in the middle, Convert File's hint has no dash, and onboarding's login switch is off when a login item
  is not available.
Checked and left: Ask AI answers through Apple Intelligence; compact mode collapses and expands; every screen reads in light and dark.
Left: "quit" rows rank by title length, like every list. Not verified live: hover states, arrow keys and Esc through SwiftUI commands.
`./scripts/check.sh` passed and `swift test` ran 939 tests with 0 failures. The MacBook was under load from other work during the run.
