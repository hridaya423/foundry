# Foundry feature surfaces: last-20% audit

Read-only code audit, run on claude-opus-5-5. I did not build, launch or screenshot the app. Every finding comes from reading the source. Visual claims (overlap, alignment, contrast) are code-derived and need one render pass before anyone acts on them.

Severity: **P0** means behavior is broken, lies, or a core state is missing. **P1** means a visible gap against the bar. **P2** means token or detail drift.

Paths are relative to `Sources/Foundry/`.

## Shared frame (FeatureSurface, panel host, tokens)

- [P0] UI/CommandPanelState+Input.swift:73 — now: arrows in Media, Developer Tools, Quick AI and Agents call `session.moveSelection`, which moves the hidden root results list · bar: arrows move the visible list, or do nothing · proposed: give `MediaDownloadsView`, `AgentShelfView` and the drop chooser a `selectedID` and a `PanelFeature.handleMove`; return early for Developer Tools and Quick AI.
- [P0] UI/CommandPanelState+Input.swift:29 — now: `performActionShortcut` and the ⌘K action panel are gated on `mode == .search`, so no feature surface has an action panel · bar: Raycast puts ⌘K on every list · proposed: let each `PanelFeature` expose `actions(for selection) -> [CommandAction]` and reuse `actionsSurface` and the `.actions` footer spec in every list mode.
- [P1] UI/PanelRouter.swift:215 — now: in feature modes Esc goes straight Home, even when the field holds a query · bar: Esc clears the field first, then goes back, the same as the root at :218 · proposed: when the active feature's query is non-empty, clear it and return true (Clipboard, Snippets, Emoji, the Quick AI composer).
- [P1] UI/CommandPanelView.swift:274, :312 — now: the footers show `Open · Click` and `Copy Value · Click`, with "Click" drawn in a keycap · bar: the footer lists keys only · proposed: `Open ↵` (Agents) and `Copy ↵` (Developer Tools, first value), once Return is wired.
- [P1] UI/CommandPanelView.swift:292, :314, :291 — now: the Shelf footer is `Remove ⌫`, Media is `Home` only, Camera is `Home` only · bar: the footer names the primary action · proposed: Shelf `Quick Look space · Open ↵ · Remove ⌫`. Media `Download ↵ · Actions ⌘K`. Camera: see the cut list.
- [P1] UI/FeatureSurface.swift:72 vs UI/CommandPanelView.swift:505, UI/CommandPanelView+Surfaces.swift:17 — now: key labels are styled three ways: `esc` (caption, glass keycap, radius 5), `Tab` (Glyph.xs, no keycap), and an ad-hoc `esc` pill (micro, radius 4) · bar: one keycap component and one spelling · proposed: always use `KeycapHint`. Write modifiers as glyphs and named keys in lowercase: `esc`, `tab`, `space`, `⌘K`, `⇧⌘C`. Write ranges as `⌘1–5`.
- [P1] UI/FeatureSurface.swift:187 and UI/FoundryControls.swift:235 — now: there are two empty-state components, `EmptyState` (68pt tile, radius 18, title font) and `FoundryEmptyState` (58pt tile, radius 16, body font) · bar: one · proposed: delete `EmptyState` and keep `FoundryEmptyState` with a 56pt tile, `Radius.overlay` (14) and an optional action.
- [P1] UI/FeatureSurface.swift:33 — now: header inset is 22, height 60, field 20pt. Snippets adds a 14pt magnifier (UI/CommandPanelView.swift:352), so its text starts 26pt further right than Clipboard and Emoji · bar: every search header starts its text at the same x · proposed: all feature search headers are back chevron + field, with no magnifier (the root has none), or all of them get the magnifier.
- [P2] UI/FoundryTheme.swift:191 — now: there are five radius tokens (6/8/10/14/26), but the surfaces use 14 distinct raw radii: 10×16, 9×14, 8×12, 18×12, 7×6, 12×6, 14×5, 11×5, 20×3, 16×3, 13×3, 15×2, 5, 4 · bar: the token scale only · proposed: 9→8, 7→6, 11/12/13→10, 15/16/18/20→14, 4/5→6. Then add `cornerRadius: [0-9]` to `lint-design.sh` outside FoundryTheme.
- [P2] UI/FoundryTheme.swift:201 — now: one control height token (`compact` 30), but surfaces use 22/24/26/28/30/32/34/36/40/42/46/48/52 · bar: a short ramp · proposed: `Control.mini 24`, `compact 30`, `field 36`, `row 40`, `rowTall 48`. Map 26/28→24 or 30, 32/34→30 or 36, 42/46→40.
- [P2] UI/FoundryTheme.swift:255 — now: motion tokens exist only for onboarding (`Brand.Motion`), and panel code uses easeOut at 0.10, 0.12, 0.14, 0.16 and 0.2, plus easeInOut at 0.12 and 0.55 · bar: two durations and one curve · proposed: `Motion.hover = easeOut 0.10`, `Motion.state = timingCurve(0.23,1,0.32,1, 0.16)`. Snap 0.12 and 0.14 to them.
- [P1] UI/ClipboardHistoryView.swift:104, UI/FileShelfView.swift:131, UI/EmojiPickerView.swift:39 — now: every arrow press animates `scrollTo` over 0.12s · bar: keyboard moves are instant (Raycast, Linear) · proposed: call `proxy.scrollTo` without `withAnimation` when the change comes from a key, and keep the animation for pointer-initiated selection only.
- [P2] UI/CommandPanelView.swift:89 — now: a mode switch crossfades with `easeInOut(0.12)`, and the switch is usually keyboard-initiated (Tab, ⌘ shortcuts) · bar: ease-out or no animation for keyboard pushes · proposed: `easeOut(0.10)` opacity only.
- [P1] UI/CommandPanelView.swift:105 + UI/MediaDownloadsView.swift:100 — now: there are two toast systems, the panel capsule (2.2s/5s) and the Media completion card (6s, radius 13) · bar: one feedback channel · proposed: send the Media completion through `showActionFeedback` with an inline action ("Saved ‘\(title)’ · Open ↵"), and delete `completionNotice`.
- [P1] UI/FeatureSurface.swift:233 + Settings/SettingsComponents.swift:115 — now: `SettingsNotice` always uses level `.error` (red), even for informational text, and `InlineNotice` uses radius 9 and 7 · bar: the level matches the meaning, with token radii · proposed: pass a `level` through `SettingsNotice`. InlineNotice radius 8, button radius 6.
- Motion clean: hover fades are 0.10–0.12 ease-out and respect Reduce Motion everywhere I read. The open spring (UI/CommandPanelView.swift:262) is deliberate per the 1.1 note. Keep both.

