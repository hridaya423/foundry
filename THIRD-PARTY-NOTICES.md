# Third-party notices

This file records the source and licence of third-party files in the repository that no other file covers. Where the repository and the file's own metadata do not show the source or the licence, the entry says "unknown, owner to confirm".

Other notices:

- `LICENSE`: Foundry's own MIT licence.
- `Sources/Foundry/Resources/BackgroundRemoval/NOTICE.txt`: the BEN2 model and ONNX Runtime.
- `foundry-ad/every-job/SOURCES.md`: footage, stills, audio and fonts of the "Every job." film.
- `foundry-ad/literal/CREDITS.md`: music and sound of the "Literal." film.
- `foundry-ad/vendor/three/LICENSE` and `foundry-ad/literal/vendor/three/LICENSE`: three.js, MIT, revision 185.

## GSAP

| | |
| --- | --- |
| Files | `foundry-ad/vendor/gsap.min.js`, `foundry-ad/every-job/vendor/gsap.min.js`, `foundry-ad/literal/vendor/gsap.min.js` |
| Version | 3.14.2 (the three files are byte-identical, SHA-1 `68fc38bddccecaeead4b9336b6f8b26e5969f96c`) |
| Source | https://gsap.com |
| Licence | Not MIT. The file header reads: "Copyright 2025, GreenSock. All rights reserved. Subject to the terms at https://gsap.com/standard-license." |
| Used by | The film projects in `foundry-ad/` only. The website in `anvil/` does not depend on it (`anvil/package.json`). |

GSAP has been free since 2025 under the standard no-charge licence at that URL. It allows commercial use and shipping the file inside a project. Its one exclusion is tools that compete with Webflow, which these films are not.

## Instrument Serif Italic

| | |
| --- | --- |
| File | `foundry-ad/every-job/assets/fonts/InstrumentSerif-Italic.ttf` |
| Source | https://github.com/Instrument/instrument-serif (from the font's name table) |
| Designer and foundry | Rodrigo Fuenzalida, fragTYPE (from the name table) |
| Copyright | "Copyright 2022 The Instrument Serif Project Authors" (from the name table) |
| Licence | SIL Open Font License 1.1 (from the name table, licence URL https://scripts.sil.org/OFL) |
| Used by | `foundry-ad/every-job/index.html` |

The licence text is `foundry-ad/every-job/assets/fonts/OFL-InstrumentSerif.txt`.

## coast.jpg

| | |
| --- | --- |
| File | `anvil/public/assets/foundry/story/coast.jpg` (960 × 960 px, SHA-1 `481e4ba853971071531f9bfc3321ab5bc31793c9`) |
| Source | unknown, owner to confirm |
| Licence | unknown, owner to confirm |
| Used by | The clipboard card in the story (`anvil/app/foundry/story/clipboard-motion.ts`) and the brand page background (`anvil/app/brand/brand.css`) |

The file has no author, copyright or source field. `progress.md` records "coast.jpg has no recorded source" and "Coast photo (no recorded source)". The alt text calls it "an illustrative clipboard image". It looks generated, and no stock or photographer source has been found. Replace it if a source turns up that forbids this use.

## emoji.tsv

| | |
| --- | --- |
| File | `Sources/Foundry/Resources/emoji.tsv` (3,944 lines: emoji, name, search keywords) |
| Source | emojibase-data (https://emojibase.dev), built on Unicode CLDR |
| Licence | MIT (emojibase); Unicode License v3 (CLDR) |
| Used by | The emoji picker, bundled by `Package.swift` |

The file has no header. It entered the repository in commit `4caca23` ("remove file indexer and add emoji", 2026-06-25) without a source note. Its names and keywords match emojibase-data 16.0.3 entry for entry (for example 😀: "grinning face", cheerful, cheery, face, grin, happy, laugh, nice, smile, smiling, teeth). emojibase-data is MIT-licensed, and its labels come from Unicode CLDR under the Unicode License v3.
