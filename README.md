# Foundry

Foundry is a native macOS launcher and command palette. It requires macOS 14 or later.

## Download

Grab the latest build from [Releases](https://github.com/hridaya423/foundry/releases/latest) — open the DMG and drag Foundry to Applications. On first launch, right-click the app and choose **Open** to approve it.

Press **⌥Space** anywhere to open the launcher. The first-run setup lets you pick a different shortcut — including ⌘Space, which Foundry can take over from Spotlight automatically — and a menu-bar item is always available.

## Features

- Launcher for apps, commands, and System Settings panes, opened with ⌥Space by default
- Guided onboarding, a menu bar item, and a searchable Settings window
- Searchable Actions panel (⌘K) with per-action shortcuts
- Quicklinks with arguments, including Raycast Quicklinks import
- Raycast-compatible Script Commands and Apple Shortcuts
- File search through Spotlight with the `f ` prefix, `kind:` filters, Quick Look, and drag-out
- Settings backup and import
- Calculator with unit conversions, equations, and a last-10 history
- Currency exchange via Frankfurter with the rate date shown
- Translator with live language switching
- Camera preview inside the launcher
- Media downloads for direct links, Cobalt, and automatic YouTube support through yt-dlp
- Clipboard history for text, files, and images, stored locally in SQLite, with pins, filters, and paste on Return
- Apple Notes search and quick actions
- File Shelf and file conversion
- Local photo background removal with optional BEN2 support
- Mac utilities, system commands, and 34 window layouts
- Emoji and symbol picker
- Snippets with create, import, and automatic expansion support
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

Release notes: [docs/release-notes/1.1.0.md](docs/release-notes/1.1.0.md). Performance numbers and how to reproduce them: [docs/benchmarks/2026-09-26-foundry-1.1-report.md](docs/benchmarks/2026-09-26-foundry-1.1-report.md).

YouTube downloads automatically install the current `yt-dlp` formula through Homebrew when needed.
