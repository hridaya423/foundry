# Foundry

A macOS launcher: a Swift package at the repo root, and its website in `anvil/` (Next.js, see `anvil/AGENTS.md`).

## Build

- `swift build --build-tests` builds the app and the tests. It must end with `Build complete!`.
- `./scripts/build-app.sh` stages `build/Foundry.app`. It does not install or launch it.
- `./scripts/verify-packaging.sh` builds the app and checks the bundle, the signature, hardened runtime and architecture.
- Release builds are arm64 only. The minimum macOS is 14.0.

## Tests

Foundry is usually running on the dev Mac. The full suite unlinks its agent socket and registers global hotkeys. Do not run `swift test` unfiltered. Run classes: `swift test --filter 'ClassA|ClassB'`.

Do not run test classes that construct `CommandPanelState`, `ShellController`, `OnboardingState` or `PanelController`, or that use `NSPasteboard.general`, unless the task says to.

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
