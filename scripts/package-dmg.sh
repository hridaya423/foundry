#!/bin/zsh
# Stages build/Foundry.app with an /Applications shortcut into a compressed
# read-only DMG with a branded window: chalk background art (from
# Supporting/DMGBackground.png — regenerate via scripts/render-dmg-background.swift),
# fixed icon positions, a custom volume icon, and no toolbar/status bar.
#
# Flow: blank APFS read-write image → attach under /Volumes → stage files →
# script Finder for the icon-view layout (this writes .DS_Store) → detach →
# convert to UDZO. If Finder automation is unavailable (headless CI), we fall
# back to a plain DMG rather than failing — a valid artifact beats a broken
# release, but the fallback prints a loud warning.
#
# Signs the DMG too when CODE_SIGN_IDENTITY is a real identity; with "-" the
# DMG ships unsigned, which is fine — Gatekeeper only inspects the app inside.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Foundry"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DMG_PATH="$ROOT_DIR/build/$APP_NAME-$APP_VERSION-build-$BUILD_NUMBER.dmg"
BG_FILE="$ROOT_DIR/Supporting/DMGBackground.png"
BG_FILE_1X="$ROOT_DIR/Supporting/DMGBackground@1x.png"
ICON_FILE="$ROOT_DIR/Supporting/AppIcon.icns"
WINDOW_BOUNDS="{200, 120, 740, 480}"   # 540×360 — matches render-dmg-background.swift
APP_ICON_POS="{130, 150}"
APPS_ICON_POS="{410, 150}"
ICON_SIZE=112

if [[ ! -d "$APP_DIR" ]]; then
    echo "error: $APP_DIR does not exist — run scripts/build-app.sh first" >&2
    exit 1
fi
if [[ ! -f "$BG_FILE" || ! -f "$BG_FILE_1X" ]]; then
    echo "error: DMG background art missing — run scripts/render-dmg-background.swift" >&2
    exit 1
fi

rm -f "$DMG_PATH"

STAGING="$(mktemp -d -t foundry-dmg)"
trap 'rm -rf "$STAGING"' EXIT

# --- Attempt 1: branded DMG via read-write image + Finder layout -------------

branded_dmg() {
    setopt localoptions err_return
    local rw_dmg="$STAGING/$APP_NAME-rw.dmg"
    local size_mb=$(( $(du -sm "$APP_DIR" | awk '{print $1}') + 48 ))

    diskutil image create blank --size "${size_mb}m" --volumeName "$APP_NAME" --fs APFS "$rw_dmg" >/dev/null

    # Mount under /Volumes/<volname> — Finder resolves disks by mount-point
    # basename, so a stray "Foundry 1" mount still layouts correctly.
    local attach_out mount vol_name
    attach_out="$(hdiutil attach -readwrite -noverify -nobrowse "$rw_dmg" 2>/dev/null)"
    mount="$(echo "$attach_out" | awk -F'\t' '$NF ~ /^\/Volumes\// { m = $NF } END { print m }')"
    vol_name="$(basename "$mount")"
    if [[ -z "$mount" || ! -d "$mount" ]]; then
        echo "warning: could not determine mount point" >&2
        return 1
    fi

    # Ensure detach even if layout scripting fails mid-way.
    {
        cp -R "$APP_DIR" "$mount/$APP_NAME.app"
        ln -s /Applications "$mount/Applications"
        mkdir -p "$mount/.background"
        # One multi-resolution TIFF; Finder upscales a lone 1x PNG on Retina.
        tiffutil -cathidpicheck "$BG_FILE_1X" "$BG_FILE" -out "$mount/.background/background.tiff" >/dev/null 2>&1

        # Custom volume icon. APFS honors .VolumeIcon.icns + the
        # kHasCustomIcon bit (0x0400) in the volume's com.apple.FinderInfo
        # xattr — SetFile is avoided because on APFS it can relocate the
        # icon into resources that survive attachment but not conversion.
        cp "$ICON_FILE" "$mount/.VolumeIcon.icns"
        xattr -wx com.apple.FinderInfo \
            "0000000000000000040000000000000000000000000000000000000000000000" \
            "$mount" 2>/dev/null || true

        /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$vol_name"
        open
        delay 0.5
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to $WINDOW_BOUNDS
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to $APP_ICON_POS
        set position of item "Applications" of container window to $APPS_ICON_POS
        close
        open
        update without registering applications
        close
    end tell
end tell
APPLESCRIPT
    } always {
        sync
        sleep 1
        hdiutil detach "$mount" -quiet 2>/dev/null || hdiutil detach "$mount" -force -quiet 2>/dev/null || true
    }

    hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null 2>&1
    [[ -f "$DMG_PATH" ]]
}

if branded_dmg; then
    echo "Branded DMG layout applied (background, icon positions, volume icon)."
else
    echo "warning: branded DMG layout failed (headless environment?); falling back to plain DMG" >&2
    PLAIN_STAGING="$(mktemp -d -t foundry-dmg-plain)"
    cp -R "$APP_DIR" "$PLAIN_STAGING/$APP_NAME.app"
    ln -s /Applications "$PLAIN_STAGING/Applications"
    diskutil image create from --format UDZO --volumeName "$APP_NAME" "$PLAIN_STAGING" "$DMG_PATH" >/dev/null
    rm -rf "$PLAIN_STAGING"
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "Signing $DMG_PATH with $CODE_SIGN_IDENTITY..."
    codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
fi

echo "Created: $DMG_PATH"
