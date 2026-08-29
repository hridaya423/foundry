#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Foundry"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if ! printf '%s\n' "$APP_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: VERSION must contain a semantic version such as 1.0.0" >&2
    exit 1
fi
if ! printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$'; then
    echo "error: BUILD_NUMBER must be a positive integer" >&2
    exit 1
fi

if [[ "${LAUNCH_APP:-0}" == "1" && "${INSTALL_APP:-0}" != "1" ]]; then
    echo "error: LAUNCH_APP=1 requires INSTALL_APP=1" >&2
    exit 1
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
else
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | sed -n '1p')"
    SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
fi

echo "Building $APP_NAME in release mode..."
swift package clean
swift build -c release --product "$APP_NAME"

EXECUTABLE="$(swift build -c release --show-bin-path)/$APP_NAME"
RESOURCE_BUNDLE="$(swift build -c release --show-bin-path)/Foundry_Foundry.bundle"
DEBUG_EXECUTABLE="$(swift build --show-bin-path)/$APP_NAME"

if [[ "${INSTALL_APP:-0}" == "1" ]]; then
    # Remove only the legacy source executable entry. Keep the packaged app entry
    # and every unrelated login item intact.
    /usr/bin/osascript - "$DEBUG_EXECUTABLE" "$INSTALL_DIR" <<'APPLESCRIPT' >/dev/null 2>&1 || true
    on run argv
        tell application "System Events"
            repeat with index from (count of login items) to 1 by -1
                set loginItem to login item index
                if ((path of loginItem) as text) is item 1 of argv or ((path of loginItem) as text) is item 2 of argv then
                    delete login item index
                end if
            end repeat
        end tell
    end run
APPLESCRIPT

    INSTALLED_EXECUTABLE="$INSTALL_DIR/Contents/MacOS/$APP_NAME"
    if pgrep -f "$INSTALLED_EXECUTABLE" >/dev/null 2>&1; then
        echo "Stopping the running installed copy..."
        pkill -TERM -f "$INSTALLED_EXECUTABLE" || true
        for _ in {1..50}; do
            pgrep -f "$INSTALLED_EXECUTABLE" >/dev/null 2>&1 || break
            sleep 0.1
        done
    fi

fi

# The staged app is an output, never an incremental input. Removing it first
# prevents deleted resources from surviving a later packaging run.
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

RESOURCE_BUNDLE_DIR="$RESOURCES_DIR/Foundry_Foundry.bundle"
if [[ ! -d "$RESOURCE_BUNDLE_DIR" ]]; then
    echo "error: SwiftPM resource bundle is missing" >&2
    exit 1
fi

if find "$RESOURCE_BUNDLE_DIR" -type f \( -name '*.pyc' -o -name 'feynobg_worker.py' -o -iname '*feyno*worker*' -o -iname '*obsolete*worker*' \) -print -quit | grep -q .; then
    echo "error: stale or obsolete worker resource found" >&2
    exit 1
fi
if find "$RESOURCE_BUNDLE_DIR" -type f \( -name '*.sh' -o -name '*.command' -o -name '*.pyc' \) -print -quit | grep -q .; then
    echo "error: undeclared script resource found" >&2
    exit 1
fi
if find "$RESOURCE_BUNDLE_DIR" -type f -perm -111 -print -quit | grep -q .; then
    echo "error: unexpected executable resource found" >&2
    exit 1
fi

for required in NOTICE.txt background_removal_worker.py manifest.json background.js emoji.tsv; do
    if [[ ! -f "$RESOURCE_BUNDLE_DIR/$required" ]]; then
        echo "error: required resource is missing: $required" >&2
        exit 1
    fi
done

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Foundry</string>
    <key>CFBundleExecutable</key>
    <string>Foundry</string>
    <key>CFBundleIdentifier</key>
    <string>com.hridya.foundry</string>
    <key>CFBundleName</key>
    <string>Foundry</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Foundry uses the camera to show a live preview when you open Camera.</string>
</dict>
</plist>
EOF

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Signing $APP_NAME with an ad-hoc identity..."
else
    echo "Signing $APP_NAME with $SIGNING_IDENTITY..."
fi
codesign --force --deep --options runtime --entitlements "$ROOT_DIR/Supporting/Foundry.entitlements" --sign "$SIGNING_IDENTITY" "$APP_DIR"
# codesign writes diagnostics to stderr; keep them out of the plist stream.
if ! codesign --display --entitlements :- "$APP_DIR" 2>/dev/null | plutil -lint - >/dev/null; then
    echo "error: signed app entitlements are not valid plist data" >&2
    exit 1
fi

if [[ "${INSTALL_APP:-0}" == "1" ]]; then
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"
    /usr/bin/defaults write com.hridya.foundry foundry.sourceRoot "$ROOT_DIR"
fi

if [[ "${INSTALL_APP:-0}" == "1" ]]; then
    echo "Installed: $INSTALL_DIR"
else
    echo "Staged: $APP_DIR"
fi
if [[ "${LAUNCH_APP:-0}" == "1" ]]; then
    echo "Launching once so the app can register its login-item setting..."
    open "$INSTALL_DIR"
fi
