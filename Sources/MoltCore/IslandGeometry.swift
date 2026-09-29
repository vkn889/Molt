import CoreGraphics
import Foundation

public enum IslandGeometry {
  public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, expanded: Bool)
    -> CGRect
  {
    let width = min(expanded ? 740 : 180, max(1, screen.width - 24))
    let height = min(expanded ? 260 + max(0, safeTop) : max(1, safeTop), max(1, visible.height))
    // The black cap touches the top edge. Interactive content sits below safeTop.
    return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
  }
}
