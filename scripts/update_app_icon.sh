#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/update_app_icon.sh <image-path> [corner-radius-ratio]

Arguments:
  image-path             Source image. Any size/aspect ratio supported.
  corner-radius-ratio    Optional. Default: 0.21. Used for rounded desktop/web
                         PNG sources only. iOS/Android sources stay square.

Examples:
  scripts/update_app_icon.sh /Users/laevatain/Desktop/aslan_icon.png
  scripts/update_app_icon.sh /Users/laevatain/Desktop/EXPO_ZUTOMAYO_KV.jpg 0.23
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 64
fi

SOURCE_IMAGE="$1"
RADIUS_RATIO="${2:-0.21}"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "Source image not found: $SOURCE_IMAGE" >&2
  exit 66
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required for image processing on macOS." >&2
  exit 69
fi

if ! command -v dart >/dev/null 2>&1; then
  echo "dart is required to run flutter icon generators." >&2
  exit 69
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SWIFT_SCRIPT="$WORK_DIR/make_app_icon_sources.swift"

cat > "$SWIFT_SCRIPT" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

struct IconJob {
    let outputPath: String
    let size: Int
    let cornerRadius: CGFloat
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if CommandLine.arguments.count < 4 {
    fail("Usage: make_app_icon_sources.swift <input> <radiusRatio> <job>...")
}

let inputPath = CommandLine.arguments[1]
guard let radiusRatio = Double(CommandLine.arguments[2]) else {
    fail("Invalid corner radius ratio: \(CommandLine.arguments[2])")
}

let jobSpecs = CommandLine.arguments.dropFirst(3)
let jobs = jobSpecs.map { spec -> IconJob in
    let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3, let size = Int(parts[1]) else {
        fail("Invalid job spec: \(spec)")
    }
    let rounded = parts[2] == "rounded"
    return IconJob(
        outputPath: parts[0],
        size: size,
        cornerRadius: rounded ? CGFloat(Double(size) * radiusRatio) : 0
    )
}

guard let sourceImage = NSImage(contentsOfFile: inputPath),
      let sourceCG = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("Cannot load source image: \(inputPath)")
}

let cropSide = min(sourceCG.width, sourceCG.height)
let cropX = (sourceCG.width - cropSide) / 2
let cropY = (sourceCG.height - cropSide) / 2

guard let croppedCG = sourceCG.cropping(to: CGRect(
    x: cropX,
    y: cropY,
    width: cropSide,
    height: cropSide
)) else {
    fail("Cannot crop source image")
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

for job in jobs {
    guard let context = CGContext(
        data: nil,
        width: job.size,
        height: job.size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("Cannot create CGContext for \(job.outputPath)")
    }

    context.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: job.size, height: job.size)

    if job.cornerRadius > 0 {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: job.cornerRadius,
            cornerHeight: job.cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.clip()
    }

    context.draw(croppedCG, in: rect)

    guard let resultCG = context.makeImage() else {
        fail("Cannot render \(job.outputPath)")
    }

    let outputURL = URL(fileURLWithPath: job.outputPath)
    try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let rep = NSBitmapImageRep(cgImage: resultCG)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fail("Cannot encode PNG for \(job.outputPath)")
    }

    do {
        try pngData.write(to: outputURL)
    } catch {
        fail("Cannot write \(job.outputPath): \(error)")
    }
}
SWIFT

echo "Generating app icon source PNGs from: $SOURCE_IMAGE"
swift "$SWIFT_SCRIPT" "$SOURCE_IMAGE" "$RADIUS_RATIO" \
  "assets/images/logo/aslan_icon_source.png:2048:square" \
  "assets/images/logo/logo_android.png:2048:square" \
  "assets/images/logo/logo_ios.png:2048:square" \
  "assets/images/logo/logo_rounded.png:2048:rounded" \
  "assets/images/logo/logo_linux.png:1024:rounded" \
  "web/favicon.png:64:rounded" \
  "web/icons/Icon-192.png:384:rounded" \
  "web/icons/Icon-512.png:1024:rounded" \
  "web/icons/Icon-maskable-192.png:384:rounded" \
  "web/icons/Icon-maskable-512.png:1024:rounded"

echo "Running flutter_launcher_icons..."
dart run flutter_launcher_icons

echo "Running flutter_native_splash..."
dart run flutter_native_splash:create

echo "Syncing Windows tray ico assets..."
cp windows/runner/resources/app_icon.ico assets/images/logo/logo_lanczos.ico
cp windows/runner/resources/app_icon.ico assets/images/logo/logo_windows.ico

echo "Icon generation finished."
echo
echo "Changed files:"
git status --short \
  assets/images/logo \
  web/favicon.png \
  web/icons \
  android/app/src/main/res \
  ios/Runner/Assets.xcassets \
  macos/Runner/Assets.xcassets \
  windows/runner/resources/app_icon.ico
