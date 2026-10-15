import Foundation

/// Something that can show beside the closed notch. When several are going at once, the one
/// highest in your order shows first, and a swipe on the notch moves to the next.
public enum LiveKind: String, CaseIterable, Codable, Sendable {
  case agents, recording, focus, music, battery
  public var title: String {
    switch self {
    case .agents: return "Agent requests"
    case .recording: return "Screen recording"
    case .focus: return "Focus session"
    case .music: return "Music"
    case .battery: return "Low battery"
    }
  }
}

/// How the notch is arranged: which tabs show and in what order, and what the closed notch
/// shows first.
public enum NotchLayout {
  /// The tabs beside the notch, by route. Home is always there.
  public static let tabs = ["Notch", "Hub", "Play", "Molting"]

  /// The visible tabs in your order. Unknown routes are dropped, and tabs missing from a saved
  /// order (added in a later version) go at the end.
  public static func tabs(order: [String], hidden: Set<String>) -> [String] {
    var seen = Set<String>()
    let known = order.filter { tabs.contains($0) && seen.insert($0).inserted } + tabs.filter { !order.contains($0) }
    return known.filter { $0 == "Notch" || !hidden.contains($0) }
  }
  /// Every tab in your order, shown or not, for arranging them.
  public static func allTabs(order: [String]) -> [String] { tabs(order: order, hidden: []) }

  /// Your order for the closed notch, with anything missing added in the default order.
  public static func priority(_ saved: [String]) -> [LiveKind] {
    var seen = Set<LiveKind>()
    let known = saved.compactMap(LiveKind.init(rawValue:)).filter { seen.insert($0).inserted }
    return known + LiveKind.allCases.filter { !known.contains($0) }
  }
  /// What's going on right now, in your order.
  public static func live(_ active: Set<LiveKind>, priority: [LiveKind]) -> [LiveKind] {
    priority.filter(active.contains)
  }
  /// Moves `item` in front of `target`, or to the end when `target` is nil.
  public static func move<T: Equatable>(_ item: T, before target: T?, in list: [T]) -> [T] {
    guard item != target, let index = list.firstIndex(of: item) else { return list }
    var result = list
    result.remove(at: index)
    let destination = target.flatMap { t in result.firstIndex(of: t) } ?? result.count
    result.insert(item, at: destination)
    return result
  }
}

/// One place the notch can take you when you start typing: a page, a widget, an action or a
/// setting.
public struct JumpItem: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var subtitle: String
  public var keywords: [String]
  /// A keyboard shortcut that does the same thing, shown while Option is held.
  public var shortcut: String?
  public init(id: String, title: String, subtitle: String, keywords: [String] = [], shortcut: String? = nil) {
    self.id = id; self.title = title; self.subtitle = subtitle; self.keywords = keywords; self.shortcut = shortcut
  }
}

public enum JumpSearch {
  /// How well `item` matches `query`, or nil when it doesn't. Higher is better: the start of the
  /// title, then the start of a word, then anywhere in the title, then a keyword, then letters
  /// in order.
  public static func score(_ query: String, _ item: JumpItem) -> Int? {
    let q = normalized(query)
    guard !q.isEmpty else { return nil }
    let title = normalized(item.title)
    let words = title.split(separator: " ").map(String.init)
    // Words in the query after the first can be anything (such as the minutes in "focus 25").
    let head = q.split(separator: " ").first.map(String.init) ?? q
    if title.hasPrefix(q) { return 100 }
    if words.contains(where: { $0.hasPrefix(q) }) { return 80 }
    if title.contains(q) { return 60 }
    if title.hasPrefix(head) { return 58 }
    if words.contains(where: { $0.hasPrefix(head) }) { return 55 }
    if item.keywords.contains(where: { normalized($0).hasPrefix(head) }) { return 50 }
    // Letters in order count for more when the first one starts the title.
    if subsequence(head, of: title) { return title.first == head.first ? 30 : 20 }
    return nil
  }
  /// The best matches, best first; equal matches keep their original order.
  public static func rank(_ query: String, _ items: [JumpItem], limit: Int = 5) -> [JumpItem] {
    items.enumerated().compactMap { index, item in score(query, item).map { (item, $0, index) } }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
      .prefix(limit).map(\.0)
  }
  /// Minutes typed into the query, such as "focus 50" or "timer 10m". Clamped to 1...180.
  public static func minutes(in query: String) -> Int? {
    let digits = query.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    return digits.map { min(180, max(1, $0)) }
  }
  /// Where `query` matches in `title`, for highlighting: the first case-insensitive occurrence.
  public static func highlight(_ query: String, in title: String) -> Range<String.Index>? {
    let q = query.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
    guard !q.isEmpty else { return nil }
    return title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive])
  }
  static func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .trimmingCharacters(in: .whitespaces)
  }
  static func subsequence(_ needle: String, of hay: String) -> Bool {
    var rest = Substring(hay)
    for character in needle where character != " " {
      guard let index = rest.firstIndex(of: character) else { return false }
      rest = rest[rest.index(after: index)...]
    }
    return true
  }
}

/// The arithmetic behind focus sessions.
public enum FocusMath {
  /// The ruler runs from 0 to 60 minutes; a session is at least 5.
  public static let scale = 60
  public static let minimum = 5
  public static let step = 5
  /// Minutes for a point along the ruler (0 to 1), snapped to five-minute steps.
  public static func minutes(at fraction: Double) -> Int {
    let clamped = min(1, max(0, fraction.isFinite ? fraction : 0))
    let raw = clamped * Double(scale)
    return min(scale, max(minimum, Int((raw / Double(step)).rounded()) * step))
  }
  /// Where `minutes` sits along the ruler.
  public static func fraction(for minutes: Int) -> Double {
    Double(min(scale, max(0, minutes))) / Double(scale)
  }
  /// The energy Molt gets for a session of this many seconds; matches the pet's reward.
  public static func reward(seconds: Double) -> Int { min(20, max(0, Int(seconds / 300))) }
  /// Sessions finished today, and the minutes they add up to.
  public static func today(_ sessions: [FocusSession], now: Date, calendar: Calendar = .current) -> (count: Int, minutes: Int) {
    let done = sessions.filter { $0.finished.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
    return (done.count, Int(done.reduce(0) { $0 + $1.elapsed } / 60))
  }
}

/// Files and links you dropped on Molt to keep for later.
public struct TrayItem: Codable, Identifiable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case file, link }
  public var id: UUID
  public var kind: Kind
  /// A file path, or a link.
  public var value: String
  public var added: Date
  public init(id: UUID = UUID(), kind: Kind, value: String, added: Date = Date()) {
    self.id = id; self.kind = kind; self.value = value; self.added = added
  }
  public var name: String {
    switch kind {
    case .file: return URL(fileURLWithPath: value).lastPathComponent
    case .link: return URL(string: value).map { ($0.host ?? "") + $0.path } ?? value
    }
  }
}

public enum Tray {
  public static let limit = 12
  /// Adds new items in front. Something already in the tray moves to the front instead of
  /// appearing twice, and the oldest fall off past the limit.
  public static func adding(_ items: [TrayItem], to tray: [TrayItem]) -> [TrayItem] {
    var result = tray
    for item in items.reversed() {
      result.removeAll { $0.kind == item.kind && $0.value == item.value }
      result.insert(item, at: 0)
    }
    return Array(result.prefix(limit))
  }
}
