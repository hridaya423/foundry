#!/bin/zsh
# Submits a DMG to Apple notarization and staples the ticket on success.
# Credentials, first match wins:
#   1. NOTARY_PROFILE — a profile saved via `xcrun notarytool store-credentials`
#   2. APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID env vars
#      (app-specific password from https://appleid.apple.com)
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 path/to/Foundry.dmg" >&2
    exit 1
fi
DMG_PATH="$1"
if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: $DMG_PATH does not exist" >&2
    exit 1
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    AUTH=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
    echo "error: set NOTARY_PROFILE, or APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID" >&2
    exit 1
fi

echo "Submitting $DMG_PATH for notarization..."
xcrun notarytool submit "$DMG_PATH" "${AUTH[@]}" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
echo "Notarized and stapled: $DMG_PATH"
