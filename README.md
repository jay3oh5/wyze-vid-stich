# WyzeVidStitch 📹

[![Build & Package macOS App](https://github.com/jay3oh5/wyze-vid-stich/actions/workflows/build.yml/badge.svg)](https://github.com/jay3oh5/wyze-vid-stich/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20(Sonoma)-blue.svg)](https://www.apple.com/macos/)
[![Architecture](https://img.shields.io/badge/arch-Universal%202%20(arm64%20%2B%20x86__64)-success.svg)]()
[![Offline-First](https://img.shields.io/badge/security-100%25%20offline--first-brightgreen.svg)](./SECURITY.md)

**WyzeVidStitch** is a high-performance native macOS desktop application and core library designed to seamlessly stitch 1-minute MicroSD card video recordings from Wyze surveillance cameras into continuous, high-definition videos.

Built with a portable, multi-threaded **Rust core** (`wyze-stitcher-core`), **Mozilla UniFFI** bindings, and a modern **SwiftUI** interface, WyzeVidStitch delivers instant lossless stitching with zero re-encoding overhead whenever possible, with automatic fallback audio remuxing for older camera models.

---

## ✨ Features

- ⚡️ **Lossless Container-Level Stitching:** Ultra-fast MP4 concatenation (`mp4-merge`) without re-encoding, preserving 100% of original camera video quality.
- 🗺️ **24-Hour Footage Heatmap:** Visual daily density timeline showing footage availability and missing minute gaps at a glance.
- 🔬 **Minute-by-Minute Exclusion Inspector:** Interactive 60-tile modal enabling granular inspection and exclusion of individual minute clips before merging.
- 🎬 **Native Hardware-Accelerated Video Player:** Built-in `AVPlayerView` sheet for instant previewing of individual camera clips and finished stitched videos.
- 🔊 **AVFoundation Remuxer (Zero FFmpeg Dependency):** Automatic native audio transcoding for older Wyze cameras recording in legacy codecs (`ulaw`/`alaw`/`pcm`) to standard AAC audio.
- 📁 **Flexible Folder Scanning:** Select an entire MicroSD card (`/Volumes/Wyze`), a specific camera root (`/record`), a day folder (`/20261123`), or directly an hour folder (`/14`).
- ⏱️ **Configurable Output Naming:** Choose between sortable 24-hour timestamps (`2026-11-23_1400.mp4`) or legacy 12-hour filenames (`2026-11-23_02PM.mp4`).
- 🍏 **Universal 2 Binary:** Native performance on both Apple Silicon (M1/M2/M3/M4) and Intel Macs.
- 🔒 **100% Offline-First:** Zero network requests, zero telemetry, and zero data collection. All video processing stays entirely on your computer.

---

## 📥 Download & Installation

### Option 1: Download from GitHub Releases (Recommended)

1. Head to the **[Releases](https://github.com/jay3oh5/wyze-vid-stich/releases)** page.
2. Download the latest `WyzeVidStitch-macOS.dmg`.
3. Open the `.dmg` file and drag **WyzeVidStitch** into your **Applications** folder.

> [!NOTE]
> Because release builds are ad-hoc signed for open-source distribution without paid Apple Developer certificates, macOS Gatekeeper may display a verification warning on first launch.
> 
> To open the app:
> - **Right-click** (or Control-click) `WyzeVidStitch.app` in Finder and select **Open**.
> - Or run the following terminal command once:
>   ```bash
>   xattr -dr com.apple.quarantine /Applications/WyzeVidStitch.app
>   ```

---

## 🚀 Getting Started

1. **Insert your Wyze MicroSD card** into your Mac (or copy its folders locally).
2. **Launch WyzeVidStitch** and click **Select Footage Folder**.
3. Choose the SD card root or any `/record/YYYYMMDD/HH` folder.
4. Browse the **24-Hour Density Heatmap** in the sidebar.
5. *(Optional)* Click **Inspect Clips** to exclude any unwanted minutes.
6. Click **Stitch Selected Hours** to queue the job.
7. Monitor progress in real time or view completed files directly from the Job History panel.

---

## 🛠️ Building from Source

### Prerequisites
- macOS 14.0+ with Xcode 15+ or Command Line Tools installed (`xcode-select --install`)
- Rust toolchain (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
- Apple Silicon & Intel targets:
  ```bash
  rustup target add aarch64-apple-darwin x86_64-apple-darwin
  ```

### 1. Run Core Rust Tests
```bash
cargo test --workspace
```

### 2. Build Universal2 XCFramework
```bash
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh
```

### 3. Package DMG & Universal App
```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh
```
The packaged `.dmg` and `.zip` will be generated in `dist/`.

---

## 🌐 Web Prototype (Legacy / Cross-Platform)

The repository also includes the original Node.js/React web prototype:

```bash
npm install
npm run dev
```
Open [http://localhost:5173](http://localhost:5173) in your web browser. (Requires local `ffmpeg` installed via Homebrew).

---

## 🛡️ Security & Privacy

For full details regarding offline guarantees, non-sandboxed filesystem permissions, and independent audit verification, please see [SECURITY.md](./SECURITY.md).

---

## 📄 License

MIT © [jay3oh5](https://github.com/jay3oh5)