## Clipboard

- [P0] UI/CommandPanelState+Paste.swift:12, :31, UI/ClipboardHistoryState.swift:176 — now: "Select an item to paste.", "No text found in that image." and the other Vision errors go to `clipboardHistory.report`, which the panel never renders · bar: failure is visible where it happened · proposed: route them to `showActionFeedback(.failure(...))`, for example "No text found in this image. Try a sharper screenshot."
- [P0] UI/Settings/SettingsView.swift:1026 — now: the same error object is shown in Settings as "Clipboard history could not be saved: No text found in that image." · bar: the message matches its cause · proposed: give persistence its own `persistenceError` and show only that here: "Couldn't save clipboard history: \(reason). Check free disk space."
- [P1] UI/CommandPanelState+Paste.swift:16-20 — now: when direct paste fails it is logged, Return silently falls back to copy, and the footer still says `Paste ↵` · bar: the fallback is stated · proposed: on fallback, toast `.info("Copied. Paste with ⌘V. Allow Accessibility to paste directly.")` and change the footer to `Copy ↵` while `accessibilityTrusted == false`.
- [P1] UI/PanelFeature.swift:189-192, UI/CommandPanelView.swift:346-349 — now: Return and ⌘↵ dismiss the panel with no confirmation · bar: a HUD after the panel closes · proposed: `shell?.showTransientNotice(.success("Pasted"))` or `("Copied")`, the same path the root uses (UI/CommandPanelState.swift:226).
- [P1] UI/ClipboardHistoryView.swift:47 — now: `Button(state.isPaused ? "Resume" : "Pause")` has no button style, so it renders as a bordered macOS push button inside glass · bar: quiet chrome · proposed: `FoundryActionButton(title:systemName: "pause.fill")`. While paused, show `InlineNotice(.warning, "Capture paused. New copies aren't saved.", actionTitle: "Resume")` above the list.
- [P1] UI/ClipboardHistoryView.swift:32-48 — now: the 60pt header holds the search field, and the body repeats a "Clipboard · 12 items · Clear" header plus a segmented control · bar: one header · proposed: drop the in-body title. Put the item count in the footer status slot. Move Clear to ⌘K as "Clear History…" (⇧⌘⌫).
- [P1] UI/ClipboardHistoryView.swift:178 — now: the row hover action reads "Paste as plain text" for images and files, and `onPaste` pastes the full payload · bar: the label is true · proposed: "Paste" for every kind. Offer "Paste as Plain Text" (⌥↵) only for text, as a ⌘K action.
- [P1] UI/ClipboardHistoryView.swift:257-281 — now: the preview header holds up to eight unlabeled 24×24 icon buttons (10pt glyphs, textTertiary) · bar: two visible actions, the rest in ⌘K with shortcuts · proposed: keep Copy (⌘↵) and Paste (↵). Move Open Link (⌘O), Extract Text (⌘E), Read Code, Add to Shelf, Copy Merged and Remove (⌫) into the action panel.
- [P1] UI/ClipboardHistoryView.swift:127-131 — now: "Clear Clipboard History?" / "Remove the copied items currently held by Foundry." · bar: name the scope and say it can't be undone · proposed: "Clear all \(n) items, including \(p) pinned? This can't be undone." Button: "Clear All".
- [P1] UI/ClipboardHistoryView.swift:73-74 — now: "No clipboard matches" / "Try a shorter search or clear the search field." · bar: echo the query and give the fix · proposed: "Nothing matches “\(query)”" / "Search covers text, file names and source apps. Press esc to clear."
- [P2] UI/ClipboardHistoryView.swift:190-192 — now: rows are 36pt high, 10pt padding, radius 8, 13pt title, 22pt icon. Root rows are 40 / 12 / 10 / 13.5 / 26 · bar: one row anatomy · proposed: 40pt height, `Spacing.sm` padding, `Radius.row`, `FoundryTheme.rowTitle`, 26pt icon box.
- [P2] UI/ClipboardHistoryView.swift:52-61 — now: the native segmented picker hides its ⌘1–5 shortcuts in a tooltip · bar: shortcuts are discoverable · proposed: replace it with chips that carry counts ("Images 4"). Show ⌘1–5 in the ⌘K list.
- [P2] UI/ClipboardHistoryView.swift:348 — now: card buttons use radius 7 on `fillHover` · proposed: `Radius.badge` (6).
- Empty first use is clean: "Clipboard history is empty" states what to do. The filtered-empty "Press ⌘1 to show everything." names the fix. Keep both.

