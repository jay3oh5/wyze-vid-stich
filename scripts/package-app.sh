#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$ROOT_DIR/macos/WyzeVidStitch"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="WyzeVidStitch"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> Building WyzeVidStitch via Swift Package Manager..."
cd "$MACOS_DIR"
swift build -c release

BIN_PATH="$MACOS_DIR/.build/release/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    # Some Swift toolchains output to apple/Products/Release
    BIN_PATH=$(find "$MACOS_DIR/.build" -type f -name "$APP_NAME" -perm +111 | grep -v "\.dSYM" | head -n 1)
fi

echo "==> Packaging into $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$MACOS_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$MACOS_DIR/WyzeVidStitch/WyzeVidStitch.entitlements" ]; then
    echo "==> Applying entitlements & ad-hoc codesigning..."
    codesign --force --deep --sign - --entitlements "$MACOS_DIR/WyzeVidStitch/WyzeVidStitch.entitlements" "$APP_BUNDLE"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Creating ZIP archive..."
mkdir -p "$DIST_DIR"
cd "$DIST_DIR"
zip -r "$APP_NAME-macOS.zip" "$APP_NAME.app"

echo "==> Creating DMG image..."
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$APP_NAME-macOS.dmg"

echo "==> Successfully packaged:"
echo "    App: $APP_BUNDLE"
echo "    Zip: $DIST_DIR/$APP_NAME-macOS.zip"
echo "    DMG: $DIST_DIR/$APP_NAME-macOS.dmg"
