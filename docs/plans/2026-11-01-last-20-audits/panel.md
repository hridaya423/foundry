# Foundry launcher panel: polish audit ("the last 20%")

Read-only audit. No builds, no app runs, no files edited. All paths are relative to `Sources/Foundry/`. Findings marked "verify" come from reading code and need a frame capture to confirm.

Priority: P0 is visibly wrong or broken. P1 falls clearly below the bar. P2 is refinement.

## 1. Entrance and exit

- [P0] UI/CommandPanelState+Lifecycle.swift:23-31 — now: when reopened inside the pop-to-root window with a query, `query = ""` repaints Home from cache, then `session.results = []` and `selectedResultID = nil` wipe it, so frame 1 shows the "Start typing" empty state until the async `loadHome` lands · bar: frame 1 is the final Home · proposed: delete the `results = []` / `selectedResultID = nil` lines; `query = ""` already refreshes. Also note the branch is named "restore" but clears the query. Raycast keeps the query inside the window and selects all of it, so typing replaces it. Do that: keep the query and send `selectAll:` to the field editor.
- [P1] UI/CommandPanelView.swift:259-266 — now: `presented = false`, then `DispatchQueue.main.async`, then `withAnimation(.spring(response: 0.22, dampingFraction: 0.9))`. That guarantees at least one fully transparent content frame inside a window that is already ordered front at `alphaValue = 1` (Shell/PanelController.swift:77-81) · bar: Raycast and Spotlight paint content on the first frame · proposed: set the start state before `makeKeyAndOrderFront`, then animate opacity only, 0→1 over 0.10 s `timingCurve(0.23, 1, 0.32, 1)`. Keep the 0.97 scale only if the user's 1.1 preference still holds, and cap it at 0.98 with the same curve and 0.14 s, no spring.
- [P1] Shell/PanelController.swift:216 — now: `hasShadow = true` on a clear borderless window whose content starts at opacity 0 and scale 0.97, and `invalidateShadow()` is never called anywhere in `Sources/` · bar: the shadow matches the 26 pt superellipse on every frame · proposed: call `panel.invalidateShadow()` after the entrance completes and after `setCompactCollapsed` (verify: capture frame 1 and frame 10 and compare shadow edges).
- [P1] Shell/PanelController.swift:143-149, 154 — now: a 0.09 s ease-in alpha fade, then `orderOut`, focus restore, and only then `completePendingPaste` · bar: keyboard dismissals are instant, and paste lands the moment the panel goes away · proposed: `orderOut` at once (duration 0) for Return-driven dismissals that paste or open something. Keep at most 0.06 s ease-in for Esc and click-away.
- [P1] Shell/PanelController.swift:59 — now: `setFrame(..., animate: true)` uses the system resize time (about 0.2 s) when compact mode expands on the first keystroke · bar: no animation on keyboard-initiated changes · proposed: `animate: false`, or a 0.12 s ease-out `NSAnimationContext` gated on Reduce Motion.
- [P2] Shell/TransientNoticeController.swift:19-31 — now: the toast pops in at full alpha, centered on the closed panel's frame, holds 1.4 s, then fades for 0.18 s with the default timing. In-panel success feedback holds 2.2 s (UI/ActionFeedbackPresentation.swift:20-21) · bar: one HUD timing · proposed: entrance opacity 0→1 over 0.12 s ease-out, hold 1.6 s, exit 0.18 s ease-in, the same hold for in-panel success.
- Focus return (PanelController.swift:161-164) is correct: it deactivates unless another Foundry window is up.

## 2. Row anatomy