## Snippets

- [P0] UI/SnippetsView.swift:498-503 + UI/SnippetState.swift:128-137 — now: selecting a snippet runs `sync()`, which fires `onChange(title/keyword/tags/content)`, which runs `updateSelected`. That sets `updatedAt = Date()`, and 350ms later the list re-sorts, so arrowing down makes the selected row jump to the top. A snippet's "used" date also changes on open · bar: browsing never mutates data · proposed: in `updateSelected`, return early when every field equals the stored value, and only touch `updatedAt` on a real edit.
- [P1] UI/SnippetState.swift:180-207 — now: import and export succeed silently. Importing zero new snippets also says nothing · bar: confirm the result · proposed: toast "Imported 12 snippets · 3 already in your library", "No new snippets in that file", "Exported 40 snippets to foundry-snippets.json".
- [P1] UI/SnippetsView.swift:182-190 — now: duplicate keywords show in destructive red: "Duplicate keywords: x. Save is allowed, but auto-expansion is disabled until resolved." · bar: warning tint, with the fix named · proposed: `.warning` tint: "“\(kw)” is used by \(n) snippets. Rename one to turn expansion back on."
- [P1] UI/SnippetsView.swift:192-207 — now: every selected snippet shows a static line, "Auto-expansion is unavailable in secure fields and excluded apps.", plus an "Auto-expand" switch that duplicates Settings › Snippets · bar: settings live in Settings · proposed: delete both. Show a one-line warning only when expansion is off or Accessibility is missing: "Keywords won't expand. Allow Accessibility in Settings › Snippets."
- [P1] UI/PanelFeature.swift:102-120 — now: no ⌘N (new), no ⌘⌫ (delete), no ⌘D (duplicate). New and delete are mouse-only · bar: Raycast and Things put create and delete on keys · proposed: ⌘N `newSnippet` with focus moved to the title. ⌘⌫ opens the existing delete alert.
- [P1] UI/SnippetsView.swift:631-681 — now: the argument prompt is opaque `windowBackgroundColor`, radius 14, over a scrim. `handleEscape` (UI/PanelRouter.swift:192) does not check `pendingSnippetArguments`, so Esc may go Home instead of closing the prompt (not run; this depends on whether `.cancelAction` wins) · bar: Esc closes the innermost layer · proposed: add `if panel.pendingSnippetArguments != nil { cancelSnippetArguments(); return true }` first. Render the prompt with `FoundryGlassSurface(.floatingOverlay)`, the same as `PanelPromptOverlay`.
- [P1] UI/SnippetsView.swift:277-285 — now: the row subtitle packs keyword, tags, "used 3×" and the time with "  •  " · bar: the keyword is the most-scanned field and reads as a chip · proposed: the subtitle is the first line of the content, and the keyword goes in a trailing mono badge (`Radius.badge`, `fillTint`). Move use count and date to the editor footer.
- [P2] UI/SnippetsView.swift:30, :164, :482 — now: "1 SNIPPET", "EDIT SNIPPET" and "PREVIEW" are hard-coded caps, while other surfaces use `.textCase(.uppercase)` on Title Case · proposed: "Snippets" + count via `FoundrySectionHeader`. Drop "EDIT SNIPPET", because the editor is self-evident. Write "Preview" with `.textCase(.uppercase)`.
- [P2] UI/SnippetsView.swift:575 — now: the editor sets `NSFont.systemFont(ofSize: 13.5)` directly, while the fields above use 13 · proposed: 13pt regular to match `bodySecondary`, or `mono` behind a toggle like Clipboard's.
- [P2] UI/SnippetsView.swift:292, :523, :141, :325 — now: radii 18/10/9, and `Color.primary.opacity(isHovering ? 0.09 : 0)` slips past the lint · proposed: surface radius 14, fields 8, buttons 8, hover fill `FoundryTheme.fillHover`.
- [P2] UI/SnippetsView.swift:131 vs :243 — now: "Clear filters" is sentence case and "New Snippet" is Title Case · proposed: Title Case for every button: "Clear Filters", "Insert Placeholder".
- [P2] UI/SnippetsView.swift:621 — now: a hand-rolled relative date gives "now", "5m ago", "3d ago" · proposed: `RelativeDateTimeFormatter(.abbreviated)`, which Agents already uses (UI/AgentShelfView.swift:255).
- Empty states are clean: "No snippets yet" + New Snippet. "No matching snippets" + Clear Filters names the fix.

## Quick AI

