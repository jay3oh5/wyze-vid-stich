# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-23

### Added
- **Native macOS 14+ SwiftUI Application:** Modern desktop interface with `NavigationSplitView`, adaptive appearance (Auto / Light / Dark), and dock progress indicator.
- **High-Performance Rust Core (`wyze-stitcher-core`):** Lossless MP4 concatenation with zero quality loss, fast zero-decode audio codec inspection, Rayon-powered multi-threaded directory scanner, and Tokio background worker queue.
- **Mozilla UniFFI Swift Bridge:** Auto-generated type-safe Swift bindings (`async throws`) with event callbacks and audio remuxer trait.
- **Interactive 24-Hour Footage Density Heatmap:** Visual inspection of daily camera footage availability and missing clip gaps (`00`–`59`).
- **Minute-by-Minute Exclusion Inspector:** 60-tile interactive modal allowing granular exclusion of individual minute clips prior to stitching.
- **Hardware-Accelerated Native Video Player:** Built-in macOS `AVPlayerView` preview for local camera clips and completed stitched footage.
- **AVFoundation Audio Remuxing Fallback:** Seamless transcoding of non-standard Wyze audio codecs (`ulaw`/`alaw`/`pcm`) to standard AAC audio with zero FFmpeg dependency.
- **Flexible Hierarchy Scanner:** Supports direct hour directories (`/14`), day directories (`/20261123`), camera roots (`/record`), or entire SD card roots (`/Volumes/...`).
- **Universal 2 macOS Binary Build:** Dual-architecture compilation supporting both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs.
- **Automated Cloud CI/CD Release Pipeline:** GitHub Actions workflow building ad-hoc signed DMG and ZIP releases on tag push.
- **Security & Privacy Policy (`SECURITY.md`):** Complete 100% offline-first verification guide and zero data collection guarantee.

### Changed
- Migrated primary desktop workflow to native macOS application with standalone Command Line Tools packaging.