- [P1] UI/PanelRowViews.swift:69-99, 288-336 and UI/PanelChrome.swift:51-91 — now: three row components. Home rows are 40 pt with a 26 pt icon at radius 6. Search rows are 44 pt (38 compact) with a 28 pt icon at radius 7. Action rows are 40 pt with a 28 pt well at radius 7. Stack spacing is 2 at Home and 3 in search (CommandPanelView.swift:661) · bar: one row, so Home and search do not shift on the first keystroke · proposed: delete `HomeResultRow` and render `ResultRow` with the subtitle hidden. Use one height, 44 (38 compact), one 28 pt icon, fallback radius 6.5 (28 × 0.2237, the macOS icon ratio), and stack spacing 2 everywhere.
- [P1] UI/PanelRowViews.swift:79, 291; UI/PanelChrome.swift:68 — now: `.scaleEffect(isSelected ? 1.04 : 1)` with no animation, so the icon jumps 4% on every arrow press · bar: selection moves the highlight and nothing else · proposed: remove it.
- [P2] UI/PanelRowViews.swift:12-26 — now: the selected row has a 0.10 fill plus a 1 pt `selectionBorder` at 0.16 · bar: Raycast and Linear use a fill only · proposed: fill only (`fillSelected` 0.10). Keep the 2 pt accent border only under Increase Contrast.
- [P2] UI/PanelRowViews.swift:317-322 — now: a 6 pt `success`-green dot sits in the trailing accessory cluster, between the badges and the kind label · bar: a running app reads as a quiet Dock-style mark, not an "online" status · proposed: a 4 pt dot in `textTertiary`, placed directly after the title with 6 pt leading.
- [P2] UI/PanelRowViews.swift:344-356 — now: `ResultBadge` is 20 pt high, radius 5, on `fillHover`, while `KeycapHint` is 19 pt, radius 5, on glass · bar: one badge primitive · proposed: one `Badge` at 20 pt, radius `Radius.badge` (6), `fillTint`, with `caption` text.
- [P2] UI/PanelRowViews.swift:376-394 — now: the fallback icon tile is a `RoundedRectangle` · bar: the same squircle as real app icons · proposed: `FoundrySmoothedRectangle(cornerRadius: size * 0.2237, smoothing: 0.6)`.
- Concentric radii work for the panel: row radius 10 + list inset 16 = panel radius 26. They do not work for the actions overlay (see lens 5).
- Icon resampling is clean. `NSWorkspace.icon(forFile:)` returns a multi-rep image, and the cache warms the first 12 rows.

## 3. Search field

- [P0] UI/CommandPanelView.swift:469-470 — now: opening ⌘K rebinds the main field to `actionFilter`. The user's query disappears from the header while the actions popover sits bottom-right, so the caret is about 400 pt from the list it filters · bar: Raycast puts "Search for actions…" inside the popover, and the root query stays visible · proposed: keep the header bound to `query`, and add a 32 pt filter field at the bottom of the actions surface with `bodySecondary` text.
- [P1] UI/PanelChrome.swift:170-192 — now: `fitTextToWidth` shrinks the font from 20 pt down to 12 pt as the query grows, so the text resizes on every keystroke · bar: a fixed size with horizontal scrolling · proposed: delete `fitTextToWidth` and keep 20 pt. `isScrollable` is already set.
- [P1] UI/PanelChrome.swift:151 — now: `insertBacktab:` (Shift-Tab) also opens Ask AI · bar: Shift-Tab does not do the same thing as Tab · proposed: handle `insertTab:` only, and let Shift-Tab do nothing in search.
- [P1] UI/PanelChrome.swift:149-160 — now: `doCommandBy` does not intercept `cancelOperation:` or `moveUp:`/`moveDown:`. NSTextView's default Esc handling can trigger `complete:`, and its arrow handling moves the caret · bar: the field forwards Esc and arrows to the panel explicitly · proposed: return `true` for `cancelOperation:` (route to `onEscape`) and for `moveUp:`/`moveDown:` (route to selection). Verify: Esc in a non-empty field must not open a completion list.
- [P1] UI/CommandPanelView.swift:913-930 — now: the footer status flips between "Searching…" and "N results" on every keystroke · bar: a loading indicator appears only when search is slow, and no result count is shown · proposed: show a 1 pt indeterminate hairline under the header only after 150 ms of loading. Delete the "N results" text. It also counts `session.results`, not the rows actually painted (`searchListResults`), so it can be wrong.
- [P2] UI/CommandPanelView.swift:486-495 — the clear button's `.transition(.scale(0.7))` never runs because typing is not animated. Remove the transition. Esc already clears.
- Placeholder, ⌘C/⌘V/⌘A/⌘Z/⌘⌫ precedence (Shell/PanelController.swift:361-377), and Esc clear-then-close (UI/PanelRouter.swift:215-223) are correct.

## 4. Empty, loading and error states