- [P0] UI/QuickAIView.swift:53 — now: a plain `ScrollView` with no reader, so a streaming answer grows below the fold and the user must scroll · bar: the view follows the stream until the user scrolls up · proposed: wrap it in `ScrollViewReader`, put a bottom anchor after the response, and call `scrollTo(anchor, .bottom)` on `quickAIResponse` change while `isQuickAILoading` and the user hasn't scrolled.
- [P0] UI/QuickAIState.swift:233-238 + UI/QuickAIView.swift:72-80 — now: a provider failure is written into `quickAIResponse` and rendered as an answer in textPrimary · bar: errors look like errors and name the fix · proposed: keep the failure message out of `quickAIResponse` and render `InlineNotice(.error, message, actionTitle: "Retry")`. Map the common cases: 401 "Your API key was rejected. Update it in Settings › AI." 429 "Rate limited by \(provider). Retry in a minute or switch model." Offline "You're offline. Switch to Apple Intelligence or retry."
- [P1] UI/PanelRouter.swift:187 + UI/QuickAIState.swift:59-62 — now: every open (Tab, ⌘N, the Ask AI button) inserts and persists a new empty "New Chat" thread, so the Chats list fills with empties · bar: an empty thread doesn't exist until its first message · proposed: reuse the active thread when it has no messages, and persist on first submit only.
- [P1] UI/QuickAIView.swift:466-470 — now: choosing a model in the footer menu also calls `aiSettings.setDefaultAIProfile`, a global side effect · bar: per-chat choice; the default lives in Settings · proposed: drop `setDefaultAIProfile` here. New chats inherit the last-used profile.
- [P1] UI/QuickAIState.swift:70-72 — now: an empty submit sets `quickAIStatus = "Type a question first"`, which only renders while loading, so Return does nothing visible · bar: nothing to say means no action · proposed: delete the status write and make empty Return a no-op. Dim the footer's Send while the composer is empty.
- [P1] UI/QuickAIView.swift:232-240 — now: `QuickAIShimmerLabel` doesn't shimmer, so "Thinking" is static text · bar: a live process shows it is live, quietly · proposed: put `ProgressView().controlSize(.mini)` before the label (no custom shimmer), and rename the struct to `QuickAIActivityLabel`.
- [P1] UI/QuickAIView.swift:426-453 — now: the thread picker is a `List` of plain Buttons, with no arrow selection, no Return, no dates, no delete or rename · bar: Raycast AI chat list · proposed: a keyboard list (↑↓, ↵ opens, ⌘⌫ deletes) with a relative date trailing each title.
- [P2] UI/QuickAIView.swift:371, :408-410 — now: the composer is 21pt with placeholder alpha 0.34 drawn at a hand-placed `(4,10)`. The root field is 20pt · bar: same size as the root field, with the placeholder on the caret line · proposed: 20pt, `NSColor.placeholderTextColor`, draw at `textContainerInset` + `lineFragmentPadding`.
- [P2] UI/QuickAIView.swift:88 vs :475 — now: "AI Settings" (button) vs "AI Settings…" (menu) · proposed: "AI Settings…" in both, because it opens a window.
- [P2] UI/QuickAIView.swift:135-140 — now: title "Ask anything" repeats the placeholder "Ask anything…", and the body is a shortcut lesson · proposed: drop the title. Keep the three suggestions. Show shortcuts in the footer only: `Send ↵ · New Line ⇧↵ · New Chat ⌘N`.
- Feedback is clean: the copy-answer check swap (UI/QuickAIView.swift:165-168) is the right size. Use it as the model for Developer Tools and Translator.

## File Shelf

- [P1] UI/PanelFeature.swift:208-212 — now: Shelf handles arrows only. Return does nothing, and Space doesn't Quick Look (UI/CommandPanelState+Input.swift:41 is gated to search) · bar: Finder and Raycast: space previews, Return opens · proposed: `handleModeShortcut`: ↵ opens the selection, space toggles Quick Look, ⌘O reveals in Finder, ⌘A selects all.
- [P1] UI/FileShelfView.swift:44-54, :171, :183 — now: header chrome reads "BEN2 Setup", "Cancel BEN2 Setup" and "Remove BEN2 Data". The engine menu reads "Standard (Vision)" / "Try BEN2". The menu also carries a "Cancel" item · bar: name the outcome, not the model · proposed: menu items "Remove Background" and "Remove Background (Detailed)". The detailed one shows "One-time model download" until it is ready. Move "Remove model data…" to Settings. Delete the Cancel item.
- [P1] UI/FileShelfView.swift:48-49 — now: "Remove BEN2 Data" is destructive with no confirmation · proposed: a confirmation dialog: "Delete the background-removal model? You can download it again later."
- [P1] UI/FileShelfView.swift:68-72 — now: the Clear Shelf trash icon sits in the same tint as Convert and Remove Background · bar: destructive is set apart · proposed: move it to ⌘K as "Clear Shelf…" (⇧⌘⌫). If it stays, put it after a `Spacer` with `.destructive` hover tint.
- [P2] UI/FileShelfView.swift:27 — now: "3 WAITING" / "2 SELECTED OF 3" · proposed: "3 Files" / "2 of 3 Selected" through `FoundrySectionHeader`.
- [P2] UI/FileShelfView.swift:152 — now: fallback "Foundry could not process this image." · proposed: "This image couldn't be read. Try a PNG or JPEG."
- Empty state is clean: "Drop files anywhere on Foundry…" names the action and the lifetime.

## File Conversion

