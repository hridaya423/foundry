#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Foundry.app"
BUNDLE_DIR="$APP_DIR/Contents/Resources/Foundry_Foundry.bundle"
BUNDLE_CONTENTS_DIR="$BUNDLE_DIR/Contents/Resources"
INSTALL_DIR="/Applications/Foundry.app"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
EXPECTED_BUILD_NUMBER="${BUILD_NUMBER:-1}"
installed_mtime="$(stat -f '%m' "$INSTALL_DIR" 2>/dev/null || true)"

rm -rf "$ROOT_DIR/build"
(cd "$ROOT_DIR" && ./scripts/build-app.sh)

plutil -lint "$APP_DIR/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" == "$EXPECTED_VERSION" ]] || {
    echo "error: app version does not match VERSION" >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")" == "$EXPECTED_BUILD_NUMBER" ]] || {
    echo "error: app build number does not match BUILD_NUMBER" >&2
    exit 1
}
if /usr/bin/plutil -p "$APP_DIR/Contents/Info.plist" | grep -q 'FoundrySourceRoot'; then
    echo "error: developer source path remains in Info.plist" >&2
    exit 1
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_DIR/Contents/Info.plist")" == "AppIcon" ]] || {
    echo "error: CFBundleIconFile is missing or wrong" >&2
    exit 1
}
ICON_FILE="$APP_DIR/Contents/Resources/AppIcon.icns"
[[ -f "$ICON_FILE" ]] || { echo "error: AppIcon.icns missing from bundle resources" >&2; exit 1; }
[[ "$(stat -f '%z' "$ICON_FILE")" -gt 10000 ]] || { echo "error: AppIcon.icns is suspiciously small" >&2; exit 1; }
file "$ICON_FILE" | grep -q 'Mac OS X icon' || { echo "error: AppIcon.icns is not a valid icns" >&2; exit 1; }
codesign --verify --deep --strict "$APP_DIR"
SIGNATURE_INFO="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<< "$SIGNATURE_INFO" || {
    echo "error: hardened runtime is not enabled" >&2
    exit 1
}
case "${CODE_SIGN_IDENTITY:-}" in
    "Developer ID Application"*)
        grep -q '^Authority=Developer ID Application' <<< "$SIGNATURE_INFO" || {
            echo "error: app is not signed by a Developer ID Application certificate" >&2
            exit 1
        }
        grep -q '^Timestamp=' <<< "$SIGNATURE_INFO" || {
            echo "error: Developer ID signature has no secure timestamp" >&2
            exit 1
        }
        ;;
    "-")
        grep -q '^Signature=adhoc' <<< "$SIGNATURE_INFO" || {
            echo "error: app is not ad-hoc signed although CODE_SIGN_IDENTITY is -" >&2
            exit 1
        }
        ;;
esac
EXPECTED_ARCHS="${EXPECTED_ARCHS:-$(uname -m)}"
[[ "$(lipo -archs "$APP_DIR/Contents/MacOS/Foundry")" == "$EXPECTED_ARCHS" ]] || {
    echo "error: executable architectures are not: $EXPECTED_ARCHS" >&2
    exit 1
}
ENTITLEMENTS_FILE="$(mktemp -t foundry-entitlements).plist"
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT
codesign --display --entitlements :- "$APP_DIR" 2>/dev/null | tee "$ENTITLEMENTS_FILE" | plutil -lint -

if grep -R -E -q "$ROOT_DIR|FoundrySourceRoot" "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/Resources"; then
    echo "error: source path remains in packaged metadata or resources" >&2
    exit 1
fi

[[ -d "$BUNDLE_CONTENTS_DIR" ]] || BUNDLE_CONTENTS_DIR="$BUNDLE_DIR"
for required in NOTICE.txt background_removal_worker.py manifest.json background.js emoji.tsv; do
    [[ -f "$BUNDLE_CONTENTS_DIR/$required" ]] || { echo "error: missing resource: $required" >&2; exit 1; }
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
