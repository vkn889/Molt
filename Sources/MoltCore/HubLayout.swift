import Foundation

/// One widget placed on the Hub. `span` is 1 (small) or 2 (medium); `items` holds per-widget
/// configuration such as the actions shown by a Shortcuts widget.
public struct HubWidget: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var kind: String
  public var span: Int
  public var items: [String]
  public init(id: UUID = UUID(), kind: String, span: Int = 1, items: [String] = []) {
    self.id = id; self.kind = kind; self.span = span; self.items = items
  }
}

/// The Hub is four units wide. Every edit returns a new valid layout, or nil when it would not fit.
public enum HubLayout {
  public static let capacity = 4
  public static let defaults = ["focus", "tasks", "weather", "topApps"].map { HubWidget(kind: $0) }

  public static func used(_ layout: [HubWidget]) -> Int { layout.reduce(0) { $0 + $1.span } }

  /// Drops unknown kinds, clamps spans and trims anything past the capacity.
  public static func sanitize(_ layout: [HubWidget], known: Set<String>) -> [HubWidget] {
    var result: [HubWidget] = []
    for var widget in layout where known.contains(widget.kind) {
      widget.span = min(2, max(1, widget.span))
      widget.items = Array(widget.items.prefix(8))
      guard used(result) + widget.span <= capacity else { continue }
      result.append(widget)
    }
    return result
  }
  public static func add(_ widget: HubWidget, at index: Int? = nil, to layout: [HubWidget]) -> [HubWidget]? {
    guard (1...2).contains(widget.span), used(layout) + widget.span <= capacity else { return nil }
    var result = layout
    result.insert(widget, at: min(max(0, index ?? layout.count), layout.count))
    return result
  }
  public static func resize(_ id: UUID, to span: Int, in layout: [HubWidget]) -> [HubWidget]? {
    guard (1...2).contains(span), let index = layout.firstIndex(where: { $0.id == id }) else { return nil }
    var result = layout
    result[index].span = span
    return used(result) <= capacity ? result : nil
  }
  /// Moves a widget in front of `target`, or to the end when `target` is nil.
  public static func move(_ id: UUID, before target: UUID?, in layout: [HubWidget]) -> [HubWidget] {
    guard id != target, let index = layout.firstIndex(where: { $0.id == id }) else { return layout }
    var result = layout
    let widget = result.remove(at: index)
    let destination = target.flatMap { t in result.firstIndex { $0.id == t } } ?? result.count
    result.insert(widget, at: destination)
    return result
  }
  public static func remove(_ id: UUID, from layout: [HubWidget]) -> [HubWidget] {
    layout.filter { $0.id != id }
  }
}
