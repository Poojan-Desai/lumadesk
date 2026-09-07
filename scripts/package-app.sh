#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-$PROJECT_DIR/dist}"
mkdir -p "$DESTINATION"
DESTINATION="$(cd "$DESTINATION" && pwd)"
cd "$PROJECT_DIR"
swift build -c release --product LumaDesk
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$DESTINATION/LumaDesk.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_DIR/.build/AppIcon.iconset"
cp "$BIN_DIR/LumaDesk" "$APP_DIR/Contents/MacOS/LumaDesk"
swift "$PROJECT_DIR/scripts/make-icon.swift" "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>LumaDesk</string>
<key>CFBundleDisplayName</key><string>LumaDesk</string>
<key>CFBundleIdentifier</key><string>dev.poojandesai.lumadesk</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>LumaDesk</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Poojan Desai. MIT License.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DESTINATION/LumaDesk-macOS.zip"
printf '\nBuilt and ad-hoc signed: %s\nArchive: %s\n' "$APP_DIR" "$DESTINATION/LumaDesk-macOS.zip"