- [P1] UI/FileConversionView+Actions.swift:214-236 — now: one button is Convert when idle and "Cancel Conversion" while running, and it keeps `.keyboardShortcut(.defaultAction)`, so a second Return cancels the batch · bar: Return never cancels; esc or ⌘. does · proposed: apply `.defaultAction` only when idle. Bind cancel to ⌘. and show `Cancel ⌘.` in the footer while converting.
- [P1] UI/FileConversionView+Actions.swift:377-384 + UI/FileConversionState.swift:249, :199 — now: any status without `outputURL` gets a warning triangle, including "Tool installed" and "Checking converter readiness…" · bar: the icon matches the outcome · proposed: carry a `level` with `status` (info/success/warning/error) and render it through `InlineNotice`.
- [P1] UI/FileConversionView.swift:89, :105 + UI/FileConversionView+Actions.swift:191 — now: the drop-target stroke, drop icon and progress bar all use `FoundryTheme.warning` (orange) · bar: warning means warning · proposed: drop target `selectionBorder` + `fillSelected`, the same as the panel drop overlay (UI/CommandPanelView.swift:618). Progress tint `accent`.
- [P1] UI/FileConversionView.swift:507 — now: the Name chips show raw templates `{name}-converted` and `{name}-{date}` · bar: show the output · proposed: chip labels "Same name", "photo-converted", "photo-2026-11-01", rendered from the first source's base name.
- [P2] UI/FileConversionView.swift:467 — now: "Max Size: Full / 4K / 2K / 1K / 512" doesn't say which dimension · proposed: label "Longest Edge", values "Original / 4096 / 2048 / 1024 / 512 px".
- [P2] UI/FileConversionView+Actions.swift:56-68 — now: 30×30 `FoundryIconButton`s sit inside a 26pt result row, so they overflow (confirm with a render) · proposed: 24pt mini icon buttons, or a 30pt row.
- [P2] UI/FileConversionView+Actions.swift:239-251 — now: the Convert button invents its own prominent style (ultraThinMaterial + fillSelected + stroke + shadow 12/6, radius 13) · bar: one prominent-control style per app · proposed: `FoundryGlassSurface(role: .prominentControl)` at `Radius.control`, no shadow.
- [P2] UI/FileConversionView.swift:84 — now: `Color.primary.opacity(isDropTargeted ? 0.09 : 0.055)` is off-token · proposed: `fillSelected` / `fillHover`.
- Copy is clean: "No converter for this file yet… Audio and video need FFmpeg." and the install sheet ("Install Only" / "Install and Convert") name the fix and the cost.

## Media Downloads

- [P1] UI/MediaDownloadsView.swift:148-283 — now: the header title "Downloads" sits above a second header (composer, hint line, folder row, capabilities menu): two headers and three text rows before the list · bar: one input header · proposed: put the link composer in the panel header slot, like the Clipboard search. Move the folder and "Change" to ⌘K, and "Supported links" to the empty state.
- [P1] UI/MediaDownloadsView.swift:329-335 — now: selection is a 1.5pt accent stroke, mouse-only (tap toggles), and ⌫ removes it through a hidden button · bar: the same selection language as every list, keyboard-first · proposed: `RowBackground(isSelected:)`, ↑↓ moves (see Shared P0), ↵ opens the file, ⌫ removes.
- [P1] UI/MediaDownloadsView.swift:572 — now: favicons load from `icons.duckduckgo.com` for every host, which sends download hosts to a third party unasked · bar: no silent third-party calls · proposed: reuse the quicklinks "Site icons" setting, or use a bundled glyph per known host (YouTube, Vimeo, X).
- [P1] UI/MediaDownloadsView.swift:371 — now: "Some entries were skipped. Review the remaining text and try again." · proposed: "\(n) links aren't supported and were left in the box."
- [P2] UI/MediaDownloadsView.swift:586 — now: "Copy URL" gives no feedback · proposed: toast "Copied link".
- [P2] UI/MediaDownloadsView.swift:187 — now: Download button opacities 0.34 / 0.92 are raw · proposed: `.disabled` + `prominentControlFill`, and let the disabled style handle dimming.
- [P2] UI/MediaDownloadsView.swift:136, :196, :346, :508 — now: radii 13/12/15/9 · proposed: 14/8/14/8.
- [P2] UI/MediaDownloadsView.swift:315 vs :359 — now: "Clear List" (Title Case) next to "Open download folder" (sentence case) · proposed: "Clear List", "Open Downloads Folder".
- Validation copy is clean: "Paste a full video or audio URL, starting with https://." names the fix. Progress (3pt bar, linear 0.18) and the completion haptic fit the bar.

## Translator

- [P1] UI/TranslatorState.swift:38-39 — now: every open resets to English → Spanish · bar: remember the last pair · proposed: persist `sourceLanguage` and `targetLanguage` in `LocalStateStore`, and reset only the text.
- [P1] UI/TranslatorState.swift:107 — now: `isTranslating = true` before the 450ms debounce, so "Translating" and a spinner flash on every keystroke and the row below shifts · bar: show progress only after real latency · proposed: set `isTranslating` after the debounce. Reserve the status row height so nothing shifts.
- [P1] UI/TranslatorView.swift:54-58 — now: "Try Apple Intelligence" appears for every error, including unavailable and cancelled · proposed: show it only for `.backend` errors. For `.unavailable`: "Download \(language) in System Settings › General › Language & Region › Translation Languages."
- [P1] UI/CommandPanelView.swift:308 vs UI/TranslatorView.swift:63 — now: the footer says "Replace ⌘↵", the button says "Insert", the help says "Paste the translation into the previous app" · proposed: "Replace ⌘↵" everywhere, with help "Replace the selection in \(appName)".
- [P2] UI/TranslatorView.swift:207-217 — now: the copy button gives no feedback, while ⇧⌘C toasts (UI/PanelFeature.swift:133) · proposed: route the button through the same path, or reuse the Quick AI check swap.
- [P2] UI/TranslatorState.swift:32 — now: 12 hard-coded languages, no auto-detect · proposed: source defaults to "Detect", using `NLLanguageRecognizer`. Build the list from `LanguageAvailability().supportedLanguages`.
- [P2] UI/TranslatorView.swift:255 — now: pane radius 18 · proposed: 14.

## Emoji

