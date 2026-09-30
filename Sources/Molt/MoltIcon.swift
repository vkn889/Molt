import AppKit
import MoltCore
import SwiftUI

/// Molt's logo: the idle pixel creature on a black macOS icon tile. Drawn from the same grid as
/// `CreatureView`, so the app icon and menu bar icon always match the character in the notch.
enum MoltIcon {
  private static var pixels: [CreatureView.Pixel] { CreatureView.pixels(pose: .idle, tick: 1) }

  /// A crisp PNG of the app icon at `size` pixels square, following Apple's icon grid.
  static func png(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .none
    NSGraphicsContext.current?.shouldAntialias = true
    let s = CGFloat(size)
    // The tile occupies 824 of 1024 units with a continuous-looking corner.
    let tile = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = NSBezierPath(roundedRect: tile, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 10 / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -s * 6 / 1024)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.02, alpha: 1)])?.draw(in: shape, angle: -90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    shape.lineWidth = max(1, s / 512)
    shape.stroke()
    // The creature spans 14 by 11 cells, centered slightly high like the notch pose.
    let cell = (tile.width * 0.62 / 14).rounded(.down)
    let originX = (tile.midX - cell * 7).rounded()
    let originY = (tile.midY + cell * 5.8).rounded()
    NSGraphicsContext.current?.shouldAntialias = false
    for pixel in pixels {
      color(pixel.kind).setFill()
      NSRect(x: originX + CGFloat(pixel.x) * cell, y: originY - CGFloat(pixel.y + 1) * cell, width: cell, height: cell).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
  }

  /// A template image for the menu bar: Molt's silhouette with its eyes cut out.
  static func menuBarImage() -> NSImage {
    let cell: CGFloat = 1.5
    let image = NSImage(size: NSSize(width: 14 * cell, height: 11 * cell), flipped: true) { _ in
      NSColor.black.setFill()
      for pixel in pixels where pixel.kind != .eye {
        NSRect(x: CGFloat(pixel.x) * cell, y: CGFloat(pixel.y) * cell, width: cell, height: cell).fill()
      }
      NSGraphicsContext.current?.compositingOperation = .clear
      for pixel in pixels where pixel.kind == .eye {
        NSRect(x: CGFloat(pixel.x) * cell, y: CGFloat(pixel.y) * cell, width: cell, height: cell).fill()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Molt"
    return image
  }

  private static func color(_ kind: CreatureView.Kind) -> NSColor {
    switch kind {
    case .body: return NSColor(MoltTheme.body("sage"))
    case .eye, .mouth: return NSColor(white: 0.07, alpha: 1)
    case .leaf: return NSColor(red: 0.49, green: 0.88, blue: 0.42, alpha: 1)
    case .stem: return NSColor(red: 0.2, green: 0.55, blue: 0.3, alpha: 1)
    }
  }

  /// Writes a complete `.iconset` folder for `iconutil`.
  static func writeIconset(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
      for scale in [1, 2] {
        guard let data = png(size: base * scale) else { throw MoltError.invalid("Could not draw the icon.") }
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
      }
    }
  }
}
