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

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
else
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | sed -n '1p')"
    SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
fi

echo "Building $APP_NAME in release mode..."
swift build -c release --product "$APP_NAME"

EXECUTABLE="$(swift build -c release --show-bin-path)/$APP_NAME"
RESOURCE_BUNDLE="$(swift build -c release --show-bin-path)/Foundry_Foundry.bundle"
DEBUG_EXECUTABLE="$(swift build --show-bin-path)/$APP_NAME"

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

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>FoundrySourceRoot</key>
    <string>$ROOT_DIR</string>
</dict>
</plist>
EOF

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Signing $APP_NAME with an ad-hoc identity..."
else
    echo "Signing $APP_NAME with $SIGNING_IDENTITY..."
fi
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"

rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "Installed: $INSTALL_DIR"
echo "Launching once so the app can register its login-item setting..."
open "$INSTALL_DIR"