- [P1] UI/EmojiPickerView.swift:16-19 + UI/EmojiPickerState.swift:75-85 — now: Recent and All share item ids (`id = value`), so a recent emoji highlights in both sections and `scrollTo` is ambiguous. Arrows can't reach Recent at all · bar: one cursor · proposed: one flat navigable list (recents first). Give section-scoped ids, `"recent-\(value)"`.
- [P1] UI/EmojiPickerView.swift:98 + UI/EmojiPickerState.swift:64 — now: cells render the base emoji, while copy applies the skin tone · bar: what you see is what you get · proposed: render `state.toneAppliedValue(item)` in `EmojiCell`.
- [P1] UI/CommandPanelView.swift:334 — now: Return copies and dismisses with no confirmation and no paste · bar: Raycast pastes into the front app · proposed: paste through `directPasteService`, fall back to copy, and show the transient HUD "Pasted 🎉" or "Copied 🎉".
- [P1] UI/CommandPanelView.swift:280-286 — now: the footer reads "Tone ·" when no tone is set, and nothing names the selected emoji · proposed: put the selected emoji's name in the status slot ("party popper"). Footer: `Paste ↵ · Skin Tone ⌘T`.
- [P2] UI/EmojiPickerView.swift:92, :102, :107 — now: the selected fill is `stroke` (0.18) plus a stroke, radius 12, with a 1.08 hover scale · proposed: `RowBackground(isSelected:isHovering:cornerRadius: Radius.row)`. Drop the scale, because hover already fills.
- [P2] UI/EmojiPickerView.swift:59 — now: "No matching emoji" sits under the Results header · proposed: `FoundryEmptyState` "No emoji for “\(query)”" / "Try a feeling or an object, like “happy” or “pizza”."
- [P2] UI/EmojiPickerView.swift:29 — now: the columns button (10/12/14) is a power setting in the header · proposed: move it to Settings or delete it. 12 is fine.

## Developer Tools

- [P1] UI/DeveloperToolsState.swift:142 — now: `copy` writes the pasteboard with no feedback anywhere · proposed: toast "Copied \(label)", for example "Copied HEX".
- [P1] UI/PanelFeature.swift:89-100 — now: ⌘1–7 switch tools, but Return does nothing and Tab between inputs is the only keyboard path · bar: Return copies the primary result · proposed: ↵ copies the first output row; ⌘1–7 stay. Footer `Copy ↵ · Tools ⌘1–7`.
- [P1] UI/CommandPanelView.swift:362 + UI/DeveloperToolsView.swift:144 — now: "Format JSON" appears three times, in the header title, the switcher chip and the section header · proposed: the header title says "Developer Tools", the chip shows the tool, and the section header goes. Keep the subtitle as placeholder help.
- [P1] UI/DeveloperToolsView.swift:66-77 — now: Base Conversion has no `DeveloperPanelSurface` and no section header; the other six do · proposed: wrap it the same way.
- [P2] UI/DeveloperToolsView.swift:393 — now: `Color.red.opacity(0.75)` · proposed: `FoundryTheme.destructive`.
- [P2] UI/DeveloperToolsView.swift:219 — now: `minimumScaleFactor(0.55)` shrinks long values to 7pt · proposed: `.truncationMode(.middle)` with `.help(value)`. Never scale below 11pt.
- [P2] UI/DeveloperToolsView.swift:38-46, :56 — now: a 4-column grid for 7 tools (4+3, ragged), with raw `opacity(… 0.10 : 0.045)` · proposed: one scrolling chip row with `fillSelected` / `fillSubtle`.
- [P2] UI/DeveloperToolsView.swift:186 — now: Word Count padding 18 and spacing 14, the others 14 / 10 · proposed: 14 / 10.
- Error copy is clean: the Base64, JSON and timestamp errors name the fix with an example (UI/DeveloperToolsState.swift:241, :258). This is the model for every other surface.

## Calculator

- [P1] UI/CalculatorViews.swift:155-161 — now: "Use "x" with…" is followed by a gear glyph that does nothing · proposed: drop the gear. Copy: "Use “\(query)” with…" with curly quotes.
- [P2] UI/CalculatorViews.swift:14 — now: the separator is always "→", including for `2+2` · proposed: "=" for arithmetic, "→" for unit and currency conversion.
- [P2] UI/CalculatorViews.swift:86 — now: `minimumScaleFactor(0.45)` lets 20pt shrink to 9pt · proposed: floor at 0.6 (12pt), then truncate.
- [P2] UI/CalculatorViews.swift:10 — now: the fallback expression is "Calculation" · proposed: show the trimmed query.
- Tokens are clean: the card uses `Radius.overlay` (14) and theme fills.

## Camera

- [P1] UI/CameraPreviewView.swift:5-60 — now: a preview with no capture, no mirror toggle and no action; the footer is Home only · bar: a surface earns its place with an action · proposed: see the cut list.
- [P2] UI/CameraPreviewState.swift:19-22 — now: "Camera access is denied" / "Could not start the camera" · proposed: "Foundry can't use the camera. Turn it on in System Settings › Privacy & Security › Camera." / "The camera didn't start. Close other apps using it, then retry."
- [P2] UI/CameraPreviewView.swift:40 — now: Retry shows for `.restricted`, which a retry can't fix · proposed: hide Retry for `.restricted`, and say "Camera use is restricted by a device profile."

## Agents