- [P0] UI/CommandPanelView.swift:585-591 — now: no results gives "No results / Nothing matches "x"." with a 68 pt tile, a dead end · bar: Raycast lists fallback commands ("Ask AI", "Search Google for x") that are keyboard-selectable · proposed: render `ResultSection.fallback` rows (Ask AI ⇥, Search the web, Search files) as normal navigable rows, so ↵ always does something.
- [P1] UI/FeatureSurface.swift:217-224 — now: the message is `lineLimit(1)` with middle truncation, and the file-search hint at CommandPanelView.swift:569-572 runs about 105 characters, which truncates at 670 pt · proposed: `lineLimit(2)`, `.multilineTextAlignment(.center)`, `frame(maxWidth: 420)`.
- [P1] UI/CommandPanelView.swift:567, 581, 583 — now: separate loading empty states (a spinner plus "Loading Home") show whenever there is no cache · bar: loading never replaces the list with a placeholder screen · proposed: keep the previous rows and show the hairline (lens 3). On a cold first launch, show 5 skeleton rows at 44 pt in `fillSubtle` and no spinner.
- [P2] UI/FeatureSurface.swift:187-231 and UI/FoundryControls.swift:235-276 — now: two empty-state components. One uses a 68 pt tile at radius 18 with a 20 pt title, the other a 58 pt tile at radius 16 with a 13 pt title · proposed: one component with a 56 pt tile, radius 14 (`Radius.overlay`), a `body` title, and `bodySecondary` text in `textSecondary`.
- [P2] There is no search error state. A provider failure looks like "No results". Proposed: an `InlineNotice(level: .warning)` row at the top of the list, e.g. "Spotlight isn't responding. File results may be missing."

## 5. Footer and the ⌘K actions panel

- [P0] UI/CommandPanelView.swift:894-907, UI/PanelSession.swift:291-294 — now: with nothing selected (no results, or a loading Home), the footer still shows "↵ Open" and "⌘K Actions", because `preferredActionTitle` falls back to "Open" · bar: the footer only promises what Return will do · proposed: return `nil` with no selection and hide both hints.
- [P1] UI/CommandPanelView.swift:143-154 vs 911-940 — now: while a prompt is up, Return confirms the prompt but the footer still advertises the row action · proposed: footer reads `[↵ <confirmLabel>, esc Cancel]` while `pendingPrompt != nil`.
- [P1] UI/FeatureSurface.swift:173-185 — now: footer actions are not clickable, and they read keycap-then-label · bar: Raycast's footer items are buttons ("Open Application ↵ | Actions ⌘K"), label first · proposed: render each `FooterAction` as a button with `[label][keycap]`, 6 pt gap, 28 pt hit height, wired to the same handler as the key.
- [P1] UI/FeatureSurface.swift:156-171 — now: `KeycapHint` is a `FoundryGlassSurface(.control)`, so every footer keycap and every action-row shortcut is its own `glassEffect`: glass on glass, costly, noisy · proposed: a flat `fillTint`, radius 5 → `Radius.badge` (6), 19 pt minimum, `caption` in `textSecondary`.
- [P1] UI/CommandPanelView+Surfaces.swift:110-113 — now: `proxy.scrollTo(actionID, anchor: .center)` re-centers on every move · bar: minimal scroll, the same as the main list · proposed: reuse the visible-ID guard from CommandPanelView.swift:736-746.
- [P1] UI/PanelChrome.swift:72 — now: destructive actions tint only the title, sit in line with the others, and keep a neutral icon · bar: destructive actions go last, behind a separator, with title and icon in `destructive` · proposed: sort `isDestructive` actions to the end, put a 1 pt `separator` with 4 pt vertical padding before them, and tint the icon too.
- [P1] UI/CommandPanelView.swift:128-139 — now: radius 16, width 340, max height 320, `spring(response: 0.28, dampingFraction: 0.82)` (which overshoots), scale 0.96 · bar: a keyboard-summoned popover appears fast with no bounce · proposed: radius 18, so 10 row + 8 inset is concentric. Enter: opacity plus scale 0.98, anchor `.bottomTrailing`, 0.15 s `timingCurve(0.23, 1, 0.32, 1)`. Exit: 0.10 s ease-in. Apply the same to the prompt (144-154) and the drop chooser (159-168).
- [P2] UI/CommandPanelView+Surfaces.swift:62-79 — now: an "ACTIONS" uppercase kicker plus the result title in tertiary · proposed: drop the kicker and show the result's 16 pt icon plus its title in `caption` `textSecondary`. Group actions under quiet section labels ("Open with", "Foundry") the way Raycast does.
- [P2] UI/FeatureSurface.swift:127-153 — now: the footer's leading control is a ⌘ glyph that opens a menu, and it reads as a shortcut hint · proposed: `ellipsis.circle` or the Foundry mark at `Glyph.sm`, labelled "Foundry menu".

