# Foundry: the last 20% (design)

Scope: the website in `anvil/` first, the brand that the website carries second, and the three touchpoints that must agree with it (app icon, menu bar glyph, DMG). Not in scope: app features, distribution plumbing beyond what the site promises.

The bar: a stranger lands on the page, and within ten seconds believes a serious person made this, downloads it, and the install does not make them feel tricked. Every claim on the page is true today. Every pixel was decided.

## 1. What the 80% version is (evidence)

Read in `anvil/app` on 2026-11-01, branch `website-tile-world`, commit b19ddb7 plus an uncommitted polish diff (22 files, 216/212 lines).

Strong, keep:
- One world: ink `#0f0d0c`, chalk tiles, one orange, Geist. Tiles that assemble into results (wordmark, 432, Bonjour, 81%, 404) is a real signature. Signature test passes in five places.
- A scroll story with a still fallback (`data-scene="still"`) for reduced motion, compact viewports and WebGL loss. Keyboard reaches every demo. Designed 404, OG image, sitemap, robots, JSON-LD.
- A methodology page that states limits honestly.

Where it stops short (each item is checkable):
1. **The mark is a letter and a dot.** `Supporting/icon-1024.png`, `MarkTiles.menuBarImage`, favicon.ico. The user's verdict stands: generic. The wordmark tiles are the brand; the "f." does not carry them.
2. **Brand drift across touchpoints.** Site orange `#fa6428` on ink `#0f0d0c`; film bible `#ff5a1f` on `#050608`; ad storyboard `#FF5A1F` on `#060505`; tile sides `#f36f39`; CSS tiles use a third orange ramp (`#ffa36c → #c94b19`). No single source of brand tokens.
3. **The page lies in three places.** Download line says `v1.1`; `VERSION` is `1.2.0`; GitHub latest is `v1.1.0` (2026-10-05). JSON-LD hardcodes `softwareVersion: "1.1"`. The download modal tells people to press `⌥ Space` while the hero says `⌘ Space` (download-gate.tsx:58). Release notes 1.2.0 describe a "forge-anvil mark" icon that no longer exists.
4. **The install asks for forgiveness.** The download modal ("Before you open it") walks through Gatekeeper's Open Anyway. For an indie Mac app this is the single biggest trust leak on the page. progress.md records a Developer ID signature already in the tree; notarization is the missing step.
5. **The hero launcher is a mock.** `launcher.tsx` is a div-built panel with its own tokens (`--l-text`, SF Pro), its own row height, no detail line, no kind label. The real panel (44 pt rows, 28 pt icons, tracked-caps section headers, selection border) looks different. Visitors who install will notice.
6. **Proof is thin, and the one number is the wrong lead.** 81% memory holds against Raycast only; against Tinycast Foundry loses on memory and wins on panel-open latency (17 ms vs 65 ms, `docs/benchmarks/2026-09-29-foundry-1.1-tinycast-0.11.3-mbp-report.md`). Latency is the claim to own. The repo also holds search p95, bundle size (7.8 MB), idle CPU, test count, zero dependencies, Swift-native with no web view (Raycast is native too, so "no Electron" is not a claim). None of it is on the site.
7. **No second page worth visiting.** Footer links go to GitHub for release notes. No changelog, no brand or press page, no privacy statement (clipboard history is stored locally; the page never says so), no licence line.
8. **Chrome defaults.** favicon.ico only (no SVG favicon, no apple-touch-icon, no `theme-color`), close button is a bare `×`, modal opens at the same instant the download starts, `v1.1 · macOS 14+ · Open source` is the only footer fact.
9. **Copy with filler.** "AI profiles" example is `lol ok → Sounds good.` with "This response is a prepared example." Tool detail lines repeat the tab name. The memory section says "Provisional" three times across page and methodology.
10. **Unverified render.** No screenshot set exists for the site at 1440/768/390. The WebGL wordmark replaces the SVG wordmark on scene ready (`opacity: 0` swap) and nobody has measured whether that flashes. Lighthouse and axe numbers are not recorded.

## 2. The 100% version (the idea in one line)

**The site is the product.** "The app you never open" becomes literal: one Foundry palette, pixel-faithful to the shipped app, lives on every page and opens with the same keystroke. Everything else on the page is proof that it is worth installing, stated in numbers the repo can regenerate.

Three tracks, in priority order:

