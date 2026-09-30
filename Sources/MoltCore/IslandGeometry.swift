import CoreGraphics
import Foundation

public enum IslandGeometry {
  public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, expanded: Bool)
    -> CGRect
  {
    frame(
      screen: screen, visible: visible,
      size: CGSize(width: expanded ? 740 : 180, height: expanded ? 380 + max(0, safeTop) : max(1, safeTop)))
  }
  /// Anchors a panel of `size` to the top center of `screen`, touching the top edge
  /// so it reads as an extension of the hardware notch.
  public static func frame(screen: CGRect, visible: CGRect, size: CGSize) -> CGRect {
    let width = min(max(1, size.width), max(1, screen.width - 24))
    let height = min(max(1, size.height), max(1, visible.height))
    return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
  }
}
