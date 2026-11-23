# Native macOS Migration Guide (Rust Core + UniFFI + SwiftUI)

This repository contains both the original Node.js/React web prototype and the native **macOS 14+ (Sonoma)** implementation powered by a portable Rust core (`wyze-stitcher-core`) and Mozilla UniFFI Swift bindings.

## Architecture Overview

1. **Portable Rust Core (`rust/wyze-stitcher-core`)**
   - **Adaptive Rayon Parallel Scanner (`src/scanner.rs`)**: Multi-threaded scanner supporting direct hour folders, day folders, SD card roots (`record/`), standard `/record/YYYYMMDD/HH/MM.mp4` hierarchies, and multi-folder aggregation. Captures exact `source_dir_path`, per-hour byte sizes, missing minute gaps (`00`–`59`), density buckets, and zero-decode MP4 `stsd` non-AAC audio detection.
   - **Lossless MP4 Merger & Strict Validator (`src/merger.rs`)**: Strictly pre-validates every input clip (fail-fast with exact filename diagnostics on 0-byte or corrupt MP4 headers), then runs `mp4_merge::join_files` with throttled progress callbacks and atomic `.tmp.mp4` staging.
   - **Sequential Background Queue (`src/queue.rs`)**: Tokio single-worker queue supporting both **Per-Hour** and **Full-Day** merged outputs, one-click `retry_job`, `cancel_job` / `cancel_all_jobs` (including immediate cooperative abort of active AVFoundation remuxes), atomic verification, and optional post-compile source cleanup.
   - **Configurable Output Naming (`src/naming.rs`)**: Defaults to sortable 24-hour (`YYYY-MM-DD_HH00.mp4`), with a Settings option for 12-hour legacy naming (`YYYY-MM-DD_!12AM.mp4`) and `YYYY-MM-DD_FullDay.mp4` for full-day merges.

2. **Mozilla UniFFI Bridge (`rust/wyze-stitcher-core/src/wyze_stitcher.udl`)**
   - Generates type-safe Swift `async throws` methods (`scanDirectory`), push event callbacks (`StitchEventListener`), and the cooperative `AudioRemuxFallback` foreign trait (`remuxClipsToAac` + `cancelRemux`).

3. **Native macOS 14+ SwiftUI App (`macos/WyzeVidStitch`)**
   - **`NavigationSplitView`** layout with adaptive **Auto / Light / Dark** appearance picker in Settings (`Cmd+,`), **folder drag-and-drop**, and automatic **Wyze SD card mount detection** (`NSWorkspace`).
   - **24-Hour Footage Density Heatmap (`Heatmap24hView.swift`)**, per-hour size badges, and **Stitch Full Day / Multi-Hour Merge** controls.
   - **Upgraded 60-Minute Clip Exclusion Inspector (`ClipInspectorSheet.swift`)**: Inline 1-minute `AVPlayerView` quick preview (with 0-byte warnings) and **Shift-click** contiguous range selection.
   - **Power Queue & Native Playback (`JobQueueView.swift`, `NativeVideoPlayerSheet.swift`)**: Aggregate batch progress bar, Dock tile progress indicator, pre-flight free disk space guard (500 MB safety buffer), **Cancel All**, **Retry Failed** / per-job **Retry**, automatic post-cleanup rescan, and native `AVPlayerView` playback.
   - **Native Packaging (`scripts/generate-icon.sh`, `scripts/package-app.sh`)**: Generates a Retina `AppIcon.icns` via CoreGraphics + `iconutil` and packages a drag-to-`/Applications` Universal2 DMG.

## Building on macOS

### Prerequisites
- macOS 14+ with Xcode 15+ (or Command Line Tools)
- Rust toolchain via `rustup` (`rustup target add aarch64-apple-darwin x86_64-apple-darwin`)

### 1. Run Rust Core Unit Tests
```bash
cargo test --workspace
```

### 2. Build Universal2 XCFramework & Regenerate Swift Bindings
```bash
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh
```
> Always rerun `./scripts/build-xcframework.sh` whenever `wyze_stitcher.udl` changes so `wyze_stitcher.swift` and `WyzeStitcherCoreFFI.xcframework` stay in sync (also handled automatically by `.github/workflows/build.yml`).

### 3. Package `.app`, `.zip`, and Drag-to-Applications `.dmg`
```bash
chmod +x scripts/package-app.sh scripts/generate-icon.sh
./scripts/package-app.sh
```
