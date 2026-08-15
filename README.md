# Foundry

Foundry is a native macOS launcher and command palette. It requires macOS 14 or later.

## Features

- Launcher for apps and commands
- Calculator with unit conversions
- Currency exchange via Frankfurter
- Translator with live language switching
- Camera preview inside the launcher
- Media downloads for direct links, Cobalt, and automatic YouTube support through yt-dlp
- Persistent local clipboard history for text, files, and images
- Apple Notes search and quick actions
- File Shelf and file conversion
- Local photo background removal with optional BEN2 support
- Mac utilities, system commands, and window tiling
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

YouTube downloads automatically install the current `yt-dlp` formula through Homebrew when needed.
