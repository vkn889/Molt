import Foundation

/// One rolling limit window of a subscription plan, such as the 5-hour or weekly window.
public struct LimitWindow: Codable, Equatable, Sendable {
  public var used: Double
  public var minutes: Int
  public var resets: Date
  public init(used: Double, minutes: Int, resets: Date) {
    self.used = min(100, max(0, used)); self.minutes = minutes; self.resets = resets
  }
  public var start: Date { resets.addingTimeInterval(-Double(minutes) * 60) }

  /// When the window will reach 100% at the pace used so far, or nil if it resets first.
  /// Needs at least five minutes of the window behind it to say anything.
  public func forecast(now: Date) -> Date? {
    guard now < resets else { return nil }
    if used >= 100 { return now }
    let elapsed = now.timeIntervalSince(start)
    guard elapsed >= 300, used > 0 else { return nil }
    let rate = used / elapsed
    let hit = now.addingTimeInterval((100 - used) / rate)
    return hit < resets ? hit : nil
  }
}

/// A plan's current limits, from whichever source reported them.
public struct PlanLimits: Codable, Equatable, Sendable {
  public var tool: String
  public var plan: String?
  public var session: LimitWindow?
  public var week: LimitWindow?
  public var updated: Date
  public init(tool: String, plan: String? = nil, session: LimitWindow?, week: LimitWindow?, updated: Date) {
    self.tool = tool; self.plan = plan; self.session = session; self.week = week; self.updated = updated
  }
  /// The tighter of the two windows, for one-number summaries.
  public var headline: Double { max(session?.used ?? 0, week?.used ?? 0) }

  /// Codex writes `rate_limits` into each `token_count` event of its session log; the newest wins.
  public static func codex(lines: [String], now: Date = Date()) -> PlanLimits? {
    for line in lines.reversed() where line.contains("\"rate_limits\"") {
      guard let data = line.data(using: .utf8),
        let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let payload = row["payload"] as? [String: Any],
        let limits = (payload["rate_limits"] ?? (payload["info"] as? [String: Any])?["rate_limits"]) as? [String: Any]
      else { continue }
      func window(_ key: String) -> LimitWindow? {
        guard let value = limits[key] as? [String: Any], let used = number(value["used_percent"]) else { return nil }
        let minutes = Int(number(value["window_minutes"]) ?? 0)
        let resets: Date
        if let at = number(value["resets_at"]) {
          resets = Date(timeIntervalSince1970: at)
        } else if let seconds = number(value["resets_in_seconds"]) {
          resets = (stamp(row["timestamp"]) ?? now).addingTimeInterval(seconds)
        } else { return nil }
        return LimitWindow(used: used, minutes: minutes, resets: resets)
      }
      let updated = stamp(row["timestamp"]) ?? now
      var session = window("primary"), week = window("secondary")
      // A window that already reset is back to zero.
      if let s = session, s.resets < now { session = LimitWindow(used: 0, minutes: s.minutes, resets: s.resets.addingTimeInterval(Double(s.minutes) * 60)) }
      if let w = week, w.resets < now { week = LimitWindow(used: 0, minutes: w.minutes, resets: w.resets.addingTimeInterval(Double(w.minutes) * 60)) }
      guard session != nil || week != nil else { continue }
      return PlanLimits(tool: "Codex", plan: limits["plan_type"] as? String, session: session, week: week, updated: updated)
    }
    return nil
  }

  /// Claude's usage response: `five_hour` and `seven_day`, each with `utilization` and `resets_at`.
  public static func claude(_ data: Data, now: Date = Date()) -> PlanLimits? {
    guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    func window(_ key: String, minutes: Int) -> LimitWindow? {
      guard let value = row[key] as? [String: Any], let used = number(value["utilization"]) else { return nil }
      let resets = stamp(value["resets_at"]) ?? now.addingTimeInterval(Double(minutes) * 60)
      return LimitWindow(used: used, minutes: minutes, resets: resets)
    }
    let session = window("five_hour", minutes: 300), week = window("seven_day", minutes: 10080)
    guard session != nil || week != nil else { return nil }
    return PlanLimits(tool: "Claude", session: session, week: week, updated: now)
  }

  static func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value.isFinite ? value : nil }
    if let value = value as? Int { return Double(value) }
    if let value = value as? String { return Double(value) }
    return nil
  }
  static func stamp(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
    // Microsecond precision (`.858680+00:00`) is more than the formatter accepts; drop the fraction.
    guard let dot = text.firstIndex(of: ".") else { return nil }
    let rest = text[text.index(after: dot)...].drop { $0.isNumber }
    return ISO8601DateFormatter().date(from: String(text[..<dot]) + rest)
  }
}
