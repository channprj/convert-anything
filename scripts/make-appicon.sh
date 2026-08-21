#!/bin/zsh
set -euo pipefail

# Renders App/AppIcon.icns from the same glyph the menu bar item draws, so the
# two can never drift apart. Run after changing BrandGlyph.

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
glyph_source="$repo_root/Sources/ConvertAnythingMac/StatusBar/BrandGlyph.swift"
output="$repo_root/App/AppIcon.icns"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/AppIcon.iconset"

cat > "$work/main.swift" <<'SWIFT'
import AppKit
import SwiftUI

let iconset = CommandLine.arguments[1]

/// Apple's icon silhouette: straight sides with continuous corners, not the
/// circular corners a plain rounded rectangle draws.
func squircle(in rect: CGRect) -> CGPath {
  RoundedRectangle(cornerRadius: rect.width * 0.2237, style: .continuous)
    .path(in: rect).cgPath
}

func render(_ pixels: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: pixels, height: pixels)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current?.shouldAntialias = true

  let canvas = CGFloat(pixels)
  let inset = canvas * 100 / 1024
  let art = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
  let context = NSGraphicsContext.current!.cgContext
  context.addPath(squircle(in: art))
  context.setFillColor(NSColor.black.cgColor)
  context.fillPath()

  // Small sizes need a larger, heavier glyph to survive.
  let ratio: CGFloat = pixels <= 32 ? 0.88 : (pixels <= 64 ? 0.70 : 0.56)
  let weight: CGFloat = pixels <= 32 ? 1.7 : (pixels <= 64 ? 1.3 : 1.0)
  let side = art.width * ratio
  let glyph = BrandGlyph.path(
    in: CGRect(x: art.midX - side / 2, y: art.midY - side / 2, width: side, height: side))
  glyph.lineWidth *= weight
  NSColor.white.setStroke()
  glyph.stroke()

  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in variants {
  try render(pixels).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
SWIFT

swiftc -O "$work/main.swift" "$glyph_source" -o "$work/render"
"$work/render" "$work/AppIcon.iconset"
iconutil --convert icns --output "$output" "$work/AppIcon.iconset"

print "Wrote $output"
