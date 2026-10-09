import Foundation

/// What Molt shows from GitHub: your open pull requests, reviews waiting on you, the default
/// branch's checks for one repository, and your contribution streak.
public struct GitHubSummary: Codable, Equatable, Sendable {
  public struct PullRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String { url }
    public var number: Int
    public var title: String
    public var url: String
    public var repository: String
    public var created: Date
    public var author: String?
    /// SUCCESS, FAILURE, PENDING, ERROR or EXPECTED, when the pull request has checks.
    public var checks: String?
    public init(number: Int, title: String, url: String, repository: String, created: Date, author: String?, checks: String?) {
      self.number = number; self.title = title; self.url = url; self.repository = repository
      self.created = created; self.author = author; self.checks = checks
    }
  }
  public enum CI: String, Codable, Sendable { case passing, failing, running, none }
  public var login: String
  public var mine: [PullRequest]
  public var reviews: [PullRequest]
  public var days: [Day]
  public var repository: String?
  public var branch: String?
  public var ci: CI
  public var fetched: Date
  public struct Day: Codable, Equatable, Sendable {
    public var date: String
    public var count: Int
    public init(date: String, count: Int) { self.date = date; self.count = count }
  }
  public init(login: String, mine: [PullRequest], reviews: [PullRequest], days: [Day], repository: String?, branch: String?, ci: CI, fetched: Date) {
    self.login = login; self.mine = mine; self.reviews = reviews; self.days = days
    self.repository = repository; self.branch = branch; self.ci = ci; self.fetched = fetched
  }

  public var total: Int { days.reduce(0) { $0 + $1.count } }
  /// Days in a row with at least one contribution, ending today, or yesterday if today has none yet.
  public var streak: Int {
    var list = days
    if list.last?.count == 0 { list.removeLast() }
    var run = 0
    for day in list.reversed() {
      guard day.count > 0 else { break }
      run += 1
    }
    return run
  }
  /// Reviews requested from you that have waited longer than a day.
  public func waiting(now: Date) -> [PullRequest] { reviews.filter { now.timeIntervalSince($0.created) > 86400 } }

  public static let query = """
    query($owner: String!, $name: String!, $watch: Boolean!) {
      viewer {
        login
        contributionsCollection { contributionCalendar { weeks { contributionDays { date contributionCount } } } }
        pullRequests(states: OPEN, first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes { number title url createdAt repository { nameWithOwner }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
        }
      }
      reviews: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
        nodes { ... on PullRequest { number title url createdAt repository { nameWithOwner } author { login } } }
      }
      repository(owner: $owner, name: $name) @include(if: $watch) {
        nameWithOwner
        defaultBranchRef { name target { ... on Commit { statusCheckRollup { state } } } }
      }
    }
    """

  public static func parse(_ data: Data, now: Date = Date()) throws -> GitHubSummary {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MoltError.invalid("GitHub sent an unreadable answer.") }
    if let errors = root["errors"] as? [[String: Any]], root["data"] == nil || root["data"] is NSNull {
      throw MoltError.invalid(errors.first?["message"] as? String ?? "GitHub refused the request.")
    }
    guard let data = root["data"] as? [String: Any], let viewer = data["viewer"] as? [String: Any] else {
      throw MoltError.invalid("GitHub sent an unreadable answer.")
    }
    func date(_ value: Any?) -> Date { (value as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? now }
    func pull(_ node: [String: Any]) -> PullRequest? {
      guard let number = node["number"] as? Int, let title = node["title"] as? String, let url = node["url"] as? String,
        url.hasPrefix("https://github.com/")
      else { return nil }
      let commit = ((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any]
      return PullRequest(
        number: number, title: String(title.prefix(200)), url: url,
        repository: (node["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? "",
        created: date(node["createdAt"]), author: (node["author"] as? [String: Any])?["login"] as? String,
        checks: (commit?["statusCheckRollup"] as? [String: Any])?["state"] as? String)
    }
    let weeks = (((viewer["contributionsCollection"] as? [String: Any])?["contributionCalendar"] as? [String: Any])?["weeks"] as? [[String: Any]]) ?? []
    let days = weeks.flatMap { ($0["contributionDays"] as? [[String: Any]]) ?? [] }.compactMap { day -> Day? in
      guard let date = day["date"] as? String, let count = day["contributionCount"] as? Int else { return nil }
      return Day(date: date, count: count)
    }
    let mine = (((viewer["pullRequests"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap(pull)
    let reviews = (((data["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap(pull)
    let repo = data["repository"] as? [String: Any]
    let ref = repo?["defaultBranchRef"] as? [String: Any]
    let state = ((ref?["target"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])?["state"] as? String
    return GitHubSummary(
      login: viewer["login"] as? String ?? "", mine: mine, reviews: reviews, days: days,
      repository: repo?["nameWithOwner"] as? String, branch: ref?["name"] as? String, ci: ci(state), fetched: now)
  }
  public static func ci(_ state: String?) -> CI {
    switch state {
    case "SUCCESS": return .passing
    case "FAILURE", "ERROR": return .failing
    case "PENDING", "EXPECTED": return .running
    default: return .none
    }
  }
  /// `owner/name` from a git remote URL such as `git@github.com:owner/name.git`.
  public static func repository(fromRemote remote: String) -> String? {
    var text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.contains("github.com") else { return nil }
    if text.hasSuffix(".git") { text.removeLast(4) }
    guard let range = text.range(of: "github.com") else { return nil }
    let tail = text[range.upperBound...].drop { $0 == ":" || $0 == "/" }
    let parts = tail.split(separator: "/")
    guard parts.count >= 2 else { return nil }
    let valid = { (s: Substring) in !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }
    guard valid(parts[0]), valid(parts[1]) else { return nil }
    return "\(parts[0])/\(parts[1])"
  }
}
