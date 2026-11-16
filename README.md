<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/banner-dark.svg">
    <img alt="Foundry" src=".github/assets/banner-light.svg" width="100%">
  </picture>
</p>

<p align="center"><b>The app you never open. Opens everything.</b><br>A native macOS launcher in Swift: apps, files, clipboard, snippets, windows, conversions and AI in one bar.<br>A free, open-source alternative to Spotlight, Raycast and Alfred.</p>

<p align="center">
  <a href="https://github.com/hridaya423/foundry/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/hridaya423/foundry?style=flat-square&color=fa6428"></a>
  <a href="https://github.com/hridaya423/foundry/actions/workflows/test.yml"><img alt="Tests" src="https://img.shields.io/github/actions/workflow/status/hridaya423/foundry/test.yml?branch=main&style=flat-square&label=tests"></a>
  <img alt="macOS 14 or later on Apple silicon" src="https://img.shields.io/badge/macOS-14%2B%20%C2%B7%20Apple%20silicon-0f0d0c?style=flat-square">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/hridaya423/foundry?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg"><b>Download Foundry.dmg</b></a> · <a href="https://foundry.hridya.tech">Website</a> · <a href="https://foundry.hridya.tech/faq">FAQ</a> · <a href="https://foundry.hridya.tech/proof">Proof</a> · <a href="https://foundry.hridya.tech/privacy">Privacy</a> · <a href="https://foundry.hridya.tech/changelog">Changelog</a>
</p>

Press ⌘ Space and type. Foundry finds the app, the file or the thing you copied an hour ago. It also does the job in the same bar: it converts a HEIC to PNG, tiles a window, expands a snippet or answers a question. The app is 9.7 MB, has no third-party Swift packages and is free under the MIT license.

<p align="center">
  <img alt="Foundry converts 5 km to 3.11 mi as you type" src=".github/assets/convert.png" width="49%">
  <img alt="Foundry shows the time in Tokyo next to your own time" src=".github/assets/time-zones.png" width="49%">
</p>

## Install

Foundry needs an Apple silicon Mac with macOS 14 or later.

1. Download [Foundry.dmg](https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg). It is signed with a Developer ID and notarized by Apple.
2. Open the DMG and drag Foundry to Applications.
3. Open Foundry and follow the four setup steps.

You can also install it with Homebrew:

```sh
brew install --cask hridaya423/tap/foundry
```

Setup asks before it takes ⌘ Space. If you choose "Take ⌘ Space", Foundry moves Spotlight off the shortcut. It also moves Raycast or Alfred to ⌥ Space if one of them holds ⌘ Space, and Settings › General can give the shortcut back. The other choice is ⌥ Space. Setup also imports your snippets from Alfred or from a Raycast export.

Once a day, Foundry asks GitHub for the newest release. When a newer version exists, Home shows a notice, and Download opens the release page. To stop the check, turn off Check for updates in Settings › About. With Homebrew, run `brew upgrade --cask foundry`.

## Numbers

| | Foundry | For comparison |
| --- | --- | --- |
| App size on disk | **9.7 MB** (1.4.0) | Raycast 2.5.3: 224 MB. Tinycast 0.11.3: 13.6 MB. |
| Memory after launch | **81% less than Raycast 2.5.3** (115 MB against 620 MB, Foundry 1.1.0) | Tinycast is lighter: 40 MB against Foundry's 60 to 120 MB. |
| Keystroke to results | **16.8 ms** p50, 35.6 ms p95 (1.2.0) | Engine time in a test, over 132 samples. Drawing time is not included. |
| Third-party Swift packages | **0** | `Package.swift` declares none. |

The memory figures are the worse of two order-swapped runs on an Apple M4 Pro. The app size comes from the 1.4.0 release zip. [`latest.json`](docs/benchmarks/latest.json) gives the version, the date, the machine and the raw record for each figure. In the same runs, Raycast opened its panel faster than the 1.1.0 release build. The [proof page](https://foundry.hridya.tech/proof) lists every figure, and the [methodology page](https://foundry.hridya.tech/methodology) explains each test.

## What to type

| Type | You get |
| --- | --- |
| `saf` | Safari, or any app, setting or command. ⌘1 to ⌘8 open your favorites. |
| `f invoice kind:pdf` | File search, with Quick Look on Space and Finder actions on ⌘K. |
| `clipboard` | Clipboard history for text, files, links and images, stored on your Mac. |
| `5 km to miles` | The calculator. It also does dates, currencies and time zones, such as `time in sf now`. |
| `left half` | One of 34 window layouts. Each one can have its own shortcut. |
| `emoji` | The emoji and symbol picker. |
| `ai draft a polite no` | An answer from Apple Intelligence on the device, or from a provider you add. |

⌘K opens every action for the selected result. Esc clears the query first and closes the panel second.

## Features

- **Launcher.** Apps, System Settings panes, Apple Shortcuts, quicklinks with arguments, and Script Commands in the Raycast format.
- **Files.** Spotlight file search, a File Shelf for files in transit, and conversion between image, audio, video, PDF and document formats. Foundry uses ImageIO, AVFoundation and PDFKit first. It installs ffmpeg, ImageMagick, pandoc or LibreOffice with Homebrew only after you approve a setup sheet.
- **Text.** Clipboard history, snippets that expand as you type, text capture from the screen (OCR), QR codes, a colour picker and developer tools for JSON, base64, UUIDs and timestamps.
- **AI.** Apple Intelligence by default. You can add OpenAI, Anthropic, Gemini and other providers, or a local server such as Ollama, LM Studio or llama.cpp. Foundry stores API keys in the Keychain.
- **Home.** Widgets for the date, CPU and memory, storage and battery, plus the shelf for your coding agents' sessions.

## Privacy

Foundry has no account, no analytics and no crash reporting. Clipboard history, snippets, settings and AI chats stay on your Mac. A few features call other services, such as currency rates, the update check and any AI provider you add. The [privacy page](https://foundry.hridya.tech/privacy) lists every request that leaves the Mac, when it happens and how to avoid it.

## Development

Foundry is a Swift package. It builds with Swift 6.1 (Xcode 16.3) or Swift 6.2. Liquid Glass surfaces need Swift 6.2 and fall back to the standard material on 6.1.

```sh
swift build --build-tests
swift test
./scripts/build-app.sh
```

`build-app.sh` writes `build/Foundry.app` and does not install it. Set `INSTALL_APP=1` to install it, and add `LAUNCH_APP=1` to launch it. `swift test` is safe to run while Foundry is open. `./scripts/check.sh` runs the lints, the test build and the website checks. [`AGENTS.md`](AGENTS.md) describes each script.

The website is a Next.js app in [`anvil/`](anvil/). Release notes are in [`docs/release-notes/`](docs/release-notes/), and [`docs/distribution.md`](docs/distribution.md) covers signing and releases.

## Contributing

Bug reports and pull requests are welcome. In an [issue](https://github.com/hridaya423/foundry/issues/new), include your macOS version, the Foundry version from Settings › About, and the steps that show the problem. Run `./scripts/check.sh` before you open a pull request.

## License

MIT. See [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
