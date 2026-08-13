#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Foundry.app"
BUNDLE_DIR="$APP_DIR/Contents/Resources/Foundry_Foundry.bundle"
INSTALL_DIR="/Applications/Foundry.app"
installed_mtime="$(stat -f '%m' "$INSTALL_DIR" 2>/dev/null || true)"

rm -rf "$ROOT_DIR/build"
(cd "$ROOT_DIR" && ./scripts/build-app.sh)

plutil -lint "$APP_DIR/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$APP_DIR/Contents/Info.plist")" == *camera* ]] || {
    echo "error: NSCameraUsageDescription is missing" >&2
    exit 1
}
if /usr/bin/plutil -p "$APP_DIR/Contents/Info.plist" | grep -q 'FoundrySourceRoot'; then
    echo "error: developer source path remains in Info.plist" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_DIR"
ENTITLEMENTS_FILE="$(mktemp -t foundry-entitlements).plist"
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT
codesign --display --entitlements :- "$APP_DIR" 2>/dev/null | tee "$ENTITLEMENTS_FILE" | plutil -lint -
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.camera' "$ENTITLEMENTS_FILE")" == "true" ]] || { echo "error: camera entitlement is missing" >&2; exit 1; }

if grep -R -E -q "$ROOT_DIR|FoundrySourceRoot" "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/Resources"; then
    echo "error: source path remains in packaged metadata or resources" >&2
    exit 1
fi

for required in NOTICE.txt background_removal_worker.py manifest.json background.js emoji.tsv; do
    [[ -f "$BUNDLE_DIR/$required" ]] || { echo "error: missing resource: $required" >&2; exit 1; }
done
if find "$BUNDLE_DIR" -type f \( -name '*.pyc' -o -name '*.sh' -o -name '*.command' -o -name 'feynobg_worker.py' -o -iname '*obsolete*worker*' \) -print -quit | grep -q .; then
    echo "error: stale or undeclared resource found" >&2
    exit 1
fi
if find "$BUNDLE_DIR" -type f -perm -111 -print -quit | grep -q .; then
    echo "error: executable resource found" >&2
    exit 1
fi
if [[ -z "$installed_mtime" && -e "$INSTALL_DIR" ]]; then
    echo "error: default packaging unexpectedly created /Applications/Foundry.app" >&2
    exit 1
fi
if [[ -n "$installed_mtime" && "$(stat -f '%m' "$INSTALL_DIR")" != "$installed_mtime" ]]; then
    echo "error: default packaging modified /Applications/Foundry.app" >&2
    exit 1
fi

echo "Packaging verification passed: staged app only; no install or launch requested."
