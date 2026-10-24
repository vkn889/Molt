import AppKit
import MoltCore
import Security
import SwiftUI

/// Your Claude and Codex plan limits: the 5-hour and weekly windows, and when you'd hit them at
/// today's pace. Codex writes its limits into its own session logs, so those need nothing extra.
/// Claude's come from the same usage endpoint Claude Code's `/usage` reads, signed in with Claude
/// Code's own login from your keychain; that's off until you turn it on, and the token is never
/// stored by Molt or sent anywhere but Anthropic.
@MainActor final class PlanController: ObservableObject {
  @Published private(set) var claude: PlanLimits?
  @Published private(set) var codex: PlanLimits?
  @Published private(set) var claudeStatus = ""
  @Published var claudeEnabled = UserDefaults.standard.bool(forKey: "claudeLimits") {
    didSet {
      UserDefaults.standard.set(claudeEnabled, forKey: "claudeLimits")
      if claudeEnabled { refresh(force: true) } else { claude = nil; claudeStatus = "" }
    }
  }
  private var lastClaude = Date.distantPast
  private var lastCodex = Date.distantPast
  private var loading = false

  var all: [PlanLimits] { [claude, codex].compactMap { $0 } }
  /// The highest share of any window in use, 0 to 100.
  var tightest: Double { all.map(\.headline).max() ?? 0 }

  /// Refreshes Codex at most every 30 seconds and Claude at most every 5 minutes.
  func refresh(force: Bool = false) {
    if force || Date().timeIntervalSince(lastCodex) > 30 {
      lastCodex = Date()
      Task {
        let value = await Task.detached(priority: .utility) { Self.readCodex() }.value
        codex = value
      }
    }
    guard claudeEnabled, !loading, force || Date().timeIntervalSince(lastClaude) > 300 else { return }
    lastClaude = Date()
    loading = true
    Task {
      defer { loading = false }
      guard let token = await Self.claudeToken() else {
        claudeStatus = "Couldn't read Claude Code's sign-in. Open Claude Code once, then try again."
        return
      }
      var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
      request.timeoutInterval = 15
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let limits = PlanLimits.claude(data) else {
          claudeStatus = status == 401 ? "Claude Code's sign-in expired. Run Claude Code once to refresh it." : "Claude usage is unavailable right now."
          return
        }
        claude = limits
        claudeStatus = ""
      } catch { claudeStatus = "Claude usage is unavailable right now." }
    }
  }

  /// Claude Code keeps its login in the keychain item "Claude Code-credentials". macOS asks you
  /// before Molt can read it. Asking through the Security framework, not the `security` tool,
  /// means "Always Allow" trusts only Molt's signature, never every program that runs `security`.
  nonisolated private static func claudeToken() async -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    let found = await Task.detached(priority: .utility) { () -> Data? in
      var item: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
      return item as? Data
    }.value
    guard let data = found,
      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = row["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty
    else { return nil }
    return token
  }

  /// The newest Codex session log from the last few days, read from its end.
  nonisolated static func readCodex() -> PlanLimits? {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    let calendar = Calendar(identifier: .gregorian)
    var newest: (URL, Date)?
    for back in 0..<7 {
      guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { continue }
      let c = calendar.dateComponents([.year, .month, .day], from: day)
      let folder = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
      for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
      where file.pathExtension == "jsonl" {
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if date > (newest?.1 ?? .distantPast) { newest = (file, date) }
      }
      if newest != nil { break }
    }
    guard let file = newest?.0, let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
    let data = (try? handle.readToEnd()) ?? Data()
    return PlanLimits.codex(lines: String(decoding: data, as: UTF8.self).components(separatedBy: "\n"))
  }

  func loadDemo() {
    let now = Date()
    claude = PlanLimits(tool: "Claude", plan: "Max", session: LimitWindow(used: 64, minutes: 300, resets: now.addingTimeInterval(7700)),
      week: LimitWindow(used: 31, minutes: 10080, resets: now.addingTimeInterval(4 * 86400)), updated: now)
    codex = PlanLimits(tool: "Codex", plan: "plus", session: LimitWindow(used: 22, minutes: 300, resets: now.addingTimeInterval(13000)),
      week: LimitWindow(used: 47, minutes: 10080, resets: now.addingTimeInterval(2 * 86400)), updated: now)
  }
  static func pace(_ window: LimitWindow, now: Date = Date()) -> String {
    if window.used >= 100 { return "Limit reached · resets \(clock(window.resets))" }
    if let hit = window.forecast(now: now) { return "At this pace, full at \(clock(hit))" }
    return "Resets \(clock(window.resets))"
  }
  static func clock(_ date: Date) -> String {
    Calendar.current.isDateInToday(date)
      ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
  }
}