- [P1] UI/AgentShelfView.swift:29-53 — now: the panel header says "Agents", and the body repeats "Agent Shelf" with the subtitle "2 active · 9 tracked · live updates off" · proposed: drop the body title row. Put "2 active" in the footer status. Show a warning only when the socket is off: "Live updates are off. Open Settings › Agents."
- [P1] UI/AgentShelfView.swift:8 — now: tabs are hard-coded to Cursor, Codex, OpenCode and Claude, while 13 providers exist (UI/AgentMonitorState.swift:276), so a Gemini or Devin session only appears under All · proposed: build tabs from the providers present in `agents.sessions`.
- [P1] UI/AgentShelfView.swift:238 — now: rows that can't open are `.disabled`, dimmed with no reason · proposed: keep them enabled, and on ↵ toast "\(provider) doesn't support jumping to a session yet."
- [P1] UI/AgentShelfView.swift:85-86 — now: "Provider hooks, plugins, and desktop catalogs appear here." is jargon · proposed: "No agent sessions yet" / "Install a bridge in Settings › Agents to see Claude Code, Codex, Cursor and OpenCode here." Action: "Open Agent Settings".
- [P2] UI/AgentMonitorState.swift:311-320 — now: the status vocabulary has both "Working" and "Running" (two greens), and "Recent" is a status that collides with the "Recent" section · proposed: merge Running into Working. Rename the `recent` status to "Idle", or hide its label.
- [P2] UI/AgentShelfView.swift:153 — now: `"\(title.uppercased()) · \(n)"` with tracking 0.8 · proposed: `FoundrySectionHeader(title:count:)`, the same as Clipboard.

## Drag and drop

- [P1] UI/CommandPanelState+Drop.swift:83-91 — now: dropping onto the File Shelf surface still opens the four-way chooser · bar: the target surface implies the action · proposed: in `.fileShelf` mode, call `shelfFiles(urls)` directly.
- [P1] UI/CommandPanelView+Surfaces.swift:28-53 — now: chooser rows all share `fillSubtle`, with no selected row and no arrow keys. Return takes the first and ⌘2–4 the rest · proposed: `RowBackground` with ↑↓ selection, Return on the selected row, and ⌘1–4 shown as `KeycapHint`.
- [P1] UI/CommandPanelState+Drop.swift:96, :108 — now: "Couldn't add those files" · proposed: name the reason from `FileShelfAddResult`, for example "Folders can't go on the shelf. Drop the files inside."
- [P2] UI/CommandPanelState+Drop.swift:58-66 — now: Extract Text on N images starts N parallel actions, which likely opens N Quick Look windows (not run) · proposed: OCR sequentially into one combined text file.
- [P2] UI/CommandPanelView.swift:628 — now: "Drop files to choose what to do" · proposed: "Drop to shelve, convert or compress".

## Settings window

- [P1] Shell/SettingsWindowController.swift:20-24 — now: `setFrameAutosaveName` then `window.center()`, so the restored position is overwritten on every launch · bar: the window reopens where it was left · proposed: call `center()` only when `!window.setFrameUsingName("FoundrySettings")`.
- [P1] UI/Settings/SettingsView.swift:9 — now: `category` is `@State` defaulting to `.general`, so the last pane is forgotten · proposed: `@SceneStorage("settings.category")`, or `LocalStateStore`.
- [P1] UI/Settings/SettingsView.swift:59-126 — now: the rail is plain Buttons, with no ↑↓ between panes and no ⌘1–9, and focus starts in search · bar: System Settings and Linear: arrows walk the sidebar · proposed: `List(selection:)` with `.listStyle(.sidebar)` in a `NavigationSplitView`, which gives arrows, a focus ring and type-select for free. Keep search above it.
- [P0] UI/Settings/QuicklinksSettingsPane.swift:88, UI/Settings/FileSearchSettingsPane.swift:39 — now: "Restore Defaults" replaces every custom quicklink or folder at once, with no confirmation · bar: destructive actions confirm and name their scope · proposed: `confirmationDialog("Replace your \(n) quicklinks with the defaults?")`, role `.destructive`, button "Replace".
- [P1] UI/Settings/SettingsPaneRows.swift:302 — now: "Remove profile" deletes an AI profile and its Keychain key in one click · proposed: confirm with "Remove \(name)? Its API key is deleted from the Keychain." Button title "Remove Profile…".
- [P1] UI/Settings/QuicklinksSettingsPane.swift:42-44 — now: the minus button deletes a quicklink at once, and `.onChange(links)` saves immediately · proposed: an Undo toast, or select-then-⌫ with ⌘Z through `UndoManager`.
- [P1] UI/Settings/SettingsView.swift:962-1017 — now: lowering "Retain items" or "Keep for" trims history live, with no warning · proposed: when the new value drops items, confirm "This removes \(n) older items."
- [P1] UI/Settings/SettingsComponents.swift:149, :165 — now: `SettingsTextFieldRow` and `ConfigFieldRow` commit on Return only, so clicking away loses the edit · bar: live apply, or commit on blur · proposed: also commit on `onChange(of: focus)` when focus leaves.
- [P1] UI/Settings/SettingsComponents.swift:233-262 — now: the shortcut recorder is mouse-only, with no Esc to cancel, no way to clear, and no focus ring · proposed: Space or Return starts recording, esc cancels, ⌫ clears. Draw a focus ring when it is first responder.
- [P1] UI/Settings/SettingsComponents.swift:287 — now: widget reorder and remove controls sit at 0.12 opacity until hover, effectively invisible to keyboard and VoiceOver users · proposed: resting opacity 0.5, full on hover or focus. Remove gets an Undo toast.
- [P1] UI/Settings/QuicklinksSettingsPane.swift:36-58 — now: native `.roundedBorder` fields and checkboxes, while every other pane uses plain fields in groups and switches · proposed: one row component per quicklink (name, keyword, URL) in a `SettingsGroup`. Switches for Enabled and Site Icon, or move them into a disclosure.
- [P2] UI/Settings/SettingsView.swift:619-622 — now: the Appearance pane holds one slider · proposed: merge it into General as "Panel contrast".
- [P2] UI/Settings/SettingsView.swift:405 — now: "Pop to root" is Raycast jargon · proposed: "Return to Home after" / "Reopening sooner than this resumes where you left off."
- [P2] UI/Settings/SettingsComponents.swift:519 — now: help "Rectangle-style suggested shortcut" names another product · proposed: "Suggested shortcut".
- [P2] UI/Settings/SettingsView.swift:419, :443, :490, :998 — now: picker widths 130/110/130/130, so the trailing controls are ragged · proposed: one trailing control column of 140pt for every picker and stepper.
- [P2] UI/Settings/SettingsComponents.swift:28-31 — now: `SettingsGroup` is radius 11, with a `fillSubtle` stroke on a `fillSubtle` fill, so the stroke can't be seen · proposed: `Radius.overlay` (14) or `Radius.row` (10), stroke `separator`.
- [P2] UI/Settings/SettingsComponents.swift:157 — now: the error is indented 44 under a 72pt label + 10 spacing · proposed: indent 82, so the error aligns with the field.
- [P2] UI/Settings/SettingsView.swift:513, :517, :237, UI/Settings/SettingsPaneRows.swift:245-262 — now: "Request access", "Privacy Settings", "Show in Finder", "Sign in with ChatGPT", "Use device code" and "Finish device login" mix sentence case and Title Case · proposed: Title Case for every button, per the HIG: "Request Access", "Use Device Code", "Finish Device Login".
- [P2] UI/Settings/SettingsView.swift:527-597 — now: two hand-built capsule-chip groups (Expand after; Return key) duplicate the same 25-line style · proposed: a native multi-select of toggles for delimiters, and a segmented `Picker` for Insert/Copy.
- [P2] UI/Settings/SettingsView.swift:962-975 — now: the "Retain items" stepper runs from 1 in steps of 50, giving 1, 51, 101 · proposed: a picker with 100 / 250 / 500 / 1,000 / 5,000.
- [P2] UI/Settings/SettingsView.swift:819-851 — now: Settings › Agents lists six tracked sessions, duplicating the Agent Shelf · proposed: delete it.
- Settings search is clean: Return reveals the first match, the anchor highlights, and "No settings match “x”" echoes the query. Reset and Import confirm with scope ("Clipboard history and snippets are kept.").

