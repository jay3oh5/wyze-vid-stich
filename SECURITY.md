# Security & Verification Policy

The WyzeVidStitch project is committed to transparent, secure, and privacy-preserving desktop software. This policy outlines our security architecture, data handling guarantees, and independent verification procedures.

---

## 1. 100% Offline-First Architecture

WyzeVidStitch is designed as a **completely offline-first** utility.

- **Zero Telemetry or Analytics:** The application contains no tracking libraries, telemetry SDKs, or background analytics.
- **Zero Outbound Network Traffic:** All media scanning, gap detection, lossless MP4 concatenation, and audio remuxing occur entirely in-memory and on local disk storage. The app makes no outbound HTTP/HTTPS requests or socket connections.
- **Local Media Processing:** Camera video files remain strictly on your local filesystem or mounted MicroSD storage. No video data or metadata ever leaves your device.

---

## 2. Zero Data Collection Guarantee

- **No Account Required:** No user accounts, registration, API keys, or cloud logins are required or supported.
- **No Remote Credential Storage:** The application never requests, stores, or handles your Wyze account credentials, camera passwords, or personal identifiers.
- **Temporary File Hygiene:** Temporary staging files created during stitching (e.g. atomic `.tmp.mp4` staging) are written directly adjacent to output directories and automatically cleaned up upon job completion or cancellation.

---

## 3. Sandboxing & System Permissions Transparency

WyzeVidStitch runs as a native macOS application:

- **Filesystem Access:** The app utilizes user-granted folder selection via standard macOS file dialogs (`NSOpenPanel`). It accesses only directories explicitly selected by the user (such as MicroSD card volumes under `/Volumes` or local output folders).
- **Entitlements:** Sandboxing is disabled (`com.apple.security.app-sandbox = false`) in release builds specifically to permit direct, high-performance sequential read access to external MicroSD cards mounted under `/Volumes/` without requiring repetitive per-directory bookmark prompts.
- **Hardware Acceleration:** Native video playback and AVFoundation remuxing leverage local macOS hardware codecs (`VideoToolbox` / `AudioToolbox`) with zero external binary dependencies.

---

## 4. Independent Audit & Verification Guide

We encourage users and security researchers to independently inspect and verify all release artifacts and network activity.

### A. Verify Zero Network Activity

Run the following command while WyzeVidStitch is actively scanning or stitching video clips:

```bash
# Check for active listening ports or established connections by the app
lsof -i -a -p $(pgrep WyzeVidStitch)
```
*Expected Result:* No output or open network sockets.

You may also monitor network traffic in real-time with macOS `nettop`:
```bash
nettop -p WyzeVidStitch
```

### B. Verify Universal Binary Architectures

Inspect the native executable within the application bundle:

```bash
file /Applications/WyzeVidStitch.app/Contents/MacOS/WyzeVidStitch
```
*Expected Result:*
```
Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]
```

### C. Verify Codesigning & Entitlements

Inspect the code signature and entitlements applied to the bundle:

```bash
codesign -d --entitlements :- /Applications/WyzeVidStitch.app
```

### D. Reproducible Local Compilation

All source code for the Rust core and Swift UI is open and auditable:
```bash
# 1. Run core Rust unit tests
cargo test --workspace

# 2. Build local Universal XCFramework
./scripts/build-xcframework.sh

# 3. Package local DMG
./scripts/package-app.sh
```

---

## 5. Reporting Security Vulnerabilities

If you discover a potential vulnerability, bug, or security concern, please submit an issue on GitHub:
- **GitHub Issues:** [https://github.com/jay3oh5/wyze-vid-stich/issues](https://github.com/jay3oh5/wyze-vid-stich/issues)

All reports are reviewed promptly and addressed in public releases.
