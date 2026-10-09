import AppKit
import MoltCore
import SwiftUI
import UserNotifications

/// Your pull requests, reviews waiting on you, one repository's default-branch checks and your
/// contribution streak. Molt signs in with the GitHub CLI's login when `gh` is installed, or with
/// a token you paste (kept in the keychain). Requests go only to api.github.com.
@MainActor final class GitHubController: ObservableObject {
  @Published private(set) var summary: GitHubSummary?
  @Published private(set) var status = ""
  @Published private(set) var busy = false
  @Published private(set) var source = ""
  @Published var enabled = UserDefaults.standard.bool(forKey: "githubEnabled") {
    didSet { UserDefaults.standard.set(enabled, forKey: "githubEnabled"); if enabled { refresh(force: true) } else { summary = nil } }
  }
  /// `owner/name` whose default branch Molt watches. Empty means the repository you last worked in.
  @Published var watched = UserDefaults.standard.string(forKey: "githubRepo") ?? "" {
    didSet { UserDefaults.standard.set(watched, forKey: "githubRepo") }
  }
  @Published private(set) var bestStreak = UserDefaults.standard.integer(forKey: "githubBestStreak")
  /// Directory of the most recent agent session, for picking a repository automatically.
  var recentDirectory: () -> String? = { nil }
  var onBanner: (IslandBanner) -> Void = { _ in }
  private var last = Date.distantPast
  private static let keychain = KeychainItem<String>(service: "app.molt.github", account: "token")

  var hasToken: Bool { Self.keychain.read() != nil }
  func setToken(_ value: String) {
    let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.count > 20, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
      status = "That doesn't look like a GitHub token."
      return
    }
    Self.keychain.write(token)
    enabled = true
    refresh(force: true)
  }
  func forgetToken() { Self.keychain.delete(); refresh(force: true) }

  /// Refreshes at most every 10 minutes unless forced.
  func refresh(force: Bool = false) {
    guard enabled, !busy, force || Date().timeIntervalSince(last) > 600 else { return }
    busy = true
    last = Date()
    let watched = self.watched, recent = recentDirectory()
    Task {
      defer { busy = false }
      guard let (token, from) = await Self.token() else {
        status = "Install the GitHub CLI and run `gh auth login`, or paste a token."
        return
      }
      source = from
      var repository = watched
      if repository.isEmpty, let recent {
        let remote = await QuickActions.output("/usr/bin/git", ["-C", recent, "remote", "get-url", "origin"])
        repository = GitHubSummary.repository(fromRemote: remote) ?? ""
      }
      let parts = repository.split(separator: "/").map(String.init)
      let variables: [String: Any] = [
        "owner": parts.first ?? "", "name": parts.count > 1 ? parts[1] : "", "watch": parts.count == 2,
      ]
      do {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": GitHubSummary.query, "variables": variables])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
          status = code == 401 ? "GitHub didn't accept the sign-in." : "GitHub is unavailable (\(code))."
          return
        }
        let next = try GitHubSummary.parse(data)
        noticeChanges(from: summary, to: next)
        summary = next
        if next.streak > bestStreak {
          bestStreak = next.streak
          UserDefaults.standard.set(bestStreak, forKey: "githubBestStreak")
        }
        status = ""
      } catch { status = (error as? LocalizedError)?.errorDescription ?? "GitHub is unavailable." }
    }
  }

  /// A red default branch and reviews that have waited over a day are worth a nudge, once.
  private func noticeChanges(from old: GitHubSummary?, to new: GitHubSummary) {
    if new.ci == .failing, old?.ci != .failing, let repo = new.repository {
      onBanner(.message("\(repo) · \(new.branch ?? "main") checks failed", symbol: "xmark.octagon.fill"))
      notify("Checks failed on \(new.branch ?? "main")", body: repo)
    }
    let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
    let waiting = new.waiting(now: Date())
    if !waiting.isEmpty, UserDefaults.standard.double(forKey: "githubNudged") < day {
      UserDefaults.standard.set(day, forKey: "githubNudged")
      notify("\(waiting.count) review\(waiting.count == 1 ? "" : "s") waiting over a day", body: waiting.first?.title ?? "")
    }
  }
  private func notify(_ title: String, body: String) {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "molt-github-\(UUID())", content: content, trigger: nil))
  }

  /// A pasted token wins; otherwise the GitHub CLI's.
  nonisolated private static func token() async -> (String, String)? {
    if let saved = keychain.read() { return (saved, "token") }
    for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
      let token = await QuickActions.output(path, ["auth", "token"]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !token.isEmpty { return (token, "gh") }
    }
    return nil
  }

  func loadDemo() {
    let now = Date()
    let calendar = Calendar(identifier: .gregorian)
    let start = calendar.date(byAdding: .day, value: -139 - calendar.component(.weekday, from: now) + 1, to: now)!
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let days = (0..<(140 + calendar.component(.weekday, from: now) - 1)).map { offset -> GitHubSummary.Day in
      let date = calendar.date(byAdding: .day, value: offset, to: start)!
      let seed = CreatureView.random(offset, 3)
      let recent = offset > 125
      return GitHubSummary.Day(date: formatter.string(from: date), count: recent ? 1 + Int(seed * 6) : seed < 0.35 ? 0 : Int(seed * 9))
    }
    func pr(_ number: Int, _ title: String, _ repo: String, _ checks: String?, _ age: Double, _ author: String? = nil) -> GitHubSummary.PullRequest {
      GitHubSummary.PullRequest(number: number, title: title, url: "https://github.com/\(repo)/pull/\(number)", repository: repo, created: now.addingTimeInterval(-age), author: author, checks: checks)
    }
    summary = GitHubSummary(
      login: "molt-fan",
      mine: [pr(312, "Answer agent approvals from the notch", "molt/molt", "SUCCESS", 7200), pr(309, "Pixel wardrobe with seasonal items", "molt/molt", "PENDING", 86400),
        pr(57, "Faster contribution grid", "molt/site", "SUCCESS", 300000)],
      reviews: [pr(301, "Plan usage forecast", "molt/molt", nil, 120000, "pal"), pr(88, "Fix dark mode toggle", "molt/site", nil, 3600, "sam")],
      days: days, repository: "molt/molt", branch: "main", ci: .passing, fetched: now)
    bestStreak = 14
  }
  func open(_ link: String) {
    guard let url = URL(string: link), url.host == "github.com" else { return }
    NSWorkspace.shared.open(url)
  }
}
