# Foundry: the last 20% Implementation Plan

Status (2026-11-09): executed. This is the plan for the website and brand. Its design is `2026-11-01-foundry-last-20-design.md`. It is not the app plan (see `2026-11-01-foundry-last-20-percent.md`). Merged into `main` as `6bf3fdf` and released in 1.3.0.

> **For Claude:** REQUIRED SUB-SKILL: Use `executing-plans` to implement task-by-task. Load `design-engineering` (it routes to the specialists) for every UI task, `emil-design-eng` for motion, `clean-copy` and `prose` for copy, `logo-design` then `brand-identity` for Track A, `verification-before-completion` before any "done".

**Goal:** Take the Foundry website from "works and looks right" to a page the best product studios would sign, with a mark that is not a letter and a dot, every claim true and regenerable, and the install free of apologies.

**Architecture:** One brand token file (`docs/brand/tokens.json`) feeds the site CSS, the Swift theme, the icon and DMG renderers and the OG image. One `Palette` React component is the hero demo and the site-wide ⌘K. One `proof.ts` module reads `VERSION` and `docs/benchmarks/*.json` at build so numbers on the page cannot drift from the repo. Visual work is verified by a Playwright QA script that writes screenshots, Lighthouse and axe JSON to `docs/qa/2026-11-01-website/`, and by two fresh-context critics.

**Tech Stack:** Next.js 16.2.7, React 19, motion 12, three 0.185, Tailwind 4 (only the preflight is in use; the site is plain CSS), Geist via next/font, Node 26 (native TypeScript stripping for `node --test`), Playwright (new devDependency, QA only), Swift 6 package for the app-side touchpoints (`blaze build` / `blaze test` per AGENTS.md).

