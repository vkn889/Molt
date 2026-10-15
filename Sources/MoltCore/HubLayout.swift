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

/// The Hub is three units wide and up to three rows tall (you choose how many). Widgets fill a
/// row from the left; one that doesn't fit in what's left of a row starts the next. Every edit
/// returns a new valid layout, or nil when it would not fit.
public enum HubLayout {
  /// Units in one row: a regular widget is one, a wide one two.
  public static let capacity = 3
  /// The most rows anyone can choose; `rows` in each call is your own limit.
  public static let maxRows = 3
  public static let defaultRows = 2
  public static let defaults = ["focus", "upNext", "molt", "tray", "nowPlaying", "shortcuts"].map {
    HubWidget(kind: $0, items: $0 == "shortcuts" ? ["action:record", "action:lens", "action:dark", "action:focus"] : [])
  }

  public static func used(_ layout: [HubWidget]) -> Int { layout.reduce(0) { $0 + $1.span } }

  /// The widgets of each row, in order.
  public static func rows(_ layout: [HubWidget]) -> [[HubWidget]] {
    var rows: [[HubWidget]] = []
    var current: [HubWidget] = []
    for widget in layout {
      if !current.isEmpty && used(current) + widget.span > capacity {
        rows.append(current)
        current = []
      }
      current.append(widget)
    }
    if !current.isEmpty { rows.append(current) }
    return rows
  }
  public static func fits(_ layout: [HubWidget], rows limit: Int = defaultRows) -> Bool {
    layout.allSatisfy { (1...2).contains($0.span) } && rows(layout).count <= min(maxRows, max(1, limit))
  }
  /// The widest widget that can still go at the end.
  public static func room(_ layout: [HubWidget], rows limit: Int = defaultRows) -> Int {
    let rows = rows(layout)
    let left = capacity - (rows.last.map(used) ?? capacity)
    return rows.count < min(maxRows, max(1, limit)) ? 2 : min(2, left)
  }

  /// Drops unknown kinds, clamps spans and trims anything that no longer fits.
  public static func sanitize(_ layout: [HubWidget], known: Set<String>, rows limit: Int = defaultRows) -> [HubWidget] {
    var result: [HubWidget] = []
    for var widget in layout where known.contains(widget.kind) {
      widget.span = min(2, max(1, widget.span))
      widget.items = Array(widget.items.prefix(8))
      guard fits(result + [widget], rows: limit) else { continue }
      result.append(widget)
    }
    return result
  }
  public static func add(_ widget: HubWidget, at index: Int? = nil, to layout: [HubWidget], rows limit: Int = defaultRows) -> [HubWidget]? {
    var result = layout
    result.insert(widget, at: min(max(0, index ?? layout.count), layout.count))
    return fits(result, rows: limit) ? result : nil
  }
  public static func resize(_ id: UUID, to span: Int, in layout: [HubWidget], rows limit: Int = defaultRows) -> [HubWidget]? {
    guard (1...2).contains(span), let index = layout.firstIndex(where: { $0.id == id }) else { return nil }
    var result = layout
    result[index].span = span
    return fits(result, rows: limit) ? result : nil
  }
  /// Moves a widget in front of `target`, or to the end when `target` is nil. A move that
  /// wouldn't fit leaves the layout as it was.
  public static func move(_ id: UUID, before target: UUID?, in layout: [HubWidget], rows limit: Int = defaultRows) -> [HubWidget] {
    guard id != target, let index = layout.firstIndex(where: { $0.id == id }) else { return layout }
    var result = layout
    let widget = result.remove(at: index)
    let destination = target.flatMap { t in result.firstIndex { $0.id == t } } ?? result.count
    result.insert(widget, at: destination)
    return fits(result, rows: limit) ? result : layout
  }
  public static func remove(_ id: UUID, from layout: [HubWidget]) -> [HubWidget] {
    layout.filter { $0.id != id }
  }
}
