import CoreGraphics
import Foundation

public enum IslandGeometry {
  public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, expanded: Bool)
    -> CGRect
  {
    let available = screen.intersection(visible)
    let width = min(expanded ? 760 : 180, max(1, available.width - 24))
    let height = min(expanded ? 780 : 44, max(1, available.height - 16))
    let top = min(available.maxY, screen.maxY - max(0, safeTop))
    return CGRect(
      x: min(max(screen.midX - width / 2, available.minX + 12), available.maxX - width - 12),
      y: max(available.minY, top - height), width: width, height: height)
  }
}
