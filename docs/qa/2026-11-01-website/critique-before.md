# Foundry site critique: before

Reviewer: fresh context, screenshots only. Idea line: "The app you never open. Opens everything."

I opened all 31 PNGs: the 18 home stops at 1440, 768 and 390, the methodology page and the 404 at each width, and `trace/handover.png`.

## Findings

Ranked by cost to the page, worst first.

### 1. HIGH: the conversion scene collapses at tablet width
- **Where:** `home-768-at0.840.png`, from y≈660 to the bottom.
- **What is wrong:** The PNG grid is drawn over the HEIC source file. It covers the "HEIC" label and covers the "Convert to PNG" tab, so only its orange underline shows. The "PNG" caption falls below the tab bar. "Original" and "Remove background" sit at the edges, cut by the grid. The one scene that shows a file changing format cannot be read.
- **Fix:** Below about 900px, use the 390 layout: source on top, result under it, tabs under the subhead. Size the result grid from the column width, not the viewport height. Add a 768 overlap check to the capture gate.
- **Principle:** Every breakpoint is designed. No element sits on another unless the design means it to.

### 2. HIGH: the memory claim sentence collides with its number at tablet width
- **Where:** `home-768-at2.920.png`, y≈840–890.
- **What is wrong:** "lower warmed memory use." is set on top of the bottom row of tiles in "81%". The page's most important claim is printed through its own figure. The cream "115.2 MB" also runs almost edge to edge with about 120px of gutter.
- **Fix:** Put the sentence in normal flow under the figure, with a fixed gap, for example 24px. Do not position it absolutely. Cap the tile size of both figures to the content width minus the gutters.
- **Principle:** Type never overlaps type. A claim has to be legible before it can persuade.

### 3. HIGH: the hero paints empty, then the wordmark pops in and changes colour
- **Where:** `trace/handover.png`.
- **What is wrong:** Frame 1 has no wordmark: a black field, a GitHub glyph and a clipped headline. In frame 2 the wordmark appears all at once in a grey-beige. Frames 3 and 4 brighten it to cream. The first impression is a pop followed by a colour shift. That reads as loading, not as intent.
- **Fix:** Make frame 1 final. Server-render the wordmark at its resting colour. If the tiles animate, animate only from that final state, for example a light settle, and never change their lightness after first paint.
- **Principle:** Quiet motion. The first painted frame is a designed state.

### 4. MEDIUM: the hero headline is smaller than every section headline
- **Where:** `home-1440-at0.000.png` compared with `-at0.840`, `-at1.300` and `-at1.860`.
- **What is wrong:** "The app you never open. Opens everything." is set at about 56px. "Convert files…", "That thing you copied." and "No new tab for that." are about 68px. The idea line is outranked by its supporting sections. The wordmark takes the scale, so the sentence that explains the product reads as a subhead.
- **Fix:** Use one display size for the hero line and every section headline, or make the hero line one step larger. Write the scale down, for example 56/72, and use only those values.
- **Principle:** Exact type. Hierarchy follows importance.

### 5. MEDIUM: the tab controls do not match each other
- **Where:** `home-1440-at0.840.png` (bottom centre) and `home-1440-at1.860.png` (left column).
- **What is wrong:** The conversion tabs are 14px labels, centred and detached at the bottom of the screen. The tools tabs are a 24px vertical list on the left that reads as page navigation. At 768 and 390 the tools tabs turn into a horizontal row, and at 390 that row wraps onto two lines. Both controls do the same job, so they should look the same.
- **Fix:** Build one segmented or underline tab component at one size. Place it directly under each section's subhead at every width. At 390, scroll it horizontally instead of wrapping.
- **Principle:** One component per job. Controls belong beside the content they change.

### 6. MEDIUM: the clipboard scene stacks four rows of controls in one corner
- **Where:** `home-1440-at1.300.png`, bottom right from y≈700 to 870.
- **What is wrong:** "Coast.jpg 10:16", "Previous 2/5 Next", "Try the sample clipboard", a search field, the hint "Text, images, links, colors." and "Copy item" are packed under the tile rail. The top-left quadrant is empty. The demo asks the visitor to run a small app when they should be watching one moment.
- **Fix:** Keep one interaction: the search field, or the carousel with arrow keys. Remove the pager label and the hint line. Move the headline left so the empty quadrant is used.
- **Principle:** Restraint. One idea per screen and one action per idea.

### 7. MEDIUM: the photo card covers the subhead at tablet width
- **Where:** `home-768-at1.300.png`, y≈480–520.
- **What is wrong:** The tilted Coast.jpg card covers the baseline of "Find it again in clipboard history." The neighbouring cards are out of view, so the carousel reads as one large tilted photo. A dead band about 150px tall separates the pager from the search field.
- **Fix:** Start the rail below the subhead with a fixed gap. Scale the card so its neighbours show at the edges, as at 390. Close the dead band.
- **Principle:** Every breakpoint is designed. Keep spacing on one scale.

