#!/usr/bin/env bash
# Build the SwiftPM executable and wrap it in a menu-bar .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="Portcall"
BUNDLE_ID="com.local.portcall"
VERSION="0.1.0"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>Portcall</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the binary launches without Gatekeeper friction.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP"
echo "    Launch with: open \"$APP\""
