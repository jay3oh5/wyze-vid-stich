#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$ROOT_DIR/macos/WyzeVidStitch"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="WyzeVidStitch"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_STAGE="$DIST_DIR/.dmg-stage"

echo "==> Building WyzeVidStitch via Swift Package Manager (Universal2)..."
cd "$MACOS_DIR"

if swift build -c release --arch arm64 --arch x86_64; then
    BIN_PATH=$(find "$MACOS_DIR/.build" -type f -name "$APP_NAME" -perm +111 | grep -v "\.dSYM" | head -n 1)
else
    echo "==> Falling back to individual arch build and lipo merge..."
    swift build -c release --triple arm64-apple-macosx14.0
    swift build -c release --triple x86_64-apple-macosx14.0
    mkdir -p "$MACOS_DIR/.build/universal"
    ARM_BIN=$(find "$MACOS_DIR/.build" -path "*/arm64*/$APP_NAME" -type f -perm +111 | head -n 1)
    INTEL_BIN=$(find "$MACOS_DIR/.build" -path "*/x86_64*/$APP_NAME" -type f -perm +111 | head -n 1)
    lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$MACOS_DIR/.build/universal/$APP_NAME"
    BIN_PATH="$MACOS_DIR/.build/universal/$APP_NAME"
fi

echo "==> Packaging into $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$MACOS_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$ROOT_DIR/scripts/generate-icon.sh" ]; then
    chmod +x "$ROOT_DIR/scripts/generate-icon.sh"
    "$ROOT_DIR/scripts/generate-icon.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ -f "$MACOS_DIR/WyzeVidStitch/WyzeVidStitch.entitlements" ]; then
    echo "==> Applying entitlements & ad-hoc codesigning..."
    codesign --force --deep --sign - --entitlements "$MACOS_DIR/WyzeVidStitch/WyzeVidStitch.entitlements" "$APP_BUNDLE"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Creating ZIP archive..."
mkdir -p "$DIST_DIR"
cd "$DIST_DIR"
rm -f "$APP_NAME-macOS.zip"
zip -r "$APP_NAME-macOS.zip" "$APP_NAME.app"

echo "==> Creating drag-to-Applications DMG image..."
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
    -volname "Wyze Vid Stitch" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$APP_NAME-macOS.dmg"

rm -rf "$DMG_STAGE"

echo "==> Successfully packaged:"
echo "    App: $APP_BUNDLE"
echo "    Zip: $DIST_DIR/$APP_NAME-macOS.zip"
echo "    DMG: $DIST_DIR/$APP_NAME-macOS.dmg"
