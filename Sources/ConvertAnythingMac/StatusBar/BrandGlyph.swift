import AppKit

/// The brand mark shared by the app icon and the status item: two arrows that
/// swap places. Coordinates live on a 24 x 24 grid, so `scripts/make-appicon.sh`
/// and the menu bar item render the same shape at different sizes.
public enum BrandGlyph {
  private static let grid: CGFloat = 24
  private static let strokeWidth: CGFloat = 1.6

  /// Stroked outline scaled to fill `rect`, in AppKit's bottom-up coordinates.
  public static func path(in rect: NSRect) -> NSBezierPath {
    let scale = min(rect.width, rect.height) / grid
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
      NSPoint(x: rect.minX + x * scale, y: rect.minY + (grid - y) * scale)
    }

    let path = NSBezierPath()
    path.move(to: point(3.6, 9))
    path.line(to: point(17.4, 9))
    path.move(to: point(14.8, 6.3))
    path.line(to: point(17.5, 9))
    path.line(to: point(14.8, 11.7))
    path.move(to: point(20.4, 15))
    path.line(to: point(6.6, 15))
    path.move(to: point(9.2, 12.3))
    path.line(to: point(6.5, 15))
    path.line(to: point(9.2, 17.7))
    path.lineWidth = strokeWidth * scale
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
  }

  /// Template image for the menu bar item, tinted by the system.
  public static func statusItemImage(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      NSColor.black.setStroke()
      BrandGlyph.path(in: rect).stroke()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Convert Anything"
    return image
  }
}
