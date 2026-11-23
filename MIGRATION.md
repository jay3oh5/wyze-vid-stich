# Native macOS Migration Guide (Rust Core + UniFFI + SwiftUI)

This repository contains both the original Node.js/React web prototype and the native **macOS 14+ (Sonoma)** implementation powered by a portable Rust core (`wyze-stitcher-core`) and Mozilla UniFFI Swift bindings.

## Architecture Overview

1. **Portable Rust Core (`rust/wyze-stitcher-core`)**
   - **`mp4-merge`**: Fast, lossless container-level MP4 concatenation (`src/merger.rs`) with atomic `.tmp.mp4` staging and progress throttling.
   - **Rayon Parallel Scanner (`src/scanner.rs`)**: Multi-threaded directory walker for `/record/YYYYMMDD/HH/MM.mp4`, computing clip counts, missing minute gaps (`00`–`59`), density buckets, and a fast zero-decode MP4 `stsd` header check for legacy Wyze non-AAC audio (`ulaw`/`alaw`/`pcm`).
   - **Tokio Sequential Queue (`src/queue.rs`)**: Single-worker background queue with per-job cancellation flags, real-time push callbacks, atomic verification, and optional post-compile source clip cleanup.
   - **Configurable Output Naming (`src/naming.rs`)**: Defaults to sortable 24-hour (`YYYY-MM-DD_HH00.mp4`), with a Settings toggle for 12-hour legacy naming (`YYYY-MM-DD_!12AM.mp4`).

2. **Mozilla UniFFI Bridge (`rust/wyze-stitcher-core/src/wyze_stitcher.udl`)**
   - Generates type-safe Swift `async throws` methods (`scanDirectory`), push event callbacks (`StitchEventListener`), and a foreign async fallback trait (`AudioRemuxFallback`).

3. **Native macOS 14+ SwiftUI App (`macos/WyzeVidStitch`)**
   - **`NavigationSplitView`** layout with adaptive **Auto / Light / Dark** appearance picker in Settings (`Cmd+,`).
   - **24-Hour Footage Density Heatmap (`Heatmap24hView.swift`)** and **Minute-by-Minute 60-Tile Exclusion Inspector (`ClipInspectorSheet.swift`)**.
   - **Native `AVPlayerView` (`NativeVideoPlayerSheet.swift`)** opening local `.mp4` files directly with hardware acceleration.
   - **`AVFoundationRemuxer.swift`**: Implements UniFFI's `AudioRemuxFallback` using `AVAssetReader` / `AVAssetWriter` (lossless video passthrough + AAC audio transcode) for legacy Wyze cameras with zero FFmpeg dependency.
   - **Direct DMG Distribution (`WyzeVidStitch.entitlements`)**: Non-sandboxed (`com.apple.security.app-sandbox = false`) for seamless `/Volumes` SD card access.

## Building on macOS

### Prerequisites
- macOS 14+ with Xcode 15+ and Command Line Tools
- Rust toolchain via `rustup` (`rustup target add aarch64-apple-darwin x86_64-apple-darwin`)

### 1. Run Rust Core Unit Tests
```bash
cargo test --workspace
```

### 2. Build Universal2 XCFramework & Generate Swift Bindings
```bash
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh
```
This compiles `libwyze_stitcher_core.a` for both Apple Silicon and Intel, generates `wyze_stitcher.swift` from `src/wyze_stitcher.udl`, and packages `macos/WyzeVidStitch/Packages/WyzeStitcherKit/WyzeStitcherCoreFFI.xcframework`.

### 3. Open & Build in Xcode
1. Create or open `macos/WyzeVidStitch/WyzeVidStitch.xcodeproj` targeting **macOS 14.0**.
2. Add the local Swift Package `macos/WyzeVidStitch/Packages/WyzeStitcherKit` to the app target's Frameworks & Libraries.
3. Add all source files under `macos/WyzeVidStitch/WyzeVidStitch/` and assign `WyzeVidStitch.entitlements`.
4. Archive with a **Developer ID Application** certificate, package into a DMG, and notarize with `xcrun notarytool`.