## 6. Keyboard

- [P0] UI/CommandPanelView.swift:684-699, UI/PanelSession.swift:88-100 — now: Favorites and the Home window-layout row are outside `navigableResults`, so the keyboard cannot reach them · bar: everything clickable is keyboard-reachable · proposed: ⌘1–⌘8 open favorites 1–8. Holding ⌘ fades in a `caption` keycap under each tile (0.1 s). Fold the layout tiles into ←/→ navigation when that row is selected, or add them to `navigableResults`.
- [P1] UI/PanelRouter.swift:224 — now: in feature modes (clipboard, snippets, emoji), Esc goes straight Home even when the mode's search field has text · bar: Esc clears the local filter first, then pops · proposed: check the feature's query first and clear it.
- [P1] Shell/PanelController.swift:392-413, UI/PanelSession.swift:319-335 — now: only ↑/↓ move the selection · bar: Raycast also takes ⌃N/⌃P and ⌃J/⌃K, and lists jump with ⌘↑/⌘↓ · proposed: map ⌃N/⌃J → down and ⌃P/⌃K → up, ⌘↑/⌘↓ (and Home/End) → first/last, Page Up/Down → ±7 rows.
- [P1] UI/PanelRowViews.swift:458-461 — now: visibility tracking uses `onAppear`/`onDisappear` inside a `LazyVStack`, which fire for prefetched offscreen rows and count half-clipped rows as visible. Selection can land offscreen or clipped with no scroll (verify with 20+ results) · proposed: `onScrollVisibilityChange(threshold: 1.0)` (macOS 15+) so "visible" means fully visible.
- No animation on keyboard-initiated actions: violated by the entrance spring (1), the ⌘K spring (5), the Tab/Esc mode crossfade (7), the compact resize (1), and the icon scale (2). Fix them there.
- The drop chooser's ⌘2…⌘N (CommandPanelView+Surfaces.swift:52) is good. ⌘K, ⌘,, ⌘Y and Space for Quick Look are wired correctly.

## 7. Motion inventory

| Site | What | Answers "why"? | Action |
|---|---|---|---|
| UI/CommandPanelView.swift:173-174, 262 | entrance: scale 0.97 + opacity, spring 0.22/0.9, after an async blank frame | partly (the 1.1 preference) | opacity 0.10 s ease-out, scale at most 0.98 (lens 1) |
| UI/CommandPanelView.swift:81 | accessory strip `.move(edge: .top)` | no; never animated, typing is not in a transaction | remove (see change 6) |
| UI/CommandPanelView.swift:84-89 | mode crossfade, easeInOut 0.12, two surfaces stacked in a ZStack | no; keyboard-driven, double exposure on glass | remove, or incoming-only opacity 0.08 s ease-out |
| UI/CommandPanelView.swift:105-121 | feedback capsule transition | dead; `showActionFeedback` sets state without animation (UI/CommandPanelState.swift:174-185) | wrap in a 0.15 s ease-out, or delete the transition |
| UI/CommandPanelView.swift:128-168 | actions, prompt, drop chooser: spring 0.28/0.82, scale 0.96 | yes (it shows where the overlay came from) but overshoots | 0.15 s ease-out in, 0.10 s ease-in out |
| UI/CommandPanelView.swift:170; UI/ConfettiBurst.swift:19 | confetti, a 2.4 s Canvas | yes (celebration, user-triggered); paused when idle; Reduce Motion gives 0 particles | clean |
| UI/CommandPanelView.swift:494, 529 | clear-button scale 0.7, header-controls move | dead | delete |
| UI/CommandPanelView.swift:612-613 | strip easeOut 0.14 on shelf/agent count | yes (content arrives) | keep, `Motion.state` |
| UI/CommandPanelView.swift:636-640 | drop-target `phaseAnimator` scale 1.035, easeInOut 0.55 | no; the dashed border already says "drop here" | delete |
| UI/FoundryControls.swift:142 | quiet press: opacity 0.55, scale 0.97, easeOut 0.12 | yes | merge with the next row |
| UI/FoundryControls.swift:154 | pressable: scale 0.975, opacity 0.82, easeOut 0.10 | yes, but a near-duplicate | one style: scale 0.97, opacity 0.7, 0.10 s ease-out in, 0.18 s out |
| Shell/PanelController.swift:59 | compact `setFrame(animate: true)` | no; keyboard-driven | instant |
| Shell/PanelController.swift:143-149 | exit fade 0.09 ease-in | weak; it delays paste | 0–0.06 s (lens 1) |
| Shell/TransientNoticeController.swift:29-31 | toast fade-out 0.18, no fade-in | half | lens 1 |
| UI/HomeAccessoryStrip.swift:209 | `TimelineView(.periodic(by: 10))` reads `NSPasteboard` every 10 s | idle work while the panel is open | read on panel open and on `changeCount` only (verify it stops when ordered out) |
| UI/HomeAccessoryStrip.swift:482, 514 | `.everyMinute` clock and date | yes | clean |
| UI/FeatureSurface.swift:198; UI/FoundryControls.swift:208; UI/PanelRowViews.swift:237; UI/WindowLayoutPicker.swift:296 | `ProgressView` spinners | only while loading | replace the list-level ones with the delayed hairline |

