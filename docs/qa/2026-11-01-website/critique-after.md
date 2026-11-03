ship with fixes

# Foundry site critique: after

Reviewer: fresh context. I opened every PNG in `final/` (18 home stops, 6 pages at 3 widths), `palette/`, the 320 px, forced colours and no-JavaScript captures in `harden/`, and `c3-trace/handover.png`. I read `report.json`, `lighthouse.json` and `docs/brand/BRAND.md`, and I checked source where a screenshot needed a cause. I read `critique-before.md` after I had formed my own view.

The site now reads as one idea, told calmly. The tile material carries every figure, the honest benchmark is the strongest page, and the machine checks are clean: 0 console errors, 0 overflow and 0 clipped controls in `report.json`, and Lighthouse accessibility 100 on every route. Two defects block a clean ship. The last call to action is broken at every width, and the site's own size figure contradicts itself.

## Status of the earlier findings

| # | Finding | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Conversion scene collapses at tablet width | resolved | `home-768-at0.840.png`: the HEIC source, the PNG grid, both captions and all three tabs are separate. Nothing covers anything. |
| 2 | Memory sentence collides with "81%" at tablet width | resolved | `home-768-at2.920.png`: "lower warmed memory use." sits about 40 px under the figure. |
| 3 | Hero paints empty, then pops and changes colour | resolved | `c3-trace/handover.png`: the wordmark is present and cream in the first frame. Later frames only add tile seams. |
| 4 | Hero headline smaller than section headlines | resolved | `home-1440-at0.000.png` and `-at0.840`, `-at1.300`, `-at1.860`: every display line now has the same 62 px line pitch. |
| 5 | Tab controls do not match each other | partial | `home-1440-at0.840.png` still has 14 px tabs at the bottom centre. `home-1440-at1.860.png` still has a 24 px vertical list. At 390 the tools row now scrolls instead of wrapping (`home-390-at1.860.png`). |
| 6 | Clipboard scene stacks four rows of controls | partial | `home-1440-at1.300.png`: the pager count, the sample button and the hint line are gone. The headline still sits at the right and the top-left quadrant is still empty. |
| 7 | Photo card covers the subhead at tablet width | partial | `home-768-at1.300.png`: the card clears the subhead. No neighbouring cards show, so the rail still reads as one tilted photo. |
| 8 | Calculator demo is a block of filler tiles | partial | The grid stays by decision. `home-1440-at1.860.png`: the grid's centre is at x≈943 and the panel's at x≈922, still about 20 px apart. The panel still does not show the answer. See new finding M2. |
| 9 | Conversion source and result change size | unresolved | `home-1440-at0.840.png`: the HEIC source is about 170 px wide, the PNG about 500 px. The source is still a blank document, not the same fruit. |
| 10 | Memory section uses two figure styles | resolved | `home-1440-at2.920.png`: "81%" is the only tiled figure. The comparison is one plain line. |
| 11 | Left edges drift between sections | unresolved | `home-1440-*`: nav logo at x≈42, hero copy at x≈75, section copy at x≈78, clipboard headline at x≈878. `methodology-1440.png`: column at x≈340, nav at x≈42. |
| 12 | Launcher mock reverses order on narrow screens | resolved | `home-768-at0.000.png` and `home-390-at0.000.png`: the list comes first and the preview follows. |
| 13 | Dead space and a broken arrow in the download section | partial | `home-390-at3.360.png`: the gap above the arrow shrank to about 100 px. The arrow's three-tile tail is still detached from its head. |
| 14 | Methodology table wraps at phone width | unresolved | `methodology-0390.png`, y≈1600 to 1850: "Foundry 1.1.0", "Raycast 2.5.3", "Foundry first" and "Raycast first" each still break onto two lines. |
| 15 | 404 zero hard to read, tiles do not match | resolved | `missing-page-1440.png`: the zero has no diagonal and the tiles share the chalk material. |

Counts: 7 resolved, 5 partial, 3 unresolved.

## New findings

### HIGH 1: the final Download button wraps onto two lines at every width
- **Where:** `home-1440-at3.360.png` at (720, 710); `home-768-at3.360.png` at (750, 1330 in the 1536 px image); `home-390-at3.360.png` at (390, 1130 in the 780 px image).
- **What is wrong:** "Download for macOS" breaks into "Download for / macOS". At 1440 the text touches the top and bottom edges of the button. This is the last screen of the story and the one action the whole page leads to. The no-JavaScript capture (`harden/nojs-home.png`) shows the button on one line, so only the animated scene is broken.
- **Cause:** `anvil/app/foundry/story/download.css:13` fixes the width at `21.6vw` (311 px at 1440) while line 6 adds 36 px of padding on each side and line 13 sets the font to up to 30 px. At 1440 that leaves about 239 px for a label that needs more. Line 23 does the same at narrow widths: 270 px wide, 72 px of padding, 20 px type.
- **Fix:** Remove the fixed `width` on lines 13 and 23. Let the button size to its label with `width: auto`, keep `min-width: 270px`, and add `white-space: nowrap`. Add the final stop to the clipped-controls check so a wrapped label fails the gate.
- **Principle:** The primary action is never broken. Size controls from their content, not from the viewport.