### Track A: Brand (mark, tokens, touchpoints)
- A mark that is built from the tile system and reads at 16 px. Direction comes from the Codex concept round (`docs/brand/concepts/`) and the research in `docs/brand/`. Shortlist three, the user picks one (taste call), then production: construction grid, SVG, monochrome template, favicon, apple-touch-icon, app icon via `scripts/render-icon.swift`, menu bar glyph via `MarkTiles`, DMG background, OG image.
- One brand token file (`docs/brand/tokens.json`) is the source for the site CSS, `FoundryTheme.Brand`, the icon script and the film. Ink, chalk ramp, orange, tile radius, tile gap, Geist weights, motion curve.
- `docs/brand/BRAND.md` plus a public `/brand` page with downloadable assets.

### Track B: Truth and proof
- Version from one source: `VERSION` at repo root is read at build time into the site (`app/site.ts`), the download line, JSON-LD and the OG image. Publishing 1.2.0 (or pointing the site at 1.1) is the user's call; the site stops being able to disagree with the release.
- Notarize, and delete the Gatekeeper modal. If the user does not notarize, the modal stays but says the true chord and opens after the download starts, not with it.
- A `/proof` page: warmed memory, search p95, bundle size, idle CPU, test count, dependency count, all from `docs/benchmarks/` JSON rendered at build. Methodology stays and links from each number.
- Privacy in one paragraph on the download section and in the footer: local SQLite, no accounts, no telemetry, AI keys in Keychain, open source under the repo licence.

### Track C: Craft (hero, story, chrome, performance, accessibility)
- One `Palette` component shared by the hero and a site-wide ⌘K, with tokens imported from the brand file and geometry matched to the app (row 44, icon 28, radius, selection border, section headers). Verified by a side-by-side capture of the real panel.
- Hero first paint: no SVG to WebGL flash, LCP under 2.0 s on throttled 4G, three.js loaded only after the wordmark is on screen.
- Story: number tick on 81%, tool examples replaced with real outputs, copy pass with `clean-copy`, mobile still layout matched section by section to the animated one.
- Chrome: SVG favicon with the new mark, `theme-color`, apple-touch-icon, changelog page rendered from `docs/release-notes/`, footer with version, size, licence, privacy.
- Performance and accessibility gates recorded in `docs/qa/2026-11-01-website/`: Lighthouse mobile ≥ 95 on every category, axe 0, 320 px no horizontal scroll, 200% zoom, forced-colors, keyboard-only journey, VoiceOver names on every control.

## 3. Decisions taken on the user's behalf (reverse any)

| Decision | Why |
| --- | --- |
| Keep the ink world and the chalk tiles; the mark changes, the system does not | The tiles are the one thing nobody else has. The research agent is confirming this against the field. |
| Site stays dark-only | The product's world is ink; a light mode would be a second design with no audience. Forced-colors mode is still honoured. |
| The hero demo stays a built component, not a screenshot | It is interactive and keyboard-driven, which a capture cannot be. The fidelity rule applies instead: it must match the real panel to the pixel. |
| Notarization is recommended, not assumed | It needs the user's Apple Developer account and a one-way action. The plan has a task for both branches. |
| New devDependency: Playwright for the QA script | The repo has no browser test harness; screenshots and axe are the only way to verify visual work, and the T3 preview is not reproducible from a script. |
| Logic tests run with `node --test` and Node's native type stripping | No test runner dependency. Node 26 on this machine strips types natively. |

## 4. Open questions for the user (asked one at a time, in the plan's gates)

1. Which mark direction, from the shortlist of three. Blocking for Track A production tasks only.
2. Notarize now, or keep the Gatekeeper modal. Blocking for one task.
3. Publish 1.2.0 before the site says 1.2. Blocking for the version task only (the site can read `VERSION` either way).

## 5. Done means

- Fresh-context critic (Opus 5.5, no transcript) reviews the hero alone, then the full page, and returns `ship`.
- `/jury` on the local build scores it at Site of the Day standard with no HIGH findings.
- Every number on the page traces to a file in `docs/benchmarks/`.
- The icon sits in a real Dock next to Raycast, Cursor, Arc and Linear without looking weaker, at 16 px in the menu bar, and as the favicon in a tab strip.
- `docs/qa/2026-11-01-website/` holds the before and after contact sheets, Lighthouse JSON, axe JSON and the install walk (download, mount, drag, first launch) as screenshots.

## Decisions taken (2026-11-01)

- Mark: Split Mould (Codex 02), Command Joint (Codex 05) kept as the alternate. Production geometry in `docs/brand/mark/`.
- Distribution: the app will be notarized, so the download modal is deleted.
- Version: the site shows `VERSION` (1.2.0) ahead of the release.
- Licence: MIT.
- Skipped: `/vs/raycast` (user's call), live Dock, menu bar, panel and install captures (user deferred them).
- Kept against the critic: the 432-tile calculator grid (the user asked for literal answers).