- [P1] UI/FoundryTheme.swift:257-265 — the only motion tokens are `Brand.Motion` (onboarding). Every panel duration is an ad hoc literal · proposed: `FoundryTheme.Motion { press 0.10, overlayIn 0.15, overlayOut 0.10, state 0.14, exit 0.06 }`, all on `timingCurve(0.23, 1, 0.32, 1)` (ease-in for exits). Extend `lint-design.sh` to reject `duration:` outside the theme.

## 8. Pointer

- [P1] UI/FoundryControls.swift:159-166 — now: `pointerCursor()` sets `NSCursor.pointingHand` on hover for every row, tile and button, and resets to arrow on exit. That fights the field's I-beam and other cursor rects (flicker crossing nested views) · bar: macOS list rows and buttons use the arrow; the hand is for links · proposed: remove it from rows and buttons. Keep `.pointerStyle(.link)` (macOS 15+) only on "View all" and the agent "↗" link.
- [P1] UI/PanelRowViews.swift:134; UI/WindowLayoutPicker.swift:74-78, 375; UI/HomeAccessoryStrip.swift:277 — now: `FavoriteTile`, `CompactLayoutButton`, `FamilyTab` and `AgentWidgetRow` ignore `foundryHoverHighlightsArmed`, so they highlight under a resting cursor when the panel opens · proposed: gate them exactly like `RowBackground`.
- [P1] UI/PanelPromptOverlay.swift:65-74, 81-96; UI/FeatureSurface.swift:267-274; UI/FoundryControls.swift:263-270 — now: padding, frame and background are applied outside the `Button`, so only the label glyphs are clickable · proposed: move padding and frame into the label (or a `ButtonStyle`) and add `.contentShape(.rect)`.
- [P1] UI/WindowLayoutPicker.swift:22-33 — "View all" is a plain button about 14 pt tall · proposed: `.frame(minHeight: 24)` plus `.contentShape(.rect)` with 6 pt horizontal padding.
- Other targets meet 24 pt: icon buttons 30, drop rows 34, rows 40–44.

## 9. Accessibility

- [P0] UI/FoundryControls.swift:19 — now: the `floatingOverlay` fallback fill is `scrimStrong` (black at 0.5). It is used under Reduce Transparency and on every pre-macOS 26 system. In light mode the actions panel, prompt, drop chooser and feedback capsule render as mid-gray with dark text · proposed: under Reduce Transparency use `Color(nsColor: .windowBackgroundColor)`. On legacy systems use `VisualEffectView(material: .popover)` plus a 0.5 pt `separator` stroke.
- [P0] UI/PanelSession.swift:319-335 — now: focus stays in the field, and arrowing posts nothing, so VoiceOver users hear nothing as the selection moves · bar: each move is announced · proposed: on `selectedResultID` change, post `NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [.announcement: "\(title), \(kind), \(i) of \(n)", .priority: NSAccessibilityPriorityLevel.high.rawValue])`.
- [P1] UI/FoundryTheme.swift:102-105 — now: Increase Contrast changes borders and selection, but text tokens stay at 0.56/0.44 · proposed: under Increase Contrast, tertiary 0.56→0.74 and quaternary 0.44→0.60 (kind labels, footer, hotkey hints).
- [P2] Shell/PanelController.swift:59 — the compact resize animation is not gated on Reduce Motion. Gate it, or make it instant per lens 1.
- [P2] UI/CommandPanelView+Surfaces.swift:78; UI/PanelChrome.swift:78 — `"Shortcut \(shortcut)"` makes VoiceOver read glyph names. Map them to spoken names ("Command Return", "Command D").
- `rowActivation` (UI/FoundryControls.swift:279-285) is correct: combined element, button and selected traits, a default action. Reduce Transparency switches the backdrop to opaque correctly. Removing the focus ring from the field is correct for a launcher.

