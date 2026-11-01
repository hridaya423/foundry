# Installer, onboarding, and logo overhaul

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

## Session 2026-10-21 (handoff /tmp/foundry-handoff-2026-10-21.md)
- Shortcut step redesigned: the two giant chalk slabs are now a full MacBook keyboard in ink, with the chord cast in chalk (orange once the panel runs). Real key presses dip the keys. The "Record a new shortcut" button became one Raycast-style field: "Shortcut ⌘ Space · Change"; recording lights held modifiers live. Mock: Paper artboard "Onboarding · 2 Shortcut v2". Evidence: /tmp/fq/v2/*.png (offscreen), /tmp/fq/r1.png (real QA app), /tmp/fq/states/{recording,hot}.png.
- Unsigned-build warnings: already gone from the tree (DownloadNotice quarantine prompt, website modal + CSS, README). Verified by grep.
- build-app.sh now prefers the Developer ID identity (it used to take "Apple Development", which notarization rejects).
- package-dmg.sh: the mount-point parse took the last line of `hdiutil attach`, which is a partition row with no mount, so the branded layout silently fell back to a plain DMG. It now takes the `/Volumes/` row.
- Signed: build/Foundry-1.2.0-build-1.dmg (app + DMG, Developer ID, hardened runtime, timestamp). `codesign --verify --deep --strict` passes; `spctl` says "Unnotarized Developer ID" as expected. Finder reports the DMG window at 540x360. A screenshot of it was not possible because Stage Manager kept moving the window.
- Checks: swift test 656 tests, 0 failures; lint-design, lint-l10n, lint-lines pass.

- Round 2 (user feedback): Try it now teaches open + close: "Now press it" -> "Now press it again" -> closing the panel is the success (orange keys, warm glow, auto-advance). It used to leave the panel open. `completeTryIt()` replaces `panelDidRunCommand()`. Launch at login explains itself when unavailable (test build). AI step: no Continue; Return picks the recommended row, marked with a ↵ chip. Steps slide in the direction of travel (`OnboardingState.movedForward`). Checks: 656 tests, 0 failures; three lints pass.

- Round 3: "Press it again" now shows in the panel's search placeholder (`CommandPanelState.searchHint`), because the open panel covers the onboarding window. Motion: one token set `FoundryTheme.Brand.Motion` (ease-out 0.23,1,0.32,1; press 120 ms, state 220 ms, enter 450 ms, 6 pt rise, 50 ms stagger), no springs or overshoot left in onboarding; steps crossfade with a 4 pt blur. Welcome redesigned (Paper "Onboarding · 1 Welcome v2"): editorial left grid, two-line large headline bottom-left, the "f." mark top-right in chalk keycap tiles with sides; cast is quieter (6 pt rise, no scale, ~1.2 s). Filmstrip: /tmp/fq/w/strip.png; render: /tmp/fq/w/s0.png. QA copy deleted at the user's request; their Foundry is running. Checks: 656 tests, 0 failures; lints pass.

## Round 4 bar ("holy shit", not "clean")
- Welcome cast reads as real molten metal: white-hot landing, cooling ramp, emitted light on the ground that decays with the heat. Ember stays on the full stop.
- Chalk surfaces respond to the cursor as a light source (smoothed, subtle).
- Judged from a video of the real window, frame by frame, not offscreen stills.
- No showy motion: every movement still answers "why".

- Round 4 done: molten cast (heat model `MarkTiles.heat`, face cools white->yellow->orange->amber->chalk via `faceCoolRamp`, red only in the bloom; floor light decays with heat; the full stop keeps an ember). Cursor light on the mark (`CursorLight`: eased pointer, falloff + sheen); not verified live because synthetic mouse events need Accessibility. Bug found by live video: the window can open behind the frontmost app, so the opening played unseen; onboarding content now waits for the window to become key (`windowSeen`). Evidence: /tmp/fq/w/live2.mov, /tmp/fq/w/hot.png, /tmp/fq/w/rest.png, /tmp/fq/w/strip-final.png.

- Round 4 rejected by the user ("sloppier"): molten cast and cursor light reverted to the round-3 cast. Kept: the windowSeen fix.
- Round 5 bar: Raycast, Linear desktop, Things 3, Apple first-run. Restraint, exact type, one spacing scale, every state designed, quiet motion. Blind critic (Sonnet 5.5) running on /tmp/fq/a/*.png. Own findings so far: headline-to-content gap 44 vs 36 (Done); list surface diagonal gradient bands.
- Round 5 fixes (from critic r1 + own findings): one footer on every step (progress left, Back + primary right, primary label min width so Back holds still); "Skip setup" top-right, dimmed (`Brand.faint`, `BrandQuietButtonStyle(dim:)`). AI step is a real choice: four rows with `BrandSelectionMark`, recommended preselected, "No AI" row, Continue confirms via `chooseAI`. ⇧⌘V clipboard toggle moved from Done to Preferences. One `listGap` (36) under every headline. Keyboard: number row and top fade removed, sits 180 pt down. Shortcut lead no longer repeats the chord. Try-it link reads as a link; primary says "Skip" until the shortcut is pressed. Flat list fill (`rowBottom` deleted). SF "return" glyph in the CTA. "Allow…". Done rows 56 pt. Evidence: /tmp/fq/b/*.png, /tmp/fq/b/sheet.png. Checks: 656 tests, 0 failures; three lints pass. Blind critic r2 ran (scores 6–8/10); its fixes applied:
  - The CTA is a fixed 172 pt, so Back never moves.
  - Try it: Continue is a quiet outline with no Return until the shortcut works.
  - AI: squared radio plus a selected-row fill (`Brand.rowSelected`); titles "Local model", "Cloud provider".
  - Done hides "Ask AI" when AI is off.
  - Launch at login copy now matches Settings.
  - The Welcome lead reads "Everything on your Mac, one keystroke away." and sits on the mark's base.
  - The keyboard top is level with the lists, and "Change" is plain text.
  - Rows are 14 pt vertical padding; disabled rows are at 0.6 opacity.
  - Evidence: /tmp/fq/c/*.png and /tmp/fq/c/sheet.png. Checks: 656 tests, 0 failures; lints pass.
- Live recording attempt failed: the user was using the Mac, so other windows covered the onboarding window, and the synthetic ⌘ Space went to the frontmost app. Recording deleted. Do not run the live rig while the user is at the machine; ask first. Still open: the critic's "Permissions dead space" and "Try it repeats the keyboard" points.

- User-reported bug, fixed:
  - Cause: the onboarding view honoured the titlebar safe area. The 880x580 view sat 28 pt low, a bare-window band showed above it, and the bottom margin was squeezed to about 21 pt.
  - The "32 pt render artifact" in every earlier snapshot was this bug, wrongly dismissed.
  - Fix: `.ignoresSafeArea()` on the root view.
  - OnboardingSnapshotTests now hosts the view the way OnboardingWindowController does. It always runs, and only writes images when the dir is set. It asserts the top and bottom edges are brand ground. It was red without the fix and is green with it.
  - Evidence: /tmp/fq/d/sheet.png. Checks: 656 tests, 0 failures; lints pass.
  - The user's Foundry is restored and the QA copy deleted.

- Panel vs installed 1.1.0 (/Applications, built 2026-10-06 at 71a4726, 61 commits behind). Captures: /tmp/fq/panel-installed.png, /tmp/fq/panel-branch.png.
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

## Remaining
- Notarize: no notarytool credentials on this Mac. Needs `xcrun notarytool store-credentials foundry --apple-id <id> --team-id DV6NC6KRYL` from the user, then `NOTARY_PROFILE=foundry zsh scripts/notarize-dmg.sh build/Foundry-*.dmg`.
- Rebuild and install to /Applications so the user's Foundry gets these changes (asked, not yet confirmed).
- Nothing open from the brief. Not tested live: the Spotlight, Raycast and Alfred takeover, because nothing holds ⌘Space on this Mac (unit tests cover it).

## Website gauntlet (anvil/, vs igloo.inc), 2026-10-22
- The first loop (jury round 0 plus gauntlet rounds 6 to 15) was discarded at the user's request: its critic counted motion, and the result read as slop. anvil/ was reset to 97ee8f1. The discarded version is in .jury/taste/snapshots/foundry-before-taste.tgz.
- New loop: taste first, against igloo.inc, with critics who judge restraint and name what to remove. No /jury skill. Live log: .jury/taste/progress.md.
- Servers: production `npx next start -H 127.0.0.1 -p 4471`. Recorder tools in ~/.cache/jury (record.mjs, still.mjs, fullpage.mjs).
- Open: metadataBase domain still to confirm with the user before deploy.

## Port from old mini line (d1d7323, pinned at refs/minicmp/old-mini), 2026-10-23
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
Visual QA pass (offscreen NSHostingView renders, temp test since deleted, /tmp/fqa): fixed the Quick AI model menu (borderlessButton ignored its style, so it read bold white), "1 snippets" (now inflected), the "~" title in File Search (now the folder display name), the truncated `f` empty-state hint, and the dimmed empty script output.
Verification: swift build clean; swift test 677 tests, 7 skipped; 6 of 7 full runs had 0 failures, 1 run had 1 failure that did not repeat and was not identified; lint-design, lint-l10n, lint-lines pass. Not committed.
Open: SelectionSnapshot has no dedicated test; "Forever" retention is 3650 days.

## Website Awwwards pass (anvil/), started 2026-10-23
Source: the review in this session (critic: separate Opus 5.5, scores D6 U5 C7 Ct5). Baseline shots: /tmp/anvil-shots (ephemeral). Server: `npx next start -H 127.0.0.1 -p 4471` in anvil/. Playwright lives in ~/.cache/jury (run shoot.mjs with cwd there).
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
- [x] QA pass 1 + fresh critic (Opus 5.5, shots /tmp/anvil-shots4): D7.5 U6.5 C7.5 Ct7.5, overall 7.2
  Fixed from its list: clipboard exit lift removed (heading slid under phone nav), CTA hover is a rising cream fill, skip link on every page, focus reveal jumps the spring (invisibleFocus 0), 404 title + shared SiteHeader/SiteFooter (app/foundry/site-chrome.tsx) on 404 and methodology, phone shelf tabs on one line, AI tool label "Draft, rewritten with Writing profile".
  Declined: "24 × 18" caption kept (it explains the 432 frame); inline "Foundry source" link exempt from target size; DPR not raised on phone (FPS cost); no page transition added.
  Pass-2 evidence (/tmp/anvil-shots5): audit 0 FAIL 0 WARN; skipLinkFirst true on all pages; invisibleFocus 0; axe 0; home colorOnly 0; 404 returns status 404.
- [x] QA pass 2 + fresh critic (Opus 5.5, shots /tmp/anvil-shots5): D7 U7 C7.5 Ct8, overall 7.2; Semantics 8, A11y 8, WPO 8, Markup 8, Animations 7, Responsive 7
  Fixed: tool captions switch input -> result (calculator caption only on 432, AI "Draft" -> "Writing profile · sample response", video "Video link" -> "Saved file"); nav Download hidden while the hero or closing CTA is on screen; current-page footer link underlined.
  Final crawl (/tmp/anvil-shots6): audit 0 FAIL 0 WARN, axe 0, skip link first, focus all visible, no overflow, 0 console errors. Remaining flags are the current-page link and footer utility links (by design).
Open, not done (structural, need a decision):
- Throttled phone scroll 19-22 fps; phone wordmark tiles read as noise at 390 px. Fix = larger tiles / fewer instances under 480 px.
- Methodology page carries no tile language; no continuous home -> methodology transition.
- Inline "Foundry source" link 22 px tall (inline exception, left as is). Hero palette search looks like a field but is not one.
Evidence so far (shots: /tmp/anvil-shots3, phone frames: /tmp/anvil-qa):
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
Evidence (/tmp/anvil-shots7, frames /tmp/anvil-qa/r): audit 0 FAIL 0 WARN; axe 0 on all pages; skip link first; invisibleFocus 0; 0 console errors.
Open: naming Raycast needs the legal review noted in the Sept report; coast.jpg has no recorded source.

### Round 3, 2026-10-24: clipboard belt, phone tiles, tile transition
- [x] Clipboard is one belt: `clipboardSelection` drives both the DOM cards and the GL ribbon (passed to the scene as `clipboardBelt`). Cards sit on the ribbon (anchored bottom-centre, tilted by the ribbon slope), land in turn from 1.01, loop so the right side never empties, and the belt carries everything off left at 1.5-1.58. Leftover shelf tiles now shrink in place (no rise into the heading). Phone belt amplitude halved; phone photo card 58% wide.
- [x] Phone tiles: "bigger, fewer tiles" is not possible without a shelf redesign (createShelfTiles needs all 272 full tiles). Root cause of the noise was the 1.25 DPR cap; phones now cap at 2. Throttled phone scroll on a real GPU (Metal, 4x CPU, DSF 3): median 16.7 ms, p90 18.3 ms. The crawler's 19-22 fps comes from SwiftShader (browser.mjs launches with --enable-unsafe-swiftshader), not the site.
- [x] "Read methodology" transition: the 81% tiles fly to the methodology figure (app/foundry/methodology-figure.ts, shared geometry), the rest fades, then router.push; methodology renders the same figure in DOM tiles and fades its content in (html[data-arriving]). Positions verified equal at 1440/1024/390 (figure top 132, tile centres match to 0.02 px). Back button returns to the memory stop (story progress kept in history.state).
Evidence: /tmp/anvil-qa/belt-*.png, /tmp/anvil-qa/transition-{d,m}.png, /tmp/anvil-qa/t/back.png, crawl /tmp/anvil-shots8 (audit 0 FAIL 0 WARN, axe 0, focus all visible, 0 console errors).
Scripts (outside repo): /tmp/anvil-rebuild.sh, /tmp/anvil-sheet.py, ~/.cache/jury/{transition,back,profile-phone,hero-phone,figure-rect}.mjs.

## Prototype: tile world (removed 2026-10-24)

Built at `/world` on branch `website-tile-world`, then deleted at the user's request ("don't like world"). Nothing from it was committed.

## Craft pass, 2026-10-24 (branch `website-tile-world`, uncommitted)
Design: `anvil/docs/plans/2026-10-24-craft-pass-design.md`.
- [x] Step 1, real launcher. `app/foundry/launcher.tsx` + `launcher.css` copy the running app's panel (reference screenshots `/tmp/anvil-qa/ref/crop-{home,calc}.png`, taken from Foundry.app). Sizes are in points through `--pt` (41.8vw / 750 on desktop, 1px on phone). Live: filter, arrow keys, Enter opens the story stop (`toolStop(i)` added to tools-motion), math via `app/foundry/calculate.ts` (copy answer on Enter). Hero panel at left 53%, top 31.55vw; tile flight path points in `tile-motion.ts` pulled toward the panel so the trail runs between the headline and the panel. Tools section: compact panel (query + action row) replaces the thin bar.
  Evidence: `/tmp/anvil-qa/l/*.png`, `/tmp/anvil-qa/flight2.png`, `/tmp/anvil-qa/tools-l.png`; shoot.mjs: axe 0, 0 console errors, skip link first. shoot.mjs flags the launcher input as "noVisibleFocus" because the ring is drawn on the panel through `:has(input:focus-visible)`; `/tmp/anvil-qa/focus-launcher.png` shows the ring.
- [x] Launcher cleanup (user request): removed the stats strip (sample numbers), Ask AI, repeated "Command" labels and the ⌘ / Actions footer items. Placeholder "Search commands...", hairlines under the search and above the footer, ↵ keycap only on the selected row, footer "↑↓ Select · ↵ Open" (hint hidden on touch). Panel height 360 pt. Flight path end retuned to the moved Convert Image row. Evidence `/tmp/anvil-qa/clean*.png`.
- [x] Launcher as a marketing piece (user: "doesn't need to be pixel perfect, make it really impressive"). Two columns: six commands left, live preview right. Self-running demo types clip, 24*18, hello, png in a loop (pauses when scrolled past 40 px, hidden tab, reduced motion; stops on pointer enter or focus, resumes on leave if empty). Selection glides (motion layoutId). Previews: clipboard cards from clipboardItems, calculator answer drawn in glazed tiles (tileText), Convert Image shows the tiled orange whose background tiles fall away on a loop, Translate, Snippets, Download Video with a progress bar. Rows never unmount (non-matches dim), so `#foundry-command-1` always exists for the tile flight gate. Glass gradient edge, warm halo. Evidence `/tmp/anvil-qa/demo.png`, `/tmp/anvil-qa/demo-page.png`, `/tmp/anvil-qa/demo-phone.png`; axe 0, console 0.
- [x] Calm pass (user: "looks ugly / like the gradient behind it too"). launcher.css: removed orange halo, gradient edge, orange focus ring, search and preview dividers; flat panel `#1b1917f2` with hairline; recessed preview; soft `#ffffff0f` selection; borderless cards, chips, keys. Focus is now a brighter hairline plus orange search icon. foundry.css: `.foundry-stage` radial gradient flattened to `#0f0d0c`.
  Evidence: `/tmp/anvil-qa/calm.png`, `/tmp/anvil-qa/calm-hero-focus.png`. The visible warm glow came from `.story-stage` in story.css (radial at 65% 45%), now flat too.
- [x] Type pass: shelf, clipboard and tools section heads share `clamp(44px, 5.2vw, 92px)`, line-height 1.04. Tools compact launcher `--pt` 41.8vw/620 (row text 14.5px at 1440).
- [x] Phone bleed fix: phone launcher was 997px tall in an 844px stage, so its last rows trailed under the nav after the hero left. Results now scroll inside 216pt with a fade, preview 170pt. Probe: launcher bottom -48px at scroll 4000.
  QA (shoot.mjs, `~/.cache/jury/.shots`): 0 axe violations, 0 audit FAIL/WARN, 0 console errors, CLS 0, mobile LCP 1.1s. Still flagged: launcher input noVisibleFocus (focus = brighter hairline + orange icon + caret; user rejected the ring).
  Critic pass 1 (Opus 5.5, evidence `/tmp/anvil-qa/critic/`): 7.15 (D7 U7 C7.5 Ct7.5). Fixes done from its list:
  - Handovers through black: hero tiles now stay on screen (`gatePassage` gate y clamped to >= 10% height in shelf-motion.ts); belt tiles carry into the tools glyphs (tools-motion `writeToolsTilePose` mixes from the prior pose; belt keeps 60% size, clipboard-motion exit); clipboard text out 1.47-1.55, tools in toolsEnter-.03 to +.05; closing headline in at downloadStart+.04 to +.12. Frames `/tmp/anvil-qa/tx-*.png`.
  - Closing trail no longer ends beside "Your next" (3 desktop trail points removed, download-motion.ts).
  - Header Download flash: `data-quiet` no longer waits for the GL scene (story.tsx), SSR ships `data-quiet="hero"`.
  - Not bugs: `hover.covered` is a scrollIntoView artifact (each control hits at its own stop, `~/.cache/jury/probe-covered.mjs`); the PNG label fades in 0.79-0.825 by design.
  - Left: copy rewrites ("Small tasks. All here.", "Your next command starts here.") need the user's call; launcher focus ring rejected by user.
  Critic pass 2 (evidence `/tmp/anvil-qa/critic2/`): 7.6 (D8 U7 C8 Ct7; dev Sem8 Anim7 A11y7 WPO8 Resp7 Meta8). Fixes done after it:
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
  Evidence: `/tmp/anvil-qa/stops*.png`, `/tmp/anvil-qa/tx-mem.png`, `/tmp/anvil-qa/copy*.png`.
- [x] Reduced motion / static mode: tools results drawn with `Tiles` (exported from launcher.tsx), source slab hidden, compact launcher shown, two-column grid on desktop; memory "81%" drawn with Tiles; static HEIC file has tile grout + label chip; static shelf tiles glazed; `.launcher-tiles i` animation off under reduced motion. Evidence `/tmp/anvil-qa/reduced-*.png`.
- [x] Methodology transition exists and works (81% tiles fly to the page header): `/tmp/anvil-qa/method/0-9.png`. Heading orphan fixed with nbsp.
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
- [x] Tools section, "literal answers" pass (user asked for something more unique): calculator builds a 24x18 grid of 432 tiles, video link becomes a tile file icon with a play triangle (outline + dot fill, echoes the shelf mold), AI rewrite scatters into a cloud and recondenses. Translation flip, snippet caret and developer clock unchanged. Evidence: /tmp/tl2, /tmp/tl3 frames, 0 console errors.
- [ ] Next: user feedback on the literal-answer direction; then a fresh critic pass.

## The last 20% plan, 2026-11-01
- Plan: docs/plans/2026-11-01-foundry-last-20-percent.md (7 phases, 50+ tasks, each pinned to a file:line finding).
- Evidence: three read-only audits (Opus 5.5) in docs/plans/2026-11-01-last-20-audits/{panel,features,onboarding}.md. P0 claims re-read in source before the plan was written.
- Open decisions D1–D8 at the top of the plan (entrance motion, four-step onboarding, launch at login default, Camera cut, keep DevTools/Translator as modes, casing rule, favicon policy, commit granularity). Tasks implement the recommendation; change the task, not the bar, if the user picks otherwise.
- Not started. The tree still carries the uncommitted mini port (Phase 0 lands it first).
