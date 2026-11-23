#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ICNS="${1:-AppIcon.icns}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

BASE_PNG="$WORK_DIR/icon_1024.png"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

echo "==> Rendering 1024x1024 macOS app icon with CoreGraphics..."
cat << 'SWIFT_EOF' > "$WORK_DIR/render_icon.swift"
import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments[1]
let size: Int = 1024
let width = CGFloat(size)
let height = CGFloat(size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// 1. macOS squircle container (824x824 centered inside 1024x1024 canvas for HIG margin)
let inset: CGFloat = 100
let cardRect = CGRect(x: inset, y: inset, width: width - inset * 2, height: height - inset * 2)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()

// Deep slate dark gradient background
let bgColors = [
    CGColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 1.0),
    CGColor(red: 0.09, green: 0.14, blue: 0.24, alpha: 1.0),
    CGColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1.0)
] as CFArray
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
        end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
        options: []
    )
}

// Subtle sky-blue top radial ambient glow
let glowColors = [
    CGColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 0.30),
    CGColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 0.0)
] as CFArray
if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: width * 0.5, y: height * 0.62),
        startRadius: 20,
        endCenter: CGPoint(x: width * 0.5, y: height * 0.62),
        endRadius: 360,
        options: []
    )
}

// 2. Stylized camera lens assembly (upper center)
let lensCenter = CGPoint(x: width * 0.5, y: height * 0.57)

// Outer anodized bezel ring
ctx.setFillColor(CGColor(red: 0.12, green: 0.17, blue: 0.27, alpha: 1.0))
ctx.fillEllipse(in: CGRect(x: lensCenter.x - 190, y: lensCenter.y - 190, width: 380, height: 380))
ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14))
ctx.setLineWidth(6)
ctx.strokeEllipse(in: CGRect(x: lensCenter.x - 187, y: lensCenter.y - 187, width: 374, height: 374))

// Inner recessed barrel
ctx.setFillColor(CGColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0))
ctx.fillEllipse(in: CGRect(x: lensCenter.x - 140, y: lensCenter.y - 140, width: 280, height: 280))

// Glowing cyan lens glass
let lensColors = [
    CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0),
    CGColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 1.0),
    CGColor(red: 0.02, green: 0.25, blue: 0.45, alpha: 1.0)
] as CFArray
ctx.saveGState()
let glassRect = CGRect(x: lensCenter.x - 102, y: lensCenter.y - 102, width: 204, height: 204)
ctx.addEllipse(in: glassRect)
ctx.clip()
if let lensGrad = CGGradient(colorsSpace: colorSpace, colors: lensColors, locations: [0.0, 0.55, 1.0]) {
    ctx.drawRadialGradient(
        lensGrad,
        startCenter: CGPoint(x: lensCenter.x - 28, y: lensCenter.y + 32),
        startRadius: 8,
        endCenter: lensCenter,
        endRadius: 115,
        options: []
    )
}
ctx.restoreGState()

// Crisp optical specular highlight
ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55))
ctx.fillEllipse(in: CGRect(x: lensCenter.x - 52, y: lensCenter.y + 22, width: 42, height: 28))

// 3. Stitched 24-hour footage timeline bar (lower area)
let barY: CGFloat = 215
let barHeight: CGFloat = 78
let barStartX: CGFloat = 195
let segCount = 6
let segGap: CGFloat = 16
let totalBarWidth = width - barStartX * 2
let segWidth = (totalBarWidth - CGFloat(segCount - 1) * segGap) / CGFloat(segCount)

let segPalette: [CGColor] = [
    CGColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0), // Emerald
    CGColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0), // Emerald
    CGColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 1.0), // Sky Blue (active)
    CGColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 1.0), // Sky Blue (active)
    CGColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0), // Amber (minor gap)
    CGColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0)  // Emerald
]

for i in 0..<segCount {
    let x = barStartX + CGFloat(i) * (segWidth + segGap)
    let rect = CGRect(x: x, y: barY, width: segWidth, height: barHeight)
    let path = CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.setFillColor(segPalette[i])
    ctx.addPath(path)
    ctx.fillPath()
}

ctx.restoreGState()

// Subtle outer specular border on squircle
ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16))
ctx.setLineWidth(6)
ctx.addPath(cardPath)
ctx.strokePath()

guard let cgImage = ctx.makeImage() else {
    fputs("Failed to make CGImage\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outPath))
SWIFT_EOF

swift "$WORK_DIR/render_icon.swift" "$BASE_PNG"

# Generate all required macOS iconset resolutions
sips -z 16 16     "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
sips -z 32 32     "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
sips -z 64 64     "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
sips -z 256 256   "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
sips -z 512 512   "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
cp "$BASE_PNG"                      "$ICONSET_DIR/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT_ICNS")"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "==> Generated macOS icon: $OUTPUT_ICNS"
