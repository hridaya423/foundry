# Website QA, 2026-11-01

Plan: `docs/plans/2026-11-01-foundry-last-20.md`. Script: `anvil/scripts/qa.mjs` (`npm run qa`; `--shots` skips Lighthouse; `--trace` records first paint, add `QA_GPU=1` for the real GPU). Routes and stops: `anvil/scripts/qa-routes.json`.

The screenshots (`*.png`) are not tracked. A run writes them next to the reports; the sentences below that describe a capture record what the reviewer saw, and the images are not in the repository.

## Before (production build, `next start -p 3124`)

Folder: `before/`. 24 captures (6 story stops and 2 pages at 1440, 768, 390), `contact-sheet.html`, `report.json`, `axe-*.json`, `lh-*.json`, `lighthouse.json`, `trace/`.

**Timing caveat.** Measured while the machine ran about 16 agents: load average 114 on 14 cores. Every wall-clock figure below is inflated and must be re-measured on a quiet machine before it is quoted or used as a budget. Structural findings and screenshots are unaffected.

### Facts that do not depend on load

| Check | Result |
| --- | --- |
| Geist is the rendered face (`document.fonts.check`) | yes, every route |
| Horizontal overflow at 1440, 768, 390 | 0 px every route |
| `/missing-page` status | 404 |
| axe | 1 minor (`aria-allowed-role`, hero, all widths); methodology and 404 clean |
| Console | 1 hydration mismatch on the clipboard card transform; fixed this session (pose values rounded, `0px`), 0 errors after |
| `/` rendering | dynamic (`ƒ`), because the page reads `searchParams` for the inspector; could be static |
| Bytes on `/` | 595 KB total |

### First paint (real GPU)

1. The first painted frame has the copy and the palette but no wordmark. The wordmark is a CSS background image (`.foundry-wordmark`) that loads after first paint, so the top half of the hero is empty.
2. The SVG wordmark is then replaced by the WebGL tiles, which render visibly brighter and warmer. The swap is a pop, not a handover.

### Main-thread cost (inflated, see caveat)

- Lighthouse mobile on `/`: performance 63, accessibility 100, best practices 100, SEO 100. FCP and LCP 0.9 s. Total blocking time 8.5 s, all in the three.js chunk (scene setup).
- Real GPU (Apple M4 Pro, headed Chromium): one cold run blocked the main thread for 5.3 s; three warm runs blocked for 250 to 510 ms. The cold run is a first-time shader compile.
- What holds regardless of load, from the code: `createShelfScene` builds the scene, the PMREM environment and the shadow map, and compiles every material on its first `render`, all in one synchronous block. Nothing uses `compileAsync` or `KHR_parallel_shader_compile`. Task C3 fixes this.

### What the screenshots show

1440:
- Hero: wordmark, headline, palette demo are strong. The nav shows only the GitHub mark at the top (Download is hidden in the hero zone), so the only Download is the orange CTA.
- Shelf: the HEIC file icon's dog-ear is drawn as grey tiles and reads as a stain, not a fold.
- Clipboard belt: the strongest section.
- Tools: 432 drawn as a 24 × 18 grid of tiles is the best idea on the page. The launcher row under it shows "Done" in a dim grey that reads as disabled.
- Memory: clear, but "Provisional" leads the context line.
- Download: clean. Footer is fine in production; the clipping seen earlier was the Next dev overlay.

390:
- Hero: the palette stacks its preview above its result list, so the list order reads backwards.
- Tools: the tab row wraps to two lines and leaves "Video download, Developer tools" as a second row.
- Memory and Download: tall empty bands between the figure and the next element.

## After (production build, same routes)

Folder: `after/` (24 captures, axe, `report.json`, `contact-sheet.html`; `--shots`, no Lighthouse). Trace: `c3-trace/`. Load average about 40 when captured: timings still unconfirmed.

