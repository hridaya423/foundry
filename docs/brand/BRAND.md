# Foundry brand

One source: `docs/brand/tokens.json`. `anvil/scripts/build-tokens.mjs` writes `anvil/app/foundry/tokens.css` and `tokens.ts` from it (`npm run tokens`; `prebuild` runs it). `anvil/scripts/build-tokens.test.mjs` fails if either generated file drifts from the JSON. `Tests/FoundryTests/BrandTokensTests.swift` fails if the app's `FoundryTheme.Brand` drifts on ink, text, muted, line or orange.

The film bible (`launch-film/DESIGN.md`, `#ff5a1f` on `#050608`) and the ad storyboard (`#FF5A1F` on `#060505`) are retired palettes. New work uses the tokens.

## Colour

| Token | Hex | Role |
| --- | --- | --- |
| `ink` | `#0f0d0c` | Ground. Every surface starts here. |
| `ink-raised`, `-2`, `-3` | `#191714`, `#201c18`, `#28241f` | Surfaces that sit on ink: panels, cards, fields. Never more than three levels. |
| `line` | `#484039` | Hairlines and borders. |
| `text` | `#eee7dd` | Body and display type on ink. |
| `muted` | `#bdb4aa` | Secondary type. |
| `orange` | `#fa6428` | The one accent. |
| `orange-light`, `-mid`, `-deep` | `#ffa36c`, `#f0672b`, `#c94b19` | The lit ramp for an orange tile face. Only on tiles. |
| `orange-side` | `#f36f39` | The visible side of a pressed or orange tile. |
| `chalk` | `#c6bbab` | Tile face in the lit 3D scene. |
| `chalk-light`, `-mid`, `-deep` | `#f4ede2`, `#d6cdbd`, `#b9ad9a` | The ramp for a flat CSS tile face. |
| `chalk-ink`, `chalk-ink-muted` | `#211d19`, `#51483e` | Type set on chalk. |

**The orange rule.** Orange closes a sentence (the full stop), marks the selected thing, or is the one cast in the mark. It never decorates, never fills a section, never appears twice in one view unless both instances are the same state.

**The full stop.** Every headline ends with a period. Only the closing headline of the home page ("then anything.") sets its period in orange. Section headlines keep a plain period.

Black shadows (`#000000xx`) stay literal: they are physics, not brand. Content colours stay literal: the tiled mandarin in the file shelf, the `#FA6428` sample in the clipboard belt.

## Tiles

Radius 18% of the tile. Gap 10% of the tile. Chalk face, orange side. A flat tile takes the chalk ramp at 160°; a lit tile takes its colour from the scene. Tiles assemble into results: the wordmark, 432, 81%, 404. Every new figure on the site is drawn in tiles or not drawn.

## Type

Geist for everything the site says, Geist Mono only for code and file names. Weights 400 (display and body), 500 (UI and labels), 600 (wordmark only). The palette demo uses the system face because the app renders SF Pro; that is the one exception and it exists for fidelity.

## Motion

`ease-out` `cubic-bezier(0.23, 1, 0.32, 1)` for anything entering or responding. `ease-in-out` `cubic-bezier(0.65, 0, 0.35, 1)` for things that travel. Press 120 ms, state change 220 ms, entrance 450 ms. Press feedback is `scale(0.97)`. No springs with overshoot. The app's `FoundryTheme.Brand.Motion` uses the same curve and durations.

## Mark

Split Mould, chosen 2026-11-01 (`docs/brand/SHORTLIST.md`). Masters live in `docs/brand/mark/`. The site draws it inline from `anvil/app/foundry/mark.tsx`. The brand kit at `/brand/foundry-brand.zip` is built by `anvil/scripts/build-brand-kit.mjs`.

**Construction.** The mark sits on a 120 unit square with 10 units of built-in margin. Every straight edge lands on a 5 unit grid; `mark-grid.svg` draws it. Three chalk pieces form the mould: a left piece with a top arm, a right piece with a top arm, and a square foot. The channel between every piece and the cast is 10 units. Outer corners take a 10 unit radius; inner corners stay square. The cast is a 20 by 60 rectangle at x 50, y 40. `anvil/scripts/mark.test.mjs` holds the grid and the single orange.

**Clear space.** Keep one cast width (20 units, 1/6 of the mark) clear on every side. In the lockup the word sits one cast width from the mark (`wordmark-lockup.svg`). The word is lowercase "foundry" in Geist 600, outlined, with its ascender matching the mark's height.

**Minimum size.** 16 px. At 16 px and below use `mark-16.svg`, which is hinted to whole pixels. The master is for 24 px and up.

**Colour.** Chalk (`text`, `#eee7dd`) on ink is the default. The cast is `orange` and is the only orange in the mark. Where colour is not available, use `mark-mono.svg` or `mark-16-mono.svg`; they draw in `currentColor`, cast included.

**Don't.**

- Recolour the cast, or add orange anywhere else in the mark.
- Rotate, skew, or stretch it.
- Place it on a photo or busy image. Use ink or a plain surface.
- Outline it, add a stroke, or add effects.

## Open

- The app's chalk ramp (`FoundryTheme.Brand.chalkTop/Mid/Bottom`, `#f2ecdf`, `#e3dbcc`, `#d2c7b3`) and orange side (`accentSide`, `#992f0a`) differ from the site's. They are not pinned by the Swift test yet. Align them when Task A3 re-renders the icon and onboarding mark, then extend the test.
- The download modal is deleted (the app will be notarized), and three of the five near-duplicate surface literals went with it. `#26201a` and `#16120f` remain; fold them into the `ink-raised` levels.