### 8. MEDIUM: the calculator demo is a block of filler tiles
- **Where:** `home-1440-at1.860.png` and `home-768-at1.860.png`.
- **What is wrong:** 432 orange tiles in a 24×18 rectangle say "24 × 18 = 432" a second time, with no new information. The launcher panel below the grid is about 20px off the grid's centre at 1440. The caption "Calculate without leaving the launcher." repeats the headline. At 768, about 300px of empty space follows the caption.
- **Fix:** Give the launcher panel the space. Show the typed expression and the answer in the result row, as the real app does, and drop the tile rectangle. If the tiles must stay, make them a small accent and align them on the panel's centre axis. Remove the caption.
- **Principle:** Show the product, not a picture of the arithmetic. No decoration in place of the real thing.

### 9. MEDIUM: the conversion source and result change size
- **Where:** `home-1440-at0.840.png`.
- **What is wrong:** The HEIC source is about 170px wide and the PNG is about 500px. The scene implies the conversion enlarged the image. The source is a blank document icon and the result is pixel-art fruit, so the before and after do not show the same picture.
- **Fix:** Show the same image at the same size on both sides and change only the format badge, for example "HEIC" to "PNG". For "Remove background", remove the cream cells.
- **Principle:** A demo has to be true to what the product does.

### 10. MEDIUM: the memory section uses two figure styles and three type sizes on one line
- **Where:** `home-1440-at2.920.png`, y≈510–700.
- **What is wrong:** "81%" uses large orange tiles. "115.2 MB" uses small cream tiles with loose tracking and a wide gap before "MB". "Foundry" sits alone under it as a label. "vs 620.2 MB · Raycast 2.5.3" mixes three sizes on one line. The screen has two heroes and no clear ranking.
- **Fix:** Keep "81%" as the only tiled figure. Set the comparison as one plain line in body type: "Foundry 115.2 MB vs Raycast 2.5.3 620.2 MB". Then add the provisional note and the methodology link.
- **Principle:** Exact type, few sizes. Give one figure the visual weight.

### 11. LOW: left edges drift between sections
- **Where:** `home-1440-*`.
- **What is wrong:** The nav logo sits at x≈42. Hero copy sits at x≈75, conversion and tools copy at x≈77–79, and the clipboard headline at x≈878. The methodology column starts at x≈320 while its nav stays at 40. No single grid holds the page.
- **Fix:** Use one container with one gutter token. Align the nav logo, the section headlines and the footer logo to the same left edge.
- **Principle:** One spacing scale and one grid.

### 12. LOW: the launcher mock reverses its order on narrow screens
- **Where:** `home-768-at0.000.png` and `home-390-at0.000.png`, the panel under the CTA.
- **What is wrong:** At 1440 the result list sits on the left and the preview on the right. At 768 and 390 the preview pane moves above the list, so the clipboard items appear before the row that opens them. The 1440 preview pane also leaves an uneven gap above its first item.
- **Fix:** On narrow screens, keep list then preview, or hide the preview and show the list only. Centre the preview content vertically, or align it to the top padding.
- **Principle:** A product mock has to behave like the product.

### 13. LOW: dead space in the download section
- **Where:** `home-390-at3.360.png` and `home-1440-at3.360.png`.
- **What is wrong:** At 390 there is about 280px of empty space between "then anything." and the tile arrow. The arrow's three-tile tail is separated from its head and reads as a stray dotted line. The arrow is a drawn illustration pointing at a button that is already obvious.
- **Fix:** Remove the arrow, or tighten it into one contiguous glyph placed close to the button. Pull the CTA up under the headline.
- **Principle:** No decoration in place of the real thing. Spacing should be intentional.

### 14. LOW: the methodology table wraps at phone width
- **Where:** `methodology-0390.png`, the table.
- **What is wrong:** "Foundry 1.1.0", "Raycast 2.5.3", "Foundry first" and "Raycast first" each break onto two lines, so the rows look ragged. The tiled "81%" above the H1 repeats the H1.
- **Fix:** At phone width, use short column heads ("Foundry", "Raycast") with the versions in the caption, or turn each run into a two-line card. Remove the tiled figure, or shrink it to an inline mark.
- **Principle:** Every state is designed, including narrow tables.

### 15. LOW: the 404 zero is hard to read and its tiles do not match
- **Where:** `missing-page-1440.png` and `missing-page-0390.png`, the "404" figure.
- **What is wrong:** The slashed zero has a stray inner diagonal, so it can read as a "6" or as a broken glyph. These tiles are greyer and more rounded than the cream tiles used on the home page.
- **Fix:** Use the same glyph set as "81%" and the same tile material and radius as the home page.
- **Principle:** One visual material, used the same way everywhere.

## Keep through any redesign

1. **The tile material as the single visual language.** The tiled wordmark, the tile rail under the clipboard, and the tiled figures for "81%" and "404" are ownable and have no stock imagery. One idea carries the whole site.
2. **The honest benchmark.** It is labelled provisional, uses the worst-case leg, rounds down, names the machine and the versions, and links a runnable script. The methodology page is calm and typeset as a reading page. This earns trust Raycast-class sites rarely ask for.
3. **The copy voice.** "That thing you copied.", "No new tab for that." and "⌘ Space, then anything." are short, specific and owned. They should not be replaced with feature-grid headings.

## Verdict

fix

---

Model: Claude Opus 5.5 (`claude-opus-5-5`).
