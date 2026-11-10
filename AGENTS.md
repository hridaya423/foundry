# Foundry

A macOS launcher: a Swift package at the repo root, and its website in `anvil/` (Next.js, see `anvil/AGENTS.md`).

## Build

- `swift build --build-tests` builds the app and the tests. It must end with `Build complete!`.
- `./scripts/build-app.sh` stages `build/Foundry.app`. It does not install or launch it.
- `./scripts/verify-packaging.sh` builds the app and checks the bundle, the signature, hardened runtime and architecture.
- Release builds are arm64 only. The minimum macOS is 14.0.

## Tests

`swift test` is safe to run while Foundry is open. Tests get the live agent socket, pasteboard, clipboard database, preferences and Trash through the seams in `Tests/FoundryTests/Helpers/IsolatedMachine.swift`, and `./scripts/lint-tests-isolation.sh` fails when a test bypasses them.

Tests that open real windows or register global hotkeys skip unless `FOUNDRY_WINDOW_TESTS=1` is set. Set it only on a machine where Foundry is not running.

## Lints

All three exit 0 on a clean tree. CI runs them.

- `./scripts/lint-lines.sh`: Swift lines over 160 characters. `--tests` also scans `Tests/`.
- `./scripts/lint-design.sh`: literal font sizes, colours, opacities, radii and durations outside `FoundryTheme.swift`.
- `./scripts/lint-l10n.sh`: strings that skip the localization catalog.

`./scripts/check.sh` runs every `scripts/lint-*.sh`, `swift build --build-tests` and the website checks.

## Website

From `anvil/`, after `npm ci`: `npx tsc --noEmit`, `npx eslint .`, `npm test`, `npx next build`. All four must pass. CI runs them in the `website` job.

## Releases

Bumping `VERSION` on `main` triggers `.github/workflows/release.yml`. A commit message containing `[skip ci]` skips every workflow. Signing, notarization and the secrets are in `docs/distribution.md`. Release notes live in `docs/release-notes/<version>.md` and become the release body.
