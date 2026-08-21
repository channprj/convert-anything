import AppKit
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let brandGlyphTests: [TestCase] = [
  TestCase("status item glyph is a template image that draws strokes") {
    try await statusItemGlyphIsTemplateAndDraws()
  }
]

/// The menu bar only tints template images to match the light and dark
/// appearances, and a glyph whose path misses the image bounds renders as an
/// empty square. Both regressions still compile, so render the image and look
/// at the pixels.
@MainActor
private func statusItemGlyphIsTemplateAndDraws() throws {
  let image = BrandGlyph.statusItemImage()
  try expectTrue(image.isTemplate, "Status item image must be a template image")
  try expectEqual(image.size, NSSize(width: 18, height: 18), "Status item image size")

  let pixels = 36
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else {
    throw TestFailure(description: "Could not create a bitmap to render the glyph into")
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
  NSGraphicsContext.restoreGraphicsState()

  var drawnPixels = 0
  for y in 0..<pixels {
    for x in 0..<pixels where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
      drawnPixels += 1
    }
  }
  try expectTrue(drawnPixels > 0, "Rendered glyph left every pixel transparent")
}