### HIGH 2: the app size contradicts itself between pages
- **Where:** `changelog-1440.png`, the 1.2.0 intro (y≈330) and the Brand and Performance lists, against `home-1440-at3.360.png` (720, 773) and `proof-1440.png`, the "8.1 MB" card (y≈2000 to 2300).
- **What is wrong:** The home page and proof page say 8.1 MB, and proof says it fell from 14,604 KB. The changelog says "a 7.8 MB app", "The app is 7.8 MB (was 18 MB)" and "App bundle 18 MB → 7.8 MB". The proof page's own pitch is "Every number, with its source". A visitor who checks will find two sizes and two baselines, and the 18 MB baseline matches no benchmark file.
- **Cause:** `docs/release-notes/1.2.0.md` lines 3, 10 and 53. The proof figure comes from `docs/benchmarks/2026-10-08-foundry-1.2-report.md:23` (14,604 KB to 8,100 KB).
- **Fix:** Change the three lines to 8.1 MB, and change "was 18 MB" to "was 14.6 MB". Then add a test that fails when a release note states a size or timing figure that differs from `docs/benchmarks/latest.json`.
- **Principle:** A site that sells honesty cannot disagree with itself. Every number has one source.

### MEDIUM 1: at 320 px the clipboard shows the wrong card and the tabs clip
- **Where:** `harden/w320-home.png`, the clipboard band (y≈1750 to 2250 in the 336 px image) and the conversion tabs (y≈1700).
- **What is wrong:** The visible card is the Messages note, cut at its left edge. The selected item, Coast.jpg, sits mostly off the right edge, while the caption under it says "Coast.jpg 10:16". The caption names a card the visitor cannot see. The conversion tabs end in "Remove backgrou", cut at the viewport edge. The PNG is 336 px wide while every other 320 px capture is 320 px wide, which suggests 16 px of horizontal overflow. The QA README says 320 px has no overflow and the tabs fit, and this capture disagrees.
- **Fix:** In the static rail, scroll the selected card to the centre on load (`scrollIntoView({ inline: "center" })`, or set the initial `scrollLeft`). Let the conversion tab row scroll, or shorten "Remove background" to "Remove BG" below 360 px. Add 320 to the overflow and clipped-controls gate so `report.json` covers it.
- **Principle:** Every breakpoint is designed. The thing the caption names is the thing on screen.

### MEDIUM 2: the calculator panel never shows the answer
- **Where:** `home-1440-at1.860.png`, the panel at (920, 745); the same at 768 and 390.
- **What is wrong:** The input says "24 × 18". The result row says "Calculate" with a faint "Done" on the right. The answer, 432, appears only as a small mono label above the grid. The product mock does the one thing a calculator should not do: it hides the result. The no-JavaScript fallback (`harden/nojs-home.png`, y≈1240 to 1350 at display scale) shows "Result 432" in tiles directly above the panel, which reads better.
- **Fix:** Keep the grid, which is the owner's decision. Put "432" in the result row where the app shows it, and drop "Done", which names no action a visitor can take. Centre the grid on the panel's axis at 1440.
- **Principle:** A product mock has to behave like the product. The answer goes where the eye expects it.

### LOW 1: two page headlines break the full-stop rule
- **Where:** `methodology-1440.png`, the H1 "How we measured 81% less memory" (y≈330); `proof-1440.png`, the H1 "Every number, with its source" (y≈200).
- **What is wrong:** `BRAND.md` says every headline ends with a period. The brand page's H1 has one, and so does every home headline. These two do not.
- **Fix:** Add the periods. Add a check that fails when an `h1` or `h2` in the app's marketing routes does not end in a period, with the changelog version headings and "Changelog" and "Privacy" as named exceptions.
- **Principle:** A brand rule only holds if every page follows it.

## Keep

1. **The tile material as the only figure language.** The wordmark, the 81%, the 432, the 404 and the clipboard rail are drawn in one material. That material is ownable and has no stock imagery.
2. **The proof and methodology pages.** They are labelled provisional, use the worse run, round down, show where Foundry loses to Tinycast, and link every source file. They are typeset as calm reading pages. This is the site's strongest trust signal.
3. **The copy voice.** "The app you never open. Opens everything.", "That thing you copied.", "No new tab for that." and "⌘ Space, then anything." are short and specific. The single orange full stop on the closing line is the best use of the accent on the site.
4. **The hardening.** Forced colours keeps the CTA and panels legible with system colours. The no-JavaScript page is a complete static story. The first paint is the final wordmark.

Model: Claude Opus 5.5 (`claude-opus-5-5`).