| Check | Before | After |
| --- | --- | --- |
| Status, Geist, overflow | 200 / 404, yes, 0 px | unchanged |
| Console errors | 1 hydration mismatch | 0 every route |
| axe | 1 minor (`aria-allowed-role`, hero) | unchanged, still open |
| First painted frame | no wordmark | SVG wordmark present (svg opacity 1, scene not yet ready) |
| SVG to WebGL handover | visible pop, WebGL brighter and warmer | SVG ramp brightened to the lit tile colour, 160 ms crossfade |
| 768 shelf (critic HIGH 1) | file shelf over the headline | clear |
| 768 memory (critic HIGH 2) | headline over the tiles | clear |
| Nav and footer mark | text "foundry" | Split Mould mark + wordmark |

Correction: `next/image` with `priority` does not emit a `<link rel="preload">` in this build (Next 16.2.7). The image is eager in the server HTML, which is enough for the first frame shown above.

### B1, B2, C3 (user: "we'll notarize the app don't worry. so remove the modal. fix the C3 and yeah make it 1.2.0")

- B2: `download-gate.tsx` and the `.dl-*` CSS deleted; every Download is a plain link. Playwright click: `Foundry.dmg` download starts, no dialog in the DOM.
- B1: `next.config.ts` reads `../VERSION` into `FOUNDRY_VERSION`; `site.ts` exports `foundryVersion`; the download line and JSON-LD `softwareVersion` read it. Served HTML shows `1.2.0`. Until the 1.2.0 release is published, `releases/latest/download/Foundry.dmg` still serves 1.1.0.
- C3: scene setup no longer runs as one block. `createShelfScene` is async and yields after renderer creation, after the PMREM bake and before merging geometry; shaders compile with `renderer.compileAsync` before the scene goes ready. `qa.mjs --trace` now records long tasks (`trace.json`: `longTasks`, `longest`, `blocking`).
  - Before (3 cold GPU runs, load 87 to 105): longest task 295, 204, 200 ms, one block.
  - After (4 cold GPU runs, load 45 to 80): longest 118, 149, 119, 190 ms, split into 3 or 4 tasks. Total blocking unchanged (150 to 285 ms): the work is the same, it no longer lands as one freeze.
  - Profile (before chunking): `renderer.setSize` ~98 ms, `PMREMGenerator.fromScene` ~81 ms, first render ~90 ms (program link in `getUniforms`).
  - Surprise: `createShelfScene` runs while the canvas is `display: none`, so `canvas.clientWidth` is 0 and `small` is always true. Desktop has always rendered without shadows at pixel ratio up to 2. Left as is: the look was tuned in that state.
  - Handover unchanged: wordmark present in the first frame, mid-crossfade in the second.
- Recaptured `after/` on this build: 24 shots, 0 errors, 0 overflow, only the known minor axe item.

Not fixed yet: the critic MEDIUMs (Task C4), Lighthouse and long-task budgets on a quiet machine.

## Final (production build, 7 routes, `final/`)

User: "finish the plan". Licence MIT; live app captures deferred; `/vs/raycast` skipped.

| Check | Result |
| --- | --- |
| Shots | 36 (6 home stops and 6 pages at 1440, 768, 390). 0 console errors, 0 horizontal overflow, 0 clipped controls outside intentional scrollers. |
| axe | 0 violations on every page except the known minor `aria-allowed-role` on the home hero. |
| Tests | `npm test` 34 pass (tokens, mark, QA helpers, site links, story hash, palette commands, changelog, proof, brand kit). Swift: mark, tokens and onboarding suites, 37 tests, 0 failures. Lint and typecheck clean. |
| 404 | HTTP 404. Atom feed passes `xmllint`. |
| Lighthouse (load average 35 to 43) | `/methodology`, `/proof`, `/changelog`, `/privacy`, `/brand`: 100 in every category. `/`: accessibility, best practices, SEO 100; performance 71 to 75 (baseline 63), TBT 0.8 to 1.1 s (baseline 8.5 s), LCP 3.0 s. LCP is now the wordmark `<img>` (it was text at 0.9 s), so the two LCP figures measure different elements. The plan's budget (performance at least 95, LCP at most 2 s) is not met; re-measure on a quiet machine. |
| Harden (`harden/`) | 320 px: no overflow; the conversion tabs fit after a fix. Reduced motion: still layout, no errors. Forced colours: CTA and panels gained system-colour edges. No JavaScript: hero copy, download link and footer in the HTML. |

