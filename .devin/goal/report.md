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

## In flight
- Nothing blocking.

## Remaining
- P3: Downloads facelift; Snippets (placeholder menu, export, usage counts, delimiters); Clipboard paste-plain; surface sweep.
- P4: OCR, color picker, QR gen/decode, caffeinate, confetti, plain-text paste.
- P5: onboarding glass/motion polish + activation instrumentation.
- P6: perf budgets, CommandPanelState split, lazy features, bundle diet.
- P7: version bump, release notes, docs, final verification + code-review pass.

## Evidence
- `swift test`: 577 tests, 3 skipped, 0 failures (post P1+P2).
- Loaded conversion surface verified visually (PNG→JPEG w/ options, readiness, preview); empty hero verified; `--convert` launch path verified.
- Note: screen-recording capture flaky mid-session; file search returned no results in-app on this machine during QA drive (mdfind works in terminal) — flagged for P6 debugging.
