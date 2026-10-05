#!/bin/zsh
# Stages build/Foundry.app with an /Applications shortcut into a compressed
# read-only DMG. Signs the DMG too when CODE_SIGN_IDENTITY is a real identity;
# with "-" (ad-hoc) the DMG ships unsigned, which is fine — Gatekeeper only
# inspects the app inside.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Foundry"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DMG_PATH="$ROOT_DIR/build/$APP_NAME-$APP_VERSION-build-$BUILD_NUMBER.dmg"

if [[ ! -d "$APP_DIR" ]]; then
    echo "error: $APP_DIR does not exist — run scripts/build-app.sh first" >&2
    exit 1
fi

STAGING="$(mktemp -d -t foundry-dmg)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_DIR" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
diskutil image create from --format UDZO --volumeName "$APP_NAME" "$STAGING" "$DMG_PATH" >/dev/null

if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "Signing $DMG_PATH with $CODE_SIGN_IDENTITY..."
    codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
fi

echo "Created: $DMG_PATH"
