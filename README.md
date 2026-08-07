# Foundry

Foundry is a native macOS alternative to raycast

## Features

- Launcher for apps and commands
- Calculator with unit conversions
- Currency exchange via Frankfurter
- Translator with live language switching
- Camera preview inside the launcher
- Media downloads with youtube downloads via `yt-dlp`
- Clipboard history for text, files, and images
- Apple Notes search and quick actions
- File Shelf for temporary file actions
- Local photo background removal for still images
- Experimental BEN2 background removal with an optional local ONNX runtime
- Mac utilities
- Activity Monitor view
- Emoji and symbol picker
- Snippets with create/import support
- Developer tools for UUIDs, JSON, base64, casing, timestamps, bitwise ops, and base conversion
- System commands
- Launch-at-login prompt on first run
- Customizable Home strip with live widgets, agents, and File Shelf
- File conversion
- AI provider profiles with Apple Intelligence, Ollama, OpenAI-compatible endpoints, OpenAI, Anthropic, Gemini, and vendor presets
- Local model support for Ollama, LM Studio, MLX, vLLM, llama.cpp, and compatible servers
- API keys stored in macOS Keychain with ordered provider fallback and model discovery

## Development

```sh
swift build
swift run Foundry
```