## The ten changes that would most change how the features feel

1. **⌘K everywhere.** Give every feature list the root's action panel with per-action shortcuts. Collapse Clipboard's eight preview icons, the Shelf header buttons and Media's folder row into it. This one change makes the surfaces keyboard-complete and quiet.
2. **Arrows and Return work on every surface.** Media, Agents, the drop chooser, the AI thread list and the Settings rail get real selection. Shelf gets ↵ open and space Quick Look. Developer Tools gets ↵ copy. Delete every fake "Click" keycap.
3. **Errors appear where they happen.** Route Clipboard, OCR and paste failures to the panel toast. Fix the Settings mislabel. Render Quick AI failures as notices with provider-specific fixes. Copy Developer Tools' error style ("That isn't valid JSON… Example: …") everywhere.
4. **One copy and paste confirmation rule.** Every copy or paste shows "Copied …" / "Pasted …", through the transient HUD when the panel dismisses. That covers Clipboard ↵/⌘↵, Emoji, Developer Tools, the Translator copy button and Media Copy URL.
5. **Esc peels one layer.** In every feature: clear the query, then go Home. The snippet argument prompt closes first.
6. **Browsing never mutates data.** Snippet selection stops touching `updatedAt` and stops reordering. Quick AI stops creating empty threads on open. The model menu stops changing the global default.
7. **Quick AI follows the stream.** Auto-scroll while streaming, a real activity indicator, and a 20pt composer that matches the root field.
8. **One row anatomy and one selection language.** Use the root's row (40pt, 12 padding, radius 10, 13.5 title, 26pt icon, `RowBackground`) for Clipboard, Shelf, Media, Agents, the drop chooser and Emoji cells. Remove the duplicate headers in Agents, Media and Clipboard.
9. **Token collapse with a lint.** 14 radii become 5. Control heights become 24/30/36/40/48. Add two panel motion tokens. Remove keyboard-initiated scroll animation. Delete `EmptyState` in favor of `FoundryEmptyState`. Extend `lint-design.sh` to raw `cornerRadius:` and `.frame(height:` literals so the drift can't return.
10. **Settings behaves like a Mac window.** Remember its frame and pane, use a sidebar with arrow keys, confirm both Restore Defaults and Remove Profile, commit text fields on blur, and color notices by level.

## Cut or merge if a surface can't reach the bar

- **Camera.** A preview with no capture, no mirror toggle and no action. Cut it, or replace it with a "Mirror" command that opens Photo Booth.
- **Developer Tools → root inline results + ⌘K transforms.** The root already parses `5 & 3` and `5 << 1` (UI/DeveloperToolsView.swift:83). Base conversion, timestamp, case and word count fit inline results or clipboard-item actions ("Format as JSON", "Decode Base64"). Seven tools behind a mode tax every use with a mode switch.
- **Translator → a root result + Quick AI.** The `.translation` result kind already exists (UI/CommandPanelView.swift:875). Without remembered pairs, auto-detect and the full language list, the full surface adds little over an inline result with "Replace ⌘↵".
- **Settings › Appearance.** One slider. Merge it into General.
- **Settings › Agents › Tracked sessions.** It duplicates the Agent Shelf. Cut it.
- **Snippets' in-panel Auto-expand switch and the BEN2 controls in the Shelf header.** Both are settings dressed as surface chrome. Move them to Settings.

Model: claude-opus-5-5.
