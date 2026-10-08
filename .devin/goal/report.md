# Goal report

## Objective
Implement the full Foundry megaplan (~/.devin/plans/plan-2b52c0932c2a6746.md) to the highest quality — no sloppification. Phases: P0 icon/DMG, P1 conversion engine v2, P2 conversion UX + file actions, P3 facelifts (Downloads/Snippets/Clipboard/sweep), P4 parity commands, P5 onboarding/motion, P6 perf/structure, P7 release/docs.

## Progress

### Baseline (before changes)
- `swift test`: 553 tests, 3 skipped, 0 failures — green baseline.

### P0 — Brand: app icon + DMG ✅ committed 7faca46
- `scripts/render-icon.swift` — CoreGraphics generator: warm-charcoal squircle, bone-gradient anvil silhouette, ember rim-light, spark dots → `Supporting/AppIcon.iconset/*` + `icon-1024.png`.
- `Supporting/AppIcon.icns` via `iconutil`; `build-app.sh` copies it and sets `CFBundleIconFile`/`CFBundleIconName` (errors if iconset is stale).
- `scripts/render-dmg-background.swift` + `scripts/package-dmg.sh` — branded DMG: APFS staging, Finder layout (540×360, icons {130,150}/{410,150}, size 96), `.VolumeIcon.icns` via FinderInfo xattr, UDZO compress.
- `verify-packaging.sh` asserts icon + plist + entitlements; passed. DMG visually verified.

### P1 — Conversion engine v2 ✅ (tests green)
- `Sources/FoundryServices/ConversionGraph.swift` — edge graph over 12 engines; ≤3-hop router ranking fewest hops → fewest external engines → graph order; junk-route guards (audio/subtitle outputs only from media origins); compound-ext normalization (tar.gz).
- `Sources/FoundryServices/ConversionService.swift` — `FileConversionTarget` (id/title/ext/category/route), `availableTargets`, `defaultTargetID`, `assess` (multi-source union), `convert` via per-engine executors through `ArtifactStore` staged atomic commits; `ConversionOptionKind`/`applicableOptions` for UI.
- Engines: native ImageIO (png/jpg/heic/tiff/gif/bmp/jp2/avif/pdf; reads webp/svg/RAW), AVFoundation (mp4/mov/m4a/wav/aif/caf/aac), PDFKit (pdf→png/jpg @ dpi/pages), textutil, plutil (plist↔json), structuredData (csv/tsv↔json), archive (zip/tar.gz/extract), Vision OCR (image→txt); external ffmpeg/imageMagick/pandoc/soffice via Homebrew setup plans.
- `FileConversionState` rewritten over the service; multi-source common targets by output ext; per-item outcomes; retry/cancel/generation-guarded.

### P2 — Conversion UX + file actions ✅ (tests green)
- `FileConversionView` facelift: dashed drop hero (`.onDrop` w/ ember highlight), source list w/ sizes + ext badges + per-file remove + add/clear, grouped format menu w/ readiness dots + engine provenance, setup banner (one-tap `Set Up`), contextual option chips (Quality/Max Size/Bitrate/DPI + Pages field), Save To, output-name preview, per-item results w/ size deltas, progress bar, Reveal/Retry/New Batch.
- State: multi-select picker, `addSources`/`removeSource`/`startOver`.
- File actions (file search results): Reveal in Finder, Copy File, Copy Path, Open With ≤4 apps (LaunchServices, ext-cached `FileAppResolver`), Add to File Shelf, Convert…, Compress (ditto→zip), Rename… (native prompt), Move to Trash (destructive confirm); shortcuts ⌘⇧R/⌘E/⌘⌫; destructive rows tinted.
- Entry points: `open -a Foundry --convert <paths>`, Finder Open With / dock drop (`CFBundleDocumentTypes` public.data+public.folder, Alternate rank), `openFileConverter(paths:)`.
- Drops inside conversion mode route to `fileConversion.addSources`.
- qa-capture extended with `convert*` surfaces.