## 10. Copy

- [P1] UI/CommandPanelView.swift:879-880 — "Utility" leaks the route name. "Browser" covers tabs, bookmarks and history alike · proposed: "System" for `.macUtility`, and "Tab", "Bookmark", "History" per route.
- [P1] UI/CommandPanelView.swift:274, 312 — "Click" sits inside a keycap · proposed: "↵ Open" for agents and "↵ Copy" for developer tools, or drop the hint.
- [P1] Casing is inconsistent. Proposed rule: actions and commands in Title Case (HIG); headings, states and messages in sentence case. Change "Loading Home" (CommandPanelView.swift:581) and "Search Files" (569, 574) to sentence case so they match "No files found" and "Searching files". Change "Take the Tour" (71) to "Take the tour", since it is a link inside a sentence. Change "Window management" and "Window layouts" (UI/WindowLayoutPicker.swift:16, 149) to "Window Layouts", matching other titles such as "File Shelf" and "Convert Files".
- [P2] Keycap formatting mixes `esc`, `Tab`, `↵`, `⌘K` and `Click` · proposed: glyphs plus `esc`: `↵ ⌘K esc ⇥ ⌫ ⇧⌘C`. Change the "Ask AI … Tab" hint (CommandPanelView.swift:505) to "⇥" in `caption`, not `Glyph.xs`.
- [P2] UI/PanelSession.swift:251 — "Open with X — Default" · proposed: "Open with X" plus a trailing "Default" accessory in `caption` `textQuaternary`.
- [P2] UI/CommandPanelView.swift:284 — "Tone ·" when no skin tone is set · proposed: "Skin Tone".
- [P2] Shell/StatusItemController.swift:31 — "… is unavailable — Choose Another Shortcut…" · proposed: "⌥Space Is Taken. Choose Another Shortcut…".
- [P2] Commands/Execution/PanelActions.swift:159 vs 170 — "Added to Favorites" vs "Ranking reset". Make the second "Ranking Reset", or both sentence case ("Added to favorites", "Ranking reset"). Pick one.

## 11. Tokens

