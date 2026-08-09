#!/bin/bash
# Build a distributable DeepSeekTray.app bundle (adhoc-signed, zip).
# Usage: scripts/package.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP_NAME="DeepSeekTray"
BUILD_DIR=".build/release"
DIST="dist"

echo "==> Building release binary for arm64 (Apple Silicon)..."
swift build -c release --triple arm64-apple-macosx --disable-sandbox

BIN=".build/arm64-apple-macosx/release/$APP_NAME"
[ -x "$BIN" ] || { echo "missing binary: $BIN"; exit 1; }

STAGE="$DIST/$APP_NAME.app"
rm -rf "$STAGE" "$DIST/$APP_NAME-$VERSION.zip"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

cp "$BIN" "$STAGE/Contents/MacOS/$APP_NAME"
cp "assets/AppIcon/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>DeepSeek Tray</string>
    <key>CFBundleIdentifier</key><string>com.deepseek.tray</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

# Adhoc codesign (no Developer ID, no sandbox): Gatekeeper will warn on first
# open — users right-click -> Open once, or xattr -dr com.apple.quarantine.
codesign --force --sign - "$STAGE"

ditto -c -k --keepParent "$STAGE" "$DIST/$APP_NAME-$VERSION.zip"
echo "==> Built $DIST/$APP_NAME-$VERSION.zip"