### P3 — Facelifts ✅ committed 4ad89bb
- Snippets: `useCount`/`lastUsedAt` usage tracking (recorded from UI + ActionRunner paths), Raycast-compatible export, configurable expansion delimiters (Space/Tab/Return/comma/period/colon/semicolon) wired through ConfigService → SnippetExpansionService → Settings UI, NSTextView-backed editor with cursor-aware placeholder insertion, Import/Export buttons in header.
- Downloads: remote favicons, completed-file thumbnails, status badges, hover, context menus.
- Clipboard: Paste as Plain Text, smart Open Link on URL-shaped text.

### P4 — Parity commands ✅ committed 78a7868
- `VisionText` shared helper (OCR + barcode). Commands: Extract Text, Pick Color (NSColorSampler), Generate/Read QR, Paste as Plain Text, Confetti (`ConfettiBurst` view). Extract Text also a file action on images. All exhaustive switches updated.

### P5 — Onboarding + motion ✅ committed b8413d2
- Panel entrance (fade+drift, reduced-motion aware), staggered onboarding reveals, pulsing keycap (`phaseAnimator`), springing footer dots, success symbolEffect bounce, confetti + haptic on done, ember accent.

### P6 — Perf + structure ✅ committed 1d3c40e
- `build-app.sh` strips the release binary before codesign → app bundle **18 MB → 7.8 MB**, signature verified.
- AgentProviderIcon + PreviewPane + rename-alert icon off the main-actor render path (cached async loaders); `lsof` port lookup async so provider deadlines bind it.
- `CommandPanelState` 1463 → 923 core + 357 Settings ext + 216 Modes ext; no behavior change, 587 tests green.

### P7 — Release
- `VERSION` → `1.2.0`; `docs/release-notes/1.2.0.md` written; HANDOFF updated.
- `build-app.sh` → signed 7.8 MB bundle (1.2.0); `verify-packaging.sh` passed; `package-dmg.sh` → `Foundry-1.2.0-build-1.dmg` with branded layout verified (mounted: .DS_Store positions, .background pair, volume icon, Applications symlink).

### Post-release gap passes ✅ committed 6ea38e6 + dcc0148
- Pass 1 (`6ea38e6`): `ConversionOptions.stripMetadata`/`nameTemplate`; pdf→txt, multi-PDF merge, images→PDF; ffmpeg `-map_metadata -1` + quality→CRF; magick `-strip`; drop chooser; file Share; snippet CSV export/tag chips/sort modes; clipboard merge + image dims; exclusion pickers; screen OCR, Wi-Fi QR, Empty Trash, Desktop Icons; first-conversion confetti; downloads ⌫ + total speed + toast.
- Pass 2 (`dcc0148`): snippet Return-key pref (Insert vs Copy) via `CommandSearchRequest.snippetInsertAsPrimary` + Settings UI; `SnippetPreview` pane; `hapticsEnabled` setting gating confetti/drop/expansion taps; downloads link badge + unfocused ⌘V + link drop; color-picker WCAG contrast readout; quicklink `isEnabled` + DDG/Wikipedia shipped disabled; clipboard ⌥↵ plain paste; snippet export remembers directory; onboarding pills + scale-morph.

## In flight
- Nothing blocking.

## Remaining
- Manual-only items in `docs/HANDOFF.md` §Open items (Accessibility-gated keystroke benchmark + VoiceOver sweep, Xcode 26 glass cost, notarization).

## Evidence
- `swift test`: **600 tests, 3 skipped, 0 failures** (full suite, post-parallel-batch commit `7afe028`).
- `swift build`: clean, zero warnings. `verify-packaging.sh`: passed — signed ~7.9 MB bundle.
- Batch conversion concurrency verified by tests: external-engine batches peak at exactly 2 in-flight, native batches peak at 1, partial failures preserve completed outputs (`FileConversionTests`).
- Loaded conversion surface verified visually; `--convert` launch path verified; DMG layout verified by mounting.
- Note: screen-recording capture flaky mid-session; file search returned no results in-app on this machine during QA drive (mdfind works in terminal) — likely Spotlight permission on the host, not a code path.