Design doc: `docs/plans/2026-11-01-foundry-last-20-design.md`. Brand research: `docs/brand/RESEARCH-websites.md` (done, Sonnet 5.5, 25 ranked items in its section 5; this plan absorbs them, and the item numbers appear as `R#` below), `docs/brand/concepts/RESEARCH.md`, `docs/brand/concepts/CONCEPTS.md` (the last two are produced by the Codex gpt-6.1-sol imagegen round that this plan's Task A1 consumes).

Four corrections from the research that change claims on the page:
- Raycast is native Swift/AppKit that leans on web views; it is not Electron. The site may say "no web view", never "no Electron".
- Against Tinycast, Foundry loses on memory (about 40 MB vs 60 to 120 MB, `docs/benchmarks/2026-09-29-foundry-1.1-tinycast-0.11.3-mbp-report.md`) and wins on panel-open latency (17 to 19 ms vs 65 ms). Latency is the claim to lead with. The 81% figure stays scoped to Raycast and the Tinycast row goes on the methodology page (R5).
- `docs/distribution.md` says the release workflow notarizes when signing secrets are set; the modal says the build is not notarized. Task B2 settles which is true for the DMG served by `releases/latest`.
- One August 2026 guide reports that macOS Tahoe's warning dialog no longer shows Open Anyway. Single source; Task B2 branch 2 tests the steps on macOS 26 and 27 before writing them.

Commits: the user did not ask for commits in this planning session. During execution, commit at the end of each task on branch `website-tile-world`. Never sweep `launch-film/`, `foundry-ad/`, `.devin/` or `Sources/` into a site commit, and never sweep `anvil/` into an app commit (HANDOFF.md rule).

Conventions for every task:
- Site commands run from `anvil/` (`cd anvil` first). App commands run from the repo root.
- Dev server: `npm run dev -- -p 3123`. If `next dev` reports a broken SWC binary, `rm -rf node_modules/@next/swc-darwin-arm64 && npm install`; on 2026-11-01 the registry was slow and the tarball had to be fetched with `curl --retry 8` and extracted by hand.
- Screenshots are judged by eye. Open every PNG the QA script writes. A capture with entrance motion mid-flight is not evidence.
- No comments in code (AGENTS.md). No new abstractions without a demonstrated second caller.

---

## Phase 0: Measure before touching anything

### Task 0.1: QA script (screenshots, axe, Lighthouse)

**Files:** Create `anvil/scripts/qa.mjs`, `anvil/scripts/qa-routes.json`; Modify `anvil/package.json` (devDependencies `playwright`, `@axe-core/playwright`, `lighthouse`; script `"qa": "node scripts/qa.mjs"`); Create `docs/qa/2026-11-01-website/README.md`.

**Step 1: Write the failing test.** `anvil/scripts/qa.test.mjs` with `node --test`: imports `routesFrom(qa-routes.json)` and asserts it yields `{ path: "/", stops: [0, 0.6, 1.3, 1.9, 2.3, storyEnd] }` style entries plus `/methodology` and `/missing-page`. Asserts `shotName({path:"/", width:1440, stop:1.3})` is `home-1440-at1.300.png`.

**Step 2: Run it.** `node --test scripts/qa.test.mjs`. Expected: FAIL, `Cannot find module`.

**Step 3: Minimal implementation.** `qa.mjs` launches Chromium at 1440×900, 768×1024, 390×844, visits each route with `?inspect=1&at=<stop>` (the page already supports this, see `app/page.tsx`), waits for `document.fonts.ready` and `[data-scene]` to be `ready` or `still`, screenshots full page, runs axe and writes `axe-<name>.json`, runs Lighthouse (mobile preset, categories performance, accessibility, best-practices, seo) once per route and writes `lh-<route>.json`. Output dir from `QA_OUT` env, default `../docs/qa/<date>-website`. Writes `contact-sheet.html` listing every PNG.

**Step 4: Run it.** `node --test scripts/qa.test.mjs` PASS. Then `npm run qa` against the dev server; open the contact sheet and every PNG.

**Step 5: Record the baseline.** `docs/qa/2026-11-01-website/README.md` lists: Lighthouse scores per route, axe violation count, bytes shipped on `/` (from the Lighthouse JSON `network-requests` audit), LCP, and a one-line note per screenshot of anything wrong. This file is the "before".

### Task 0.2: First-paint flash and font check

**Files:** Modify `anvil/scripts/qa.mjs` (add a `trace` mode).

**Step 1:** Add `--trace` to `qa.mjs`: records a Playwright trace of `/` at 1440 from navigation to `data-scene="ready"`, then screenshots every 50 ms for 2 s into `trace-<n>.png`.
**Step 2:** Run `node scripts/qa.mjs --trace`. Open the frames. Record in README whether the SVG wordmark is visible before the WebGL tiles, whether both are visible at once, and whether the hero copy moves.
**Step 3:** In the same run, evaluate `document.fonts.check("16px Geist")` and `getComputedStyle(h1).fontFamily`; record the result. If Geist is not the rendered face, every typographic judgement below is void until fixed.

### Task 0.3: Fresh-context critique of the baseline

**Files:** Create `docs/qa/2026-11-01-website/critique-before.md`.

**Step 1:** Delegate one review to a design critic with no transcript (per the user's standing preference, `claude-opus-5-5` via `delegate_task`, target `{"providerInstanceId":"claudeAgent","model":"claude-opus-5-5"}`). Give it only: the PNGs from Task 0.1, the idea line "The app you never open. Opens everything.", and the reviewer prompt from `design-slop/references/review.md`. Ask for findings with severity, location, before, after, principle, and one of `recapture`, `rebuild`, `fix`, `ship`.
**Step 2:** Save the result verbatim. Fold each finding into the matching task below as an acceptance line. Nothing is "fixed" until the recapture is scored against the finding.

---

## Phase A: Brand

### Task A1: Choose the mark

**Files:** Read `docs/brand/concepts/CONCEPTS.md`, `docs/brand/concepts/*.png`, `docs/brand/concepts/RESEARCH.md`, `docs/brand/RESEARCH-websites.md`. Create `docs/brand/SHORTLIST.md`.

**Step 1:** Load `logo-design`. Run its application-context test on every concept: 16 px menu bar template, 28 px, 1024 px icon beside Raycast, Cursor, Arc, Linear in a Dock mock, favicon in a tab strip, single colour, reverse. A concept failing three contexts is out.
**Step 2 (done 2026-11-01):** `docs/brand/SHORTLIST.md` holds four candidates: Pressed tile (a 2 × 2 of chalk keycaps with one pressed so its orange side shows; not from the Codex set, built from the site's own tile material), Registration (Codex 06), Spacebar (Codex 08), Ingot Gate (Codex 03). Recommendation: Pressed tile, Registration as fallback.
**Step 3 (decided 2026-11-01):** The user chose **Split Mould (Codex 02)** with **Command Joint (Codex 05)** as the alternate. A3 draws Split Mould first: two mould halves on the tile grid, the stepped cavity between them, one orange cast in the centre. Acceptance at 16 px: not a pair of code brackets, not a QR glyph, channel at least 2 device pixels at 1x, orange only on the cast. If the first vector fails that reading, draw Command Joint (two loops, never four, so it is not the ⌘ symbol) and bring both to the user as 16 px and Dock captures.

### Task A2: One brand token file

**Files:** Create `docs/brand/tokens.json`; Create `anvil/scripts/build-tokens.mjs`; Create `anvil/app/foundry/tokens.css` (generated, committed); Modify `anvil/app/foundry/foundry.css:4-10` (`--f-*` read from `tokens.css`), `anvil/app/foundry/launcher.css:1-8`, `anvil/app/not-found.css`, `anvil/app/methodology/methodology.css`, `anvil/app/foundry/story/*.css` (every hard-coded `#fa6428`, `#f36f39`, `#c6bbab`, `#d6cdbd`, `#ffa36c`, `#f0672b`, `#c94b19`, `#eee7dd`, `#0f0d0c`); Modify `Sources/Foundry/UI/FoundryTheme.swift:208-233` (`enum Brand` values match the file); Modify `scripts/render-icon.swift` and `scripts/render-dmg-background.swift` (read the same hex values); Create `Tests/FoundryTests/BrandTokensTests.swift`.

**Step 1: Write the failing tests.** (a) `anvil/scripts/build-tokens.test.mjs`: `cssFrom(tokens)` emits `:root{--f-ink:#0f0d0c;...}` and errors on a key without a `#rrggbb` value. (b) `BrandTokensTests.swift`: decodes `docs/brand/tokens.json` (path from `#filePath`) and asserts `FoundryTheme.Brand.accent`, `ink`, `chalkTop`, `chalkBottom` equal the file to 1/255.
**Step 2: Run.** `node --test scripts/build-tokens.test.mjs` FAIL (module missing); `blaze test --filter BrandTokensTests` FAIL (file missing).
**Step 3: Implement.** `tokens.json` schema: `{ "ink", "inkRaised", "chalk": {"top","mid","bottom","sideTop","sideBottom"}, "orange": {"face","side","deep"}, "text", "muted", "line", "tile": {"radius": 0.18, "gap": 0.1}, "type": {"family":"Geist","weights":[400,500,600]}, "motion": {"easeOut":[0.23,1,0.32,1], "press": 120, "state": 220, "enter": 450} }`. Values: today's site values are the source of truth (`#0f0d0c`, `#eee7dd`, `#bdb4aa`, `#fa6428`, `#484039`, chalk `#f2ecdf/#e3dbcc/#d2c7b3`, sides `#a99d8a/#857a69`, orange side `#99300a`). The film and ad palettes are retired. `build-tokens.mjs` writes `tokens.css`; `npm run build` runs it first (`"prebuild"`). The Swift side keeps literal values but the test pins them to the file.
**Step 4: Run.** Both tests PASS. `npm run build` succeeds. `grep -rn "#fa6428\|#f36f39\|#c94b19" anvil/app` returns only `tokens.css`.
**Step 5:** `docs/brand/BRAND.md`: the palette with roles, the tile rules (radius 18%, gap 10%, chalk face and orange side, never a gradient on a flat surface), Geist weights in use (400 display, 500 UI, 600 wordmark), motion tokens, and the one rule for the orange: it closes a sentence or marks the selected thing, never decorates.

### Task A3: Production mark (after the A1 answer)

**Files:** Create `docs/brand/mark/mark.svg`, `mark-mono.svg`, `mark-grid.svg`, `wordmark-lockup.svg`; Create `anvil/app/icon.svg` (Next picks it up as favicon), `anvil/app/apple-icon.png` (180 px), Modify `anvil/app/favicon.ico` (regenerated); Modify `anvil/app/layout.tsx` (`themeColor: "#0f0d0c"`, icons); Modify `scripts/render-icon.swift` (draws the chosen mark), `Supporting/AppIcon.iconset/*`, `Supporting/icon-1024.png`, `Supporting/AppIcon.icns`; Modify `Sources/Foundry/UI/Onboarding/CastMark.swift:117` (`menuBarImage` draws the chosen mark as a template at 14 pt); Modify `scripts/render-dmg-background.swift`; Modify `anvil/app/opengraph-image.png` (regenerated from the lockup); Modify `anvil/app/foundry/site-chrome.tsx:12,20` (header and footer use the lockup SVG, not text).

**Step 1: Construction.** Draw the mark on the tile grid in SVG by hand (not the imagegen PNG; the PNG is the concept, the SVG is the mark). `mark-grid.svg` shows the grid, the tile count and the full stop position. Record the construction in `BRAND.md`.
**Step 2: Write the failing tests.** `anvil/scripts/mark.test.mjs`: `mark.svg` has a `viewBox` of `0 0 N N` with N a multiple of the tile count, every `<rect>` snaps to the grid, exactly one element carries the orange token, and `mark-mono.svg` has no `fill` other than `currentColor`. `Tests/FoundryTests/MenuBarMarkTests.swift`: `MarkTiles.menuBarImage.isTemplate` is true, size is 14×14 pt or the lockup width at 14 pt high, and the rendered bitmap at 1x has at least one fully opaque and one fully transparent pixel (a glyph, not a blob).
**Step 3: Run.** Both FAIL.
**Step 4: Implement** the SVGs, the Swift mark, and regenerate every raster: `swift scripts/render-icon.swift && iconutil -c icns Supporting/AppIcon.iconset -o Supporting/AppIcon.icns`, `swift scripts/render-dmg-background.swift`, favicon.ico from icon.svg (`rsvg-convert` or a Playwright render at 16/32/48), OG image at 1200×630 by rendering `anvil/app/brand/og.html` through Playwright.
**Step 5: Run.** Tests PASS. `./scripts/build-app.sh` then `./scripts/verify-packaging.sh` PASS.
**Step 6: Verify by looking (the bar from `progress.md`).** Install the built app into a QA bundle, screenshot the real Dock with Raycast, Cursor, Arc, Linear, Safari beside it (light and dark Dock), screenshot the real menu bar at 1x and 2x, screenshot a Safari tab strip with the favicon between GitHub and Linear tabs. Save to `docs/qa/2026-11-01-website/mark-*.png`. The mark is done when it does not look weaker than its neighbours in any of these. If it does, go back to Step 1, not to Step 4.

### Task A4: `/brand` page

**Files:** Create `anvil/app/brand/page.tsx`, `anvil/app/brand/brand.css`, `anvil/public/brand/foundry-brand.zip` (built by `anvil/scripts/build-brand-kit.mjs` from `docs/brand/mark/*` and `tokens.json`); Modify `anvil/app/sitemap.ts` (add `/brand`), `anvil/app/foundry/site-chrome.tsx` (footer link "Brand").

**Step 1:** Test: `build-brand-kit.test.mjs` asserts the zip lists `mark.svg`, `mark-mono.svg`, `wordmark-lockup.svg`, `icon-1024.png`, `tokens.json`, `BRAND.md`.
**Step 2:** FAIL. **Step 3:** Implement the page: the mark large on ink, the construction grid beside it, the palette as tiles with hex and role, "Do" and "Do not" rows (minimum size 16 px, clear space one tile, never recolour, never on a photo), one download button. Same chrome as `/methodology`. **Step 4:** PASS, `npm run qa` includes `/brand` and the screenshots are clean at all three widths.

---

## Phase B: Truth and proof

### Task B1: Version and release from one source

**Files:** Create `anvil/app/proof.ts`; Modify `anvil/app/site.ts` (export `version` from `proof.ts`), `anvil/app/page.tsx:19` (`softwareVersion: version`), `anvil/app/foundry/story/download.tsx:19` (`v{version} · macOS 14+ · Open source`), `anvil/next.config.ts` (`outputFileTracingIncludes` for `../VERSION` and `../docs/benchmarks/*.json`); Create `anvil/app/proof.test.ts`.

**Step 1: Write the failing test.** `node --test app/proof.test.ts`: `readVersion("/path/with/VERSION")` returns the trimmed string and throws when the file is missing; `releasedVersion()` (reads `https://api.github.com/repos/hridaya423/foundry/releases/latest` at build, cached, 5 s timeout) returns `"1.1.0"`-shaped strings or `null`; `displayVersion({repo:"1.2.0", released:"1.1.0"})` returns `"1.1"` and logs a build warning naming both.
**Step 2:** FAIL. **Step 3:** Implement. The site displays the *released* version; the repo version only wins when a release with that tag exists. The warning appears in `next build` output so a mismatch is loud. **Step 4:** PASS; `npm run build` prints the warning today (1.2.0 unreleased vs 1.1.0 released).
**Step 5 (gate, user decision):** Ask the user whether to publish 1.2.0 now (pushing `VERSION` triggers `.github/workflows/release.yml`, a one-way action). Either answer leaves the site truthful.

### Task B2: Delete the apology (notarization) or make it honest

**Files (branch 1, notarize):** Modify `scripts/build-app.sh` (call `scripts/notarize-dmg.sh` when `NOTARY_PROFILE` is set), `.github/workflows/release.yml` (notarize step with secrets); Delete `anvil/app/foundry/download-gate.tsx` and `.dl-*` rules in `foundry.css:230-340`; Modify every `DownloadLink` call site (`hero-content.tsx`, `site-chrome.tsx`, `story/download.tsx`) to a plain `<a href={foundryDownloadUrl} download>`.
**Files (branch 2, keep the modal):** Modify `download-gate.tsx:58` (`⌘` not `⌥`, read the chord from one constant in `site.ts`), delay `setOpen(true)` until the `download` attribute click has fired (the browser starts the download; the modal opens on `requestAnimationFrame`), replace the `×` with the 16 px close glyph from the palette icon set, add `aria-describedby`, trap focus, restore focus to the trigger on close.

**Step 0:** Establish the truth of the served DMG: `curl -L -o /tmp/Foundry.dmg https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg && spctl -a -vv -t install /tmp/Foundry.dmg && xcrun stapler validate /tmp/Foundry.dmg`. Record the output. This decides whether the modal's "isn't notarized" sentence is already false (R3).
**Step 1 (gate, user decision):** Ask: notarize now (recommended; `scripts/notarize-dmg.sh` already exists and needs only `xcrun notarytool store-credentials`, and `docs/distribution.md` says the release workflow does it when secrets are set) or keep the modal. Branch 2 must first walk the real Gatekeeper dialog on macOS 26 and 27 and write only the steps the dialog shows (R2).
**Step 2: Write the failing test.** Branch 1: `verify-packaging.sh` gains `spctl -a -vv -t install build/Foundry-*.dmg` expecting `accepted` and `stapler validate` expecting success. Branch 2: `download-gate.test.tsx` (React Testing Library is not installed; test the pure helper instead: `installSteps(chord)` returns four strings containing `⌘ Space` and none containing `⌥`).
**Step 3:** FAIL. **Step 4:** Implement the chosen branch. **Step 5:** PASS. Walk the install for real: download from the local site, mount, drag, first launch. Screenshot each step into `docs/qa/2026-11-01-website/install-*.png`. Branch 1 has no warning dialog at all; that screenshot is the proof.

### Task B3: Proof page and proof strip

**Files:** Create `anvil/app/proof/page.tsx`, `anvil/app/proof/proof.css`; Modify `anvil/app/proof.ts` (readers for `docs/benchmarks/2026-10-12-search-latency.md` numbers via the JSON that produced them, `2026-09-29-foundry-1.1-raycast-2.5.3-mbp-forward.json` and `-reverse.json`, bundle size from the release asset list, test count from `swift test` output stored in `docs/benchmarks/latest.json`); Create `scripts/write-benchmark-summary.sh` (writes `docs/benchmarks/latest.json` with `{version, searchImmediateP95, searchCompleteP95, warmedMemoryMB, raycastWarmedMemoryMB, bundleMB, tests, dependencies: 0, capturedAt, sources: [...]}`); Modify `anvil/app/foundry/story/download.tsx` (a four-figure proof strip under the CTA: memory, p95, size, dependencies); Modify `anvil/app/sitemap.ts`, `site-chrome.tsx` (footer "Proof").

**Step 1: Write the failing test.** `proof.test.ts`: `proofFigures(latest.json)` returns figures each with `value`, `unit`, `label`, `source` (a path under `docs/benchmarks/`), and throws if any figure lacks a source. `formatFigure({value: 115.2, unit:"MB"})` is `"115 MB"` via `Intl.NumberFormat`.
**Step 2:** FAIL. **Step 3:** Implement. The page is a table of figures, each row: the number set in tiles (reuse `Tiles` from `launcher.tsx`), the sentence it supports, the machine, the date, and a link to the source file and the methodology. The strip under the download CTA uses `tabular-nums` and ticks from 0 once on reveal (`animate` from motion, 1.2 s, `[0.16, 1, 0.3, 1]`, skipped under reduced motion, final value announced via `aria-live="polite"`).
The strip leads with latency, "17 ms to open" with p50 and p95 and the machine (R4), then memory scoped to "vs Raycast 2.5.3", then size, then dependencies. `/methodology` gains a Tinycast row stating the memory loss and the latency win plainly (R5). SHA-256 of the served DMG and the DMG size sit beside the download button (R6), computed at build from the release asset.
**Step 4:** PASS. `npm run qa` includes `/proof`. Every figure on the page is clickable to its file. The word "Provisional" appears once on `/methodology` and nowhere else; the strip's label says "measured 29 Sep 2026" instead.

### Task B4: Licence and privacy

**Files:** Create `LICENSE` (repo root; recommend MIT, the user confirms in the same question as B1); Create `anvil/app/privacy/page.tsx`; Modify `anvil/app/foundry/story/download.tsx` (one line under the strip: "Clipboard history stays on your Mac in SQLite. No account, no telemetry. AI keys live in Keychain."), `site-chrome.tsx` (footer: version, size, licence, Privacy, Proof, Brand, Changelog, GitHub).

**Step 1:** Test: `site-chrome` footer link list is a data array in `site.ts`; `node --test` asserts every `href` is either internal and present in `sitemap.ts` or external and `https`. **Step 2:** FAIL. **Step 3:** Implement; the privacy page lists exactly what leaves the machine and nothing else (R7): Frankfurter for currency rates, Homebrew for yt-dlp and conversion tools, the AI provider the user configured, remote favicons for downloads. Then what never leaves: clipboard, snippets, files, usage ranking. Crash reports none, analytics none, updates none yet. Verify each sentence against the code (`ClipboardHistoryStore`, `AIProvider`, `CurrencyProvider`, `MediaDownload*`, `DiagnosticsService`) before writing it. Add a short maker's note in first person with a name (R22); the user writes it, the executor places it. **Step 4:** PASS.

### Task B5: Changelog page

**Files:** Create `anvil/app/changelog/page.tsx`, `anvil/app/changelog/changelog.css`, `anvil/app/changelog.ts` (reads `docs/release-notes/*.md` at build, parses `#`/`##`/`-` only); Modify `docs/release-notes/1.2.0.md` (the "Brand" section describes the real icon, not the forge-anvil one); Modify `site-chrome.tsx` ("Release notes" points to `/changelog`), `sitemap.ts`.

**Step 1:** Test: `parseReleaseNotes("# Foundry 1.2.0\n\n## Brand\n- a\n- b")` returns `{version:"1.2.0", sections:[{title:"Brand", items:["a","b"]}]}`; unknown markdown throws with the line number. **Step 2:** FAIL. **Step 3:** Implement. Each version is a heading in tiles with the version number, the date from the GitHub release when it exists, sections as plain lists, a download link for that version's DMG, and `anvil/app/changelog/feed.xml/route.ts` serving an Atom feed (R9). **Step 4:** PASS; screenshots clean at three widths; the feed validates with `xmllint --noout`.

---

## Phase C: Craft

### Task C1: One Palette, faithful to the app

**Files:** Create `anvil/app/foundry/palette/palette.tsx`, `palette.css`, `palette-commands.ts`, `palette-geometry.ts`; Modify `anvil/app/foundry/launcher.tsx` (becomes a thin wrapper that mounts `Palette` in `hero` mode and keeps the typing demo), `launcher.css` (geometry from `palette-geometry.ts` and colours from `tokens.css`), `story/tools.tsx:85-95` (the compact launcher uses `Palette` in `row` mode); Create `anvil/app/foundry/palette/palette-geometry.test.ts`.

**Step 1: Capture the truth.** Build and run the app (`INSTALL_APP=0 ./scripts/build-app.sh`, launch `build/Foundry.app`), open the panel with the query `png`, capture at 2x with `scripts/qa-capture.swift`. Save `docs/qa/2026-11-01-website/panel-real.png`. Measure: panel width 750 pt, row 44 pt, icon 28 pt, title 13.5 medium, detail line, kind label, selection border, section header tracked caps, footer. Write them into `palette-geometry.ts` as pt values with the panel width as the unit (the existing `--pt` trick in `launcher.css:2`).
**Step 2: Write the failing test.** `palette-geometry.test.ts` pins the numbers to the Swift source: it reads `Sources/Foundry/UI/FoundryTheme.swift` and asserts `rowTitle` size and the row height constant match `palette-geometry.ts`. (A drift in either side fails the site test.)
**Step 3:** FAIL. **Step 4:** Implement `Palette`: one component, modes `hero` (typing demo, preview pane) and `overlay` (site-wide). Rows render title, detail, kind label, hotkey badge exactly as the app. Selection is a border plus fill, moving with a 120 ms ease-out, never a spring (command palettes do not bounce; `emil-design-eng`). First open has no stagger. The font stack is `-apple-system` first because the app renders SF; Geist only for the site chrome around it.
**Step 5:** PASS. Side-by-side capture: `panel-real.png` beside `palette-site.png` at the same pixel width in `docs/qa/2026-11-01-website/palette-compare.png`. Differences allowed: the window material and the macOS shadow. Nothing else.

### Task C2: Site-wide ⌘K

**Files:** Modify `anvil/app/layout.tsx` (mount `<PaletteOverlay />` once); Create `anvil/app/foundry/palette/overlay.tsx`; Modify `palette-commands.ts` (commands: Download, every section stop, Proof, Methodology, Changelog, Brand, Privacy, GitHub, Copy install command, Toggle reduced motion, Calculator passthrough from `calculate.ts`, `confetti` which bursts the hero tiles once, R14); Modify `anvil/app/foundry/hero-content.tsx` (the hotkey hint `⌘ Space from anywhere` gains a sibling: "Try ⌘ K here").

**Step 1: Write the failing test.** `palette-commands.test.ts`: `search("proof")` returns the Proof command first; `search("24*18")` returns a calculator result with `432`; `search("")` returns the default list in the hero's order; every command has an `id`, `name`, `kind`, `run`.
**Step 2:** FAIL. **Step 3:** Implement. Opens on ⌘K and ⌘/ (not ⌘Space, which the browser and macOS own); `/` focuses the hero palette; `D` and `G` with no modifier trigger Download and GitHub when focus is not in a field, each CTA shows its key as a `kbd` chip (R13); closes on Esc (clear query first, then close, mirroring the app's Esc rule), returns focus to the trigger. Native `<dialog>` with `showModal()`. Opens instantly (no entrance animation: frequency rule, 100+ a day in the app, so the site demo matches). Scroll lock without layout shift (`scrollbar-gutter: stable`). Announced as "Foundry palette" to screen readers.
**Step 4:** PASS. Keyboard-only walk: Tab to the hero hint, Enter, type, arrows, Enter, Esc, Esc. Record in README. Axe 0.

### Task C3: Hero first paint

**Files:** Modify `anvil/app/foundry/story/story-canvas.tsx:70-85` (initialize after the first paint: `requestIdleCallback` with a 1.5 s timeout, then `import("./shelf-scene")`), `story.css:21` (`.foundry-wordmark` fades over 160 ms when `data-scene="ready"`, instead of snapping to 0), `shelf-scene.ts` (first `render` sets the tiles at the hero pose before the SVG fades), `anvil/next.config.ts` (`experimental.optimizePackageImports: ["three"]`), `anvil/app/layout.tsx` (`<link rel="preload">` for `tile-layout.json`).

**Step 1:** Baseline from Task 0.2 frames: name the exact frame where the swap happens and what is wrong.
**Step 2: Write the failing test.** Extend `qa.mjs --trace` to compute, per frame, the mean luminance of the wordmark region; fail if any frame drops below 60% of the final value (a blank between SVG and WebGL). Run: FAIL on the baseline if the flash is real; if it is not real, record that and skip to Step 4.
**Step 3:** Implement. **Step 4:** Lighthouse mobile on `/`: performance ≥ 95, LCP ≤ 2.0 s, no layout shift from the wordmark. Record in README with the JSON path. Open the trace frames again.

### Task C4: Story details

**Files:** Modify `anvil/app/foundry/story/tools-motion.ts:13-20` (examples), `story/tools.tsx` (labels), `story/memory.tsx` (tick), `story/clipboard.tsx` (keyboard hint copy), `story/download.tsx`, `story/*.css` (hover is one signal per element; `:active` is `scale(.97)` everywhere via one rule in `foundry.css`), `anvil/app/foundry/hero-content.tsx` (copy).

Each item below is one step with a before and after screenshot in the QA set:
1. Tool examples become real outputs. Replace the AI example `lol ok → Sounds good.` with a real one the app produces (run it: a one-line draft rewritten by the configured profile), and keep the "prepared example" sentence only where the output was prepared. Replace "Download video" with a real link the user owns or a public-domain one; the result label names the saved file. Calculator shows the expression the way the app formats it.
2. Tab detail lines stop repeating the tab name (`clean-copy`). Eight words max.
3. 81% ticks from 0 to 81 over 1.2 s on first reveal (`memory.tsx`), tabular numerals, once, not under reduced motion, final value in `aria-live`.
4. Clipboard belt: the selected card's detail shows the real keymap from the app (`↵ Paste · ⌘↵ Copy · ⌘P Pin`, HANDOFF.md), as `kbd` chips in the same style as the hero hint.
5. Download section: the CTA label is "Download for macOS", the line under it comes from Task B1/B3, the arrow still-figure keeps the orange side.
6. Mobile still layout (`data-scene="still"`): screenshot each section at 390 and match heading size, spacing scale and section order to the animated layout. Any section whose still version lacks a figure the animated version has gets the tile figure (reuse `Tiles`).
7. Hover and press: one rule `.foundry-preview :is(a,button):active { transform: scale(.97) }` with `transition: transform 120ms ease-out`; delete the per-component copies in `story.css:12`, `clipboard.css`, `foundry.css:164`.
8. URL hash follows the active section (`#shelf`, `#clipboard`, `#tools`, `#memory`, `#download`) via `history.replaceState`, and landing on a hash scrolls to that stop (R17). Test: `stopForHash("#tools")` equals `toolsStop`.
9. Copy pass over every string with `clean-copy`: no "seamless", no "powerful", every headline ends with the orange full stop or none do (today: hero no, download yes; decide: all closing headlines get it, section headings do not, and write the rule into `BRAND.md`).

Verification for the task: rerun `npm run qa`, open every screenshot, compare to the "before" set in a contact sheet `before-after.html`.

### Task C5: Chrome

**Files:** Modify `anvil/app/layout.tsx` (metadata: `themeColor`, `icons` from A3, `openGraph.images` per page, `twitter.card`), `anvil/app/not-found.tsx` (adds the palette hint and a search field that opens the palette), `anvil/app/foundry/site-chrome.tsx` (footer from B4; `aria-current="page"` on the active link; the lockup from A3), `anvil/app/globals.css` (`scrollbar-color`, `caret-color`, `::selection` already set; `scrollbar-gutter: stable`), `anvil/app/foundry/foundry.css` (focus ring is `outline: 2px solid var(--f-orange); outline-offset: 5px` everywhere, no transition on outline).

Favicon ships as light and dark SVGs selected by `media` (R10). `color-scheme: dark` on `html`. The 404 page returns HTTP 404 (check with `curl -I`) and links Download, Methodology and GitHub (R20). Methodology reproduction command gets a copy button and links to the raw JSON (R23).
**Step 1:** Test: `node --test app/metadata.test.ts` renders `generateMetadata` for each route and asserts a unique title, description under 160 chars, an OG image, canonical; a fetch of `/missing` returns status 404. **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS. Paste each URL into a Slack-style unfurl checker (or `curl -s | grep og:`) and screenshot the OG image for each page.

### Task C6: Harden

**Files:** Modify as found.

One step per check, each recorded in the README with a screenshot or a command output:
1. 320 px width: no horizontal scroll on any route (`document.documentElement.scrollWidth === innerWidth`).
2. 200% zoom at 1440: nothing clipped. Also 900 to 1100 px: `.foundry-copy h1` is `white-space: nowrap` at `4.15vw` and the stage has `min-height: 56.28vw` (R19); screenshot at 900, 1000, 1100.
3. `prefers-reduced-motion: reduce`: every route screenshotted; the still layout is the finished page.
4. Forced colours (`forced-colors: active` emulated in Playwright): tiles keep a visible edge (`outline: 1px solid transparent` on tiles), selection visible, orange meaning not colour-only (the full stop is also a period character, the selected row also has the border).
5. No JS: `curl` the HTML, confirm the hero copy, the download link, the proof strip and the footer are in the markup.
6. Keyboard-only journey from the top of `/` to the download link and through the palette; VoiceOver names on every control (`aria-label` audit in axe output; manual pass for the belt and tabs).
7. Extreme input in the palette: 200-character query, emoji, CJK; the row never wraps, the empty state names the fix ("No commands match. Try png, 24*18 or proof.").
8. Offline: `/` served from the Next build with network blocked after load still animates (assets are same-origin; `coast.jpg` has a width/height so nothing shifts if it fails).

### Task C7 (optional, user's call): `/vs/raycast`

**Files:** Create `anvil/app/vs/raycast/page.tsx`. One line per feature, a "Where Raycast is better" block (extensions, AI, Windows, iOS), numbers only from `docs/benchmarks/` (R24). Ask before building; it is a product stance, not polish.

---

## Phase D: Verify and ship

### Task D1: Fresh-context finish reviews

**Files:** Create `docs/qa/2026-11-01-website/critique-hero.md`, `critique-after.md`, `before-after.html`.

**Step 1:** Hero-first review: build the nav and hero alone (`?inspect=1&at=0`), capture 1280×800, 1440×900, 1920×1080 and 390×844, send to the Opus critic with no transcript. Fix, recapture, score each finding `resolved` / `partial` / `unresolved`.
**Step 2:** Full review: full-page shots at 1440 and 375, the source, the idea line, the first review's findings and how each was settled. Verdict must be `ship`.
**Step 3:** `/jury` on `http://localhost:3123`. No HIGH findings.
**Step 4:** Install walk as a stranger: new user account on this Mac, visit the site, download, install, first launch, press ⌘Space, type `png`. Time it. Under 60 s from landing to first command, no warning dialog (Branch 1) or exactly the dialog the site described (Branch 2).

### Task D2: Ship list

Every item checked with evidence in the README: legal links (licence, privacy), 404, favicon and apple-touch-icon in a real tab strip and home screen, skip link visible on focus, no dead `#` links (`qa.mjs` crawls every `href` on every route and reports status), `aria-current` in nav, OG per page, sitemap lists every route, robots allows all, Lighthouse ≥ 95 every category every route, axe 0 every route, bytes on `/` under 600 KB before the three.js chunk and the chunk loads after first paint.

### Task D3: Handoff

**Files:** Modify `docs/HANDOFF.md` (new "Website" section pointing to this plan and the QA folder), `progress.md` (one paragraph: what shipped, what is still imperfect, where the evidence is), `docs/plans/2026-11-01-foundry-last-20-design.md` (mark decisions taken).

Report in the `perfection` format: the 80% version, the last 20% item by item with evidence, what is still imperfect and why.