What changed in this round: ⌘K palette on every page (`palette/`); section hashes; `/proof`, `/changelog` + feed, `/privacy` + MIT `LICENSE`, `/brand` + kit; one display size for headlines; tools tabs scroll on phones; clipboard controls trimmed and the 768 card no longer covers the subhead; hero demo lists before preview on phones; memory shows one tiled figure and one plain comparison line; download section tightened on phones; footer wraps; one focus ring, one press rule; plain zero in the tile font; onboarding cast redrawn as Split Mould; Open Graph image regenerated.

Not done: live Dock, menu bar, panel and install captures (C1 palette fidelity, A3 step 6, D1 step 4: deferred by the user); `/vs/raycast` (skipped); confetti and the reduced-motion toggle from C2 (left out for restraint); D and G single-key shortcuts (left out: a stray keypress would leave the page).

### D1 fresh-context review (`critique-after.md`, Opus 5.5): "ship with fixes"

Earlier findings: 7 resolved, 5 partial, 3 unresolved. New: 2 HIGH, 2 MEDIUM, 1 LOW. Settled after the review:

- HIGH 1, closing button wrapped onto two lines: fixed (`width: auto`, `nowrap`); the recaptured home shots at 3.36 s show one line.
- HIGH 2, app size disagreed between pages: `docs/release-notes/1.2.0.md` now says 8.1 MB (was 14.6 MB), matching `/proof` and `docs/benchmarks/2026-10-08-foundry-1.2-report.md`.
- MEDIUM 1, 320 px: the tab clipping came from a capture taken before the 320 fix. The selected clipboard card is centred on the current build (Coast.jpg at 48 to 272 px of 320). 320 px is now part of the QA gate (48 shots). Adding it surfaced a clipped hero headline (display floor lowered to 24 px), a table that scrolled without being focusable, and duplicate table labels on /methodology; all fixed.
- MEDIUM 2, calculator panel hid the answer: the result row now shows the result (432, Bonjour, 2024-01-01) in place of "Done".
- LOW 1: /proof and /methodology headlines end with a period.
- Still open: #9 HEIC source and PNG result differ in size (WebGL choreography), #11 left edges drift between sections, #14 the methodology table needs horizontal scrolling at 390 (now a focusable region).

Final gate (`final/report.json`): 48 shots, 0 console errors, 0 overflow, 0 clipped controls, axe clean except the known minor `aria-allowed-role` on the home hero. A contrast hit at 320 on one run was the demo's preview list mid-fade (`#282625` foreground), not the settled colour.


## Re-measured 2026-11-10

`final/lighthouse.json` records `/` at performance 52 and LCP 5.1 s. That run is an outlier. On a production build (`next build`, `next start`, load average 9 to 16), seven Lighthouse mobile runs of `/` scored 48, 74, 78, 75, 73, 74 and 79. LCP stayed at 3.0 s in every warm run, and TBT at 0.6 to 0.9 s. The first run of a fresh server is the outlier: 48, TBT 13 s.

Starting the 3D scene only after `load` and an idle callback did not move LCP or the score, so that change was not kept. The budget (performance at least 95, LCP at most 2 s) is still not met. The LCP element is the wordmark `<img>`, which is not waiting on the scene.

The axe `aria-allowed-role` on the tools panel is fixed; `npm run qa -- --shots` now exits non-zero on page errors, a fallen-back 3D scene, overflow, clipped controls or serious axe violations.
