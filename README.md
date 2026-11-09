# Foundry

Foundry is a native macOS launcher and command palette. It requires macOS 14 or later.

## Download

Grab the latest build from [Releases](https://github.com/hridaya423/foundry/releases/latest), open the DMG and drag Foundry to Applications.

Press **⌘Space** anywhere to open the launcher. First-run setup takes ⌘Space over from Spotlight, and moves Raycast or Alfred to ⌥Space if either holds it. You can record a different shortcut there, and a menu-bar item is always available.

## Features

- Launcher for apps, commands, and System Settings panes, opened with ⌘Space by default
- Guided onboarding with motion polish, a menu bar item, and a searchable Settings window
- Searchable Actions panel (⌘K) with per-action shortcuts and destructive-action styling
- Quicklinks with arguments, including Raycast Quicklinks import
- Raycast-compatible Script Commands and Apple Shortcuts
- File search through Spotlight with the `f ` prefix, `kind:` filters, Quick Look, drag-out, and Finder-style actions (Reveal, Copy Path, Open With, Compress, Rename, Share, Trash, Convert, Extract Text)
- A routed conversion engine — native ImageIO/AVFoundation/PDFKit/textutil/plutil engines plus on-demand Homebrew tools (ffmpeg, ImageMagick, pandoc, LibreOffice), multi-hop routes, PDF merge/extract/OCR, archive handling, staged atomic output, and per-target options (quality, bitrate, DPI, page ranges, metadata stripping, naming templates)
- Scriptable conversion entry points: Finder Open With, Dock drops, and `open -a Foundry --args --convert <paths>` when Foundry is not already running
- Settings backup and import
- Calculator with unit conversions, equations, and a last-10 history
- Time zone lookups and conversions (`now in sf`, `12pm est`)
- Currency exchange via Frankfurter with the rate date shown
- Translator with live language switching
- Media downloads for direct links and automatic YouTube support through yt-dlp, with favicons, file thumbnails, context menus, a completion toast, and aggregate speed
- Clipboard history for text, files, and images, stored locally in SQLite, with pins, filters, plain-text paste, merge-with-previous, and image metadata
- Apple Notes search and quick actions
- File Shelf and file conversion
- Local photo background removal with optional BEN2 support
- Mac utilities, system commands, 34 window layouts, Empty Trash, and a desktop-icons toggle
- Emoji and symbol picker
- Snippets with keywords, placeholders, tag filtering, usage counts, Raycast JSON import, JSON and CSV export, and automatic expansion with per-app exclusions and configurable delimiters
- Vision OCR on images, shelf items, clipboard images, and screen regions
- Color picker with hex/RGB/HSL/HSV/OKLCH/NSColor formats and a recent-colors strip
- QR generation (text and Wi-Fi join) and QR/barcode reading
- Caffeinate keep-awake toggle and a confetti celebration command
- Developer tools for UUIDs, JSON, base64, casing, timestamps, bitwise operations, and base conversion
- Launch-at-login support
- Customizable Home with live widgets, agents, and File Shelf
- AI provider profiles, ordered fallback, model discovery, and Keychain storage
- Local model support for Ollama, LM Studio, MLX, vLLM, llama.cpp, and compatible servers

## Development

The default build creates `build/Foundry.app` without installing or launching it.

```sh
./scripts/build-app.sh
./scripts/verify-packaging.sh
```

Install with `INSTALL_APP=1 ./scripts/build-app.sh`. Add `LAUNCH_APP=1` to launch the installed copy.

Run the tests with `swift test`. The package builds with Swift 6.1 (Xcode 16.3) or Swift 6.2; Liquid Glass surfaces need the Swift 6.2 toolchain and fall back to the standard material otherwise.

Release notes: [docs/release-notes/1.3.0.md](docs/release-notes/1.3.0.md). Performance numbers and how to reproduce them: [docs/benchmarks/](docs/benchmarks/).

YouTube downloads automatically install the current `yt-dlp` formula through Homebrew when needed.