- [P1] The lint has a loophole. `opacity(` with a ternary or a variable passes `lint-design.sh`: UI/WindowLayoutPicker.swift:78 (`0.16 : 0.08`), 587 (`0.12 : 0.05`), 623 (`0.26 : 0.15`), 628 (`0.95 : 0.6`); UI/HomeAccessoryStrip.swift:277 (`0.9 : 0.35`); UI/FoundryControls.swift:140, 153 (`0.55`, `0.82`). So does `FoundryTheme.dark(0.06)` (UI/CommandPanelView.swift:256). `Color.green`/`Color.red` (UI/HomeAccessoryStrip.swift:438) bypass `success`/`destructive` · proposed: map these to `selectionBorder`, `fillTint`, `separator` and `stroke`, and extend the lint to any numeric literal inside `opacity(`.
- [P1] Radii outside the 6/8/10/14/26 scale: 16 (overlays, CommandPanelView.swift:128, 144, 159), 18 (FeatureSurface.swift:203; CommandPanelView.swift:635; PanelRowViews.swift:248), 9 (FeatureSurface.swift:280; WindowLayoutPicker.swift:75), 7 (PanelChrome.swift:60; FeatureSurface.swift:274; HomeAccessoryStrip.swift:161, 328; PanelRowViews.swift:290), 5 (PanelChrome.swift:160 → FeatureSurface.swift:160; PanelRowViews.swift:354; WindowLayoutPicker.swift:619), 4 (CommandPanelView+Surfaces.swift:23), and a literal 14 (CommandPanelView.swift:609; HomeAccessoryStrip.swift:40, 44) · proposed: add `Radius.popover = 18`. Then 9 and 7 → 8, 5 and 4 → 6, the 14 literals → `Radius.overlay`, and 18 → `popover`.
- [P1] The header uses 22 pt horizontal padding (UI/FeatureSurface.swift:33), so search text starts at x = 22 while row icons and section text start at x = 28 (16 inset + 12 row padding) · proposed: header padding 28, so the field's text sits on the icon column.
- [P2] Spacing outside 4/8/12/16/24: 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 18, 20, 22, 46, 50 (e.g. CommandPanelView.swift:118, 135, 666, 686, 698; FeatureSurface.swift:260, 277). Collapse 6→8, 10→12, 14→16, 18/20/22→24 except for optical cases. Name the overlay offset from the footer: `footerHeight (38) + Spacing.xs` = 46.
- [P2] Near-duplicate colors: `sectionHeader` 0.70 vs `textSecondary` 0.74 → keep `textSecondary`. `fillSelected` 0.10 = `Alpha.subtle` 0.10. `stroke` 0.18 = `highContrastSelection` 0.18. `selectionBorder` 0.16 vs `fillEmphasis` 0.14 → one 0.15. Agent colors `.working` (0.42, 0.90, 0.67) ≈ `success`; `.reviewReady`/`.completed` ≈ `accent` → alias them (UI/FoundryTheme.swift:286-290).
- [P2] Near-duplicate type: `rowTitle` 13.5 medium vs `body` 13 medium; `rowDetail` 12 vs `mono` 12. `Strip` sizes of 9, 9.5 and 10 sit below the ramp's own 11 pt minimum (UI/HomeAccessoryStrip.swift:123, 134-138, 188, 366). `Glyph.xs` is used as a text style (UI/CommandPanelView.swift:506) · proposed: drop 13.5 for `body`; strip floor at 10 with the semibold labels at 11.
- [P2] Sizes repeated as literals: overlay width 340 (×3), shadow `radius: 24, y: 10` (×3), header 60, footer 38, controls 26/29/30/34 · proposed: `Panel.headerHeight`, `Panel.footerHeight`, `Overlay.width`, `Overlay.shadow`, and control heights 24/30.

## The ten changes that would most change how the panel feels

1. **Frame 1 is final.** Remove the async blank frame and the `results = []` wipe on reopen. Keep the query inside the pop-to-root window with the text selected. Entrance is opacity only (scale at most 0.98), 0.10 s, ease-out. Call `invalidateShadow()` after it.
2. **⌘K behaves like Raycast's actions panel.** The filter field lives in the popover and the root query stays visible. Use a 0.15 s ease-out with no spring, minimal scroll, destructive actions last behind a separator, and a concentric 18 pt radius.
3. **The footer never lies, and it is clickable.** Hide ↵/⌘K when nothing is selected. Switch to the prompt's verbs while a prompt is up. Label before keycap, as flat buttons with no glass keycaps.
4. **One row everywhere.** Delete `HomeResultRow`. Use 44 pt rows, 28 pt icons, spacing 2, no selection scale, fill-only selection, and align the header text to the icon column (padding 28).
5. **No dead ends.** No-results shows keyboard-reachable fallback rows (Ask AI ⇥, search the web, search files) instead of an icon tile.
6. **The first keystroke does not move the list.** Today the accessory strip, favorites and What's New disappear and the list jumps up about 70 pt. Move the accessory strip above the footer so the list's top edge is fixed between Home and search.
7. **The search field holds still.** Delete the font shrink. Delete "Searching…"/"N results". Show a 1 pt hairline under the header only after 150 ms of loading.
8. **Fallback glass is readable.** Replace the `scrimStrong` overlay fallback with a window background or the `.popover` material. Step up tertiary and quaternary text under Increase Contrast.
9. **The keyboard reaches everything, and VoiceOver hears it.** ⌘1–⌘8 for favorites, ⌃N/⌃P, ⌘↑/⌘↓, and Shift-Tab no longer duplicating Tab. Esc clears a feature mode's filter before popping. Announce selection changes. Make visibility tracking count only fully visible rows.
10. **Motion is a token, and keyboard paths are instant.** Add `FoundryTheme.Motion`. Exit is at most 0.06 s so paste lands sooner. The compact resize and mode crossfade are instant. Delete the dead transitions and the drop-target pulse. Merge the two press styles. Remove the hand cursor from rows.

Model: Claude Opus 5.5 (`claude-opus-5-5`).
