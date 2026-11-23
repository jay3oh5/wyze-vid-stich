#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$ROOT_DIR/rust/wyze-stitcher-core"
KIT_DIR="$ROOT_DIR/macos/WyzeVidStitch/Packages/WyzeStitcherKit"
BUILD_TMP="$ROOT_DIR/target/xcframework-stage"

echo "==> Ensuring macOS Rust targets (arm64 + x86_64) are installed..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo "==> Building release static libraries for Apple Silicon & Intel..."
cargo build --manifest-path "$ROOT_DIR/Cargo.toml" --package wyze-stitcher-core --release --target aarch64-apple-darwin
cargo build --manifest-path "$ROOT_DIR/Cargo.toml" --package wyze-stitcher-core --release --target x86_64-apple-darwin

rm -rf "$BUILD_TMP"
mkdir -p "$BUILD_TMP/bindings" "$BUILD_TMP/headers" "$BUILD_TMP/universal"

echo "==> Generating UniFFI Swift bindings from wyze_stitcher.udl..."
cargo run --manifest-path "$ROOT_DIR/Cargo.toml" --package wyze-stitcher-core --bin uniffi-bindgen -- \
  generate "$CRATE_DIR/src/wyze_stitcher.udl" \
  --language swift \
  --out-dir "$BUILD_TMP/bindings"

echo "==> Creating Universal2 static library with lipo..."
lipo -create \
  "$ROOT_DIR/target/aarch64-apple-darwin/release/libwyze_stitcher_core.a" \
  "$ROOT_DIR/target/x86_64-apple-darwin/release/libwyze_stitcher_core.a" \
  -output "$BUILD_TMP/universal/libwyze_stitcher_core.a"

cp "$BUILD_TMP/bindings/"*.h "$BUILD_TMP/headers/"
cp "$BUILD_TMP/bindings/"*.modulemap "$BUILD_TMP/headers/module.modulemap"

echo "==> Packaging WyzeStitcherCoreFFI.xcframework..."
rm -rf "$KIT_DIR/WyzeStitcherCoreFFI.xcframework"
xcodebuild -create-xcframework \
  -library "$BUILD_TMP/universal/libwyze_stitcher_core.a" \
  -headers "$BUILD_TMP/headers" \
  -output "$KIT_DIR/WyzeStitcherCoreFFI.xcframework"

mkdir -p "$KIT_DIR/Sources/WyzeStitcherKit"
cp "$BUILD_TMP/bindings/wyze_stitcher.swift" "$KIT_DIR/Sources/WyzeStitcherKit/wyze_stitcher.swift"

echo "==> Done! WyzeStitcherKit updated at: $KIT_DIR"
