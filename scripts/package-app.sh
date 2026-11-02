#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-$PROJECT_DIR/dist}"
mkdir -p "$DESTINATION"
DESTINATION="$(cd "$DESTINATION" && pwd)"
cd "$PROJECT_DIR"
swift build -c release --product LumaDesk
BIN_DIR="$(swift build -c release --show-bin-path)"

# Assemble only files from this build. Reusing an existing bundle can silently
# retain obsolete binaries/resources and include them in a new signed archive.
STAGING_DIR="$(mktemp -d "$DESTINATION/.lumadesk-package.XXXXXX")"
APP_DIR="$STAGING_DIR/LumaDesk.app"
ARCHIVE="$STAGING_DIR/LumaDesk-macOS.zip"
FINAL_APP="$DESTINATION/LumaDesk.app"
FINAL_ARCHIVE="$DESTINATION/LumaDesk-macOS.zip"
PUBLISHED=0
NEW_APP_INSTALLED=0
NEW_ARCHIVE_INSTALLED=0
LOCK_DIR="$DESTINATION/.lumadesk-package.lock"
LOCK_HELD=0
cleanup() {
    local remove_staging=1
    if [[ "$PUBLISHED" -eq 0 ]]; then
        # A rename failure during publication restores the previous outputs.
        # If restoration itself fails, retain the backups for manual recovery.
        if [[ "$NEW_ARCHIVE_INSTALLED" -eq 1 ]] && ! mv "$FINAL_ARCHIVE" "$STAGING_DIR/failed-archive.zip"; then remove_staging=0; fi
        if [[ "$NEW_APP_INSTALLED" -eq 1 ]] && ! mv "$FINAL_APP" "$STAGING_DIR/failed-LumaDesk.app"; then remove_staging=0; fi
        if [[ -e "$STAGING_DIR/previous-LumaDesk.app" || -L "$STAGING_DIR/previous-LumaDesk.app" ]]; then
            if [[ -e "$FINAL_APP" || -L "$FINAL_APP" ]] || ! mv "$STAGING_DIR/previous-LumaDesk.app" "$FINAL_APP"; then remove_staging=0; fi
        fi
        if [[ -e "$STAGING_DIR/previous-archive.zip" || -L "$STAGING_DIR/previous-archive.zip" ]]; then
            if [[ -e "$FINAL_ARCHIVE" || -L "$FINAL_ARCHIVE" ]] || ! mv "$STAGING_DIR/previous-archive.zip" "$FINAL_ARCHIVE"; then remove_staging=0; fi
        fi
    fi
    if [[ "$remove_staging" -eq 1 ]]; then
        rm -rf -- "$STAGING_DIR"
    else
        printf 'Previous package backups retained for recovery: %s\n' "$STAGING_DIR" >&2
    fi
    if [[ "$LOCK_HELD" -eq 1 ]]; then rmdir "$LOCK_DIR"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! mkdir "$LOCK_DIR"; then
    printf 'Package destination is locked by another invocation: %s\n' "$LOCK_DIR" >&2
    exit 1
fi
LOCK_HELD=1

SOURCE_COMMIT="$(git rev-parse --verify HEAD 2>/dev/null || true)"
SOURCE_STATE="unavailable"
if [[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    if [[ -z "$(git status --porcelain --untracked-files=normal)" ]]; then SOURCE_STATE="clean"; else SOURCE_STATE="modified"; fi
else
    SOURCE_COMMIT="unavailable"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$STAGING_DIR/AppIcon.iconset"
cp "$BIN_DIR/LumaDesk" "$APP_DIR/Contents/MacOS/LumaDesk"
swift "$PROJECT_DIR/scripts/make-icon.swift" "$STAGING_DIR/AppIcon.iconset"
iconutil -c icns "$STAGING_DIR/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>LumaDesk</string>
<key>CFBundleDisplayName</key><string>LumaDesk</string>
<key>CFBundleIdentifier</key><string>dev.poojandesai.lumadesk</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>LumaDesk</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LumaDeskSourceCommit</key><string>$SOURCE_COMMIT</string>
<key>LumaDeskSourceState</key><string>$SOURCE_STATE</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Poojan Desai. MIT License.</string>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE"

# The destination is on the same filesystem as staging, so each move is a
# rename. A complete verified bundle/archive precedes any output replacement.
if [[ -e "$FINAL_APP" || -L "$FINAL_APP" ]]; then mv "$FINAL_APP" "$STAGING_DIR/previous-LumaDesk.app"; fi
if [[ -e "$FINAL_ARCHIVE" || -L "$FINAL_ARCHIVE" ]]; then mv "$FINAL_ARCHIVE" "$STAGING_DIR/previous-archive.zip"; fi
mv "$APP_DIR" "$FINAL_APP"
NEW_APP_INSTALLED=1
mv "$ARCHIVE" "$FINAL_ARCHIVE"
NEW_ARCHIVE_INSTALLED=1
PUBLISHED=1
printf '\nBuilt preview 0.2.0 and ad-hoc signed: %s\nArchive: %s\nSource: %s (%s)\n' "$FINAL_APP" "$FINAL_ARCHIVE" "$SOURCE_COMMIT" "$SOURCE_STATE"
