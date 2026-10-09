import AppKit
import MoltCore
import SwiftUI
import UserNotifications

/// Molting: friends, who's online, hangouts where two Molts share a little playground, and
/// lending your notch setup to a friend. The server decides who can see and do what.
@MainActor final class SocialController: ObservableObject {
  struct Friend: Identifiable, Equatable {
    var profile: Profile
    var accepted: Bool
    var incoming: Bool
    var id: UUID { profile.id }
  }
  struct Loan: Identifiable, Equatable {
    var id: UUID
    var owner: UUID
    var borrower: UUID
    var title: String
    var payload: Data
    var expires: Date?
    var returned: Date?
  }
  struct Hangout: Equatable {
    var id: UUID
    var friend: Profile
    var host: Bool
    var started: Date?
    var me = CGPoint(x: 0.3, y: 0.7)
    var them: CGPoint?
    var myEmote: String?
    var theirEmote: String?
    var reward: Int?
  }
  struct Invite: Identifiable, Equatable { var id: UUID; var from: Profile; var received: Date }

  @Published private(set) var friends: [Friend] = []
  @Published private(set) var online: [String: [String: Any]] = [:] {
    didSet { onlineIDs = Set(online.keys.compactMap(UUID.init(uuidString:))) }
  }
  @Published private(set) var onlineIDs: Set<UUID> = []
  @Published private(set) var loans: [Loan] = []
  @Published private(set) var invites: [Invite] = []
  @Published private(set) var hangout: Hangout?
  @Published private(set) var waitingFor: Profile?
  @Published var status = ""
  @Published private(set) var borrowing: Loan?
  static let inviteNotification = "molt-hangout-invite"

  let account: AccountController
  var captureSetup: () -> [String: Any] = { [:] }
  var applySetup: ([String: Any]) -> Void = { _ in }
  private lazy var socket = RealtimeSocket { [weak self] in try? await self?.account.accessToken() }
  private var lobby: RealtimeChannel?
  private var inbox: RealtimeChannel?
  private var room: RealtimeChannel?
  private var lastSent = Date.distantPast
  private var poll: Task<Void, Never>?

  init(account: AccountController) {
    self.account = account
    if let data = UserDefaults.standard.data(forKey: "borrowedLoan"), let loan = try? JSONDecoder().decode(StoredLoan.self, from: data) {
      borrowing = loan.loan
    }
  }

  var me: UUID? { account.userID }
  var friendsAccepted: [Friend] { friends.filter(\.accepted) }
  var requests: [Friend] { friends.filter { !$0.accepted && $0.incoming } }
  var sent: [Friend] { friends.filter { !$0.accepted && !$0.incoming } }
  /// Signed-in Molt users online right now who are open to meeting people and not yet friends.
  var discover: [Profile] {
    let known = Set(friends.map(\.id))
    return online.compactMap { key, meta -> Profile? in
      guard let id = UUID(uuidString: key), id != me, !known.contains(id) else { return nil }
      return Profile(
        id: id, username: meta["username"] as? String ?? "molt", moltName: meta["molt_name"] as? String ?? "Molt",
        palette: meta["palette"] as? String ?? "sage", points: 0, social: meta["social"] as? Int ?? 0, discoverable: true)
    }.sorted { $0.social > $1.social }
  }

  // MARK: Connection

  /// Connects the lobby and your personal inbox once you are signed in.
  func start() {
    guard let me, lobby == nil, account.phase == .signedIn else { return }
    let lobby = socket.channel("lobby", presenceKey: me.uuidString)
    lobby.onPresence = { [weak self] state in self?.online = state }
    lobby.onJoin = { [weak self] ok, _ in if ok { self?.announce() } }
    lobby.join()
    self.lobby = lobby
    // Invitations arrive as new hangout rows addressed to you; nobody else can read them.
    let inbox = socket.channel(
      "user:\(me.uuidString)",
      changes: [["event": "INSERT", "schema": "public", "table": "hangouts", "filter": "guest=eq.\(me.uuidString)"]])
    inbox.onChange = { [weak self] data in self?.invited(data) }
    inbox.join()
    self.inbox = inbox
    refresh()
    checkLoanExpiry()
  }
  func stop() {
    socket.disconnect()
    lobby = nil
    inbox = nil
    room = nil
    hangout = nil
    waitingFor = nil
    friends = []
    online = [:]
  }
  /// Tells the lobby you're here, unless you've chosen not to be discoverable.
  func announce() {
    guard let profile = account.profile, profile.discoverable else { return }
    var meta: [String: Any] = ["username": profile.username, "molt_name": profile.moltName, "palette": profile.palette, "social": profile.social]
    if shareActivity, let doing { meta["doing"] = String(doing.prefix(60)) }
    lobby?.track(meta)
  }
  /// What you're up to, like "Coding with Claude Code", shown to friends while you're online.
  var doing: String? { didSet { if doing != oldValue { announce() } } }
  @Published var shareActivity = UserDefaults.standard.bool(forKey: "shareActivity") {
    didSet { UserDefaults.standard.set(shareActivity, forKey: "shareActivity"); announce() }
  }
  func doing(_ id: UUID) -> String? {
    (online[id.uuidString]?["doing"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
  }

  // MARK: Friends

  func refresh() {
    guard me != nil else { return }
    Task {
      do {
        try await loadFriends()
        try await loadLoans()
        try await loadInvites()
      } catch { status = error.localizedDescription }
    }
  }
  func addFriend(_ username: String) {
    let name = username.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
    guard AccountRules.usernameProblem(name) == nil, let me else { status = "Enter a username like @molt_fan."; return }
    guard name != account.profile?.username else { status = "That's you."; return }
    Task {
      do {
        let (data, _) = try await account.call("GET", "/rest/v1/profiles?username=eq.\(name)&select=*")
        guard let profile = try JSONDecoder().decode([Profile].self, from: data).first else {
          status = "No one is called @\(name)."; return
        }
        try await sendRequest(to: profile.id, from: me)
        status = "Friend request sent to @\(name)."
      } catch { status = error.localizedDescription }
    }
  }
  func addFriend(_ profile: Profile) {
    guard let me else { return }
    Task {
      do { try await sendRequest(to: profile.id, from: me); status = "Friend request sent to @\(profile.username)." } catch { status = error.localizedDescription }
    }
  }
  func accept(_ friend: Friend) {
    guard let me else { return }
    Task {
      _ = try? await account.call("PATCH", "/rest/v1/friendships?requester=eq.\(friend.id.uuidString)&addressee=eq.\(me.uuidString)", body: ["status": "accepted"])
      refresh()
    }
  }
  func remove(_ friend: Friend) {
    guard let me else { return }
    let a = me.uuidString, b = friend.id.uuidString
    Task {
      _ = try? await account.call("DELETE", "/rest/v1/friendships?or=(and(requester.eq.\(a),addressee.eq.\(b)),and(requester.eq.\(b),addressee.eq.\(a)))")
      refresh()
    }
  }
  private func sendRequest(to id: UUID, from me: UUID) async throws {
    let (data, code) = try await account.call("POST", "/rest/v1/friendships", body: ["requester": me.uuidString, "addressee": id.uuidString])
    guard (200..<300).contains(code) else {
      let text = String(data: data, encoding: .utf8) ?? ""
      throw CloudError(message: text.contains("23505") ? "You're already friends, or a request is waiting." : "Couldn't send that request.")
    }
    try await loadFriends()
  }
  private func loadFriends() async throws {
    guard let me else { return }
    struct Row: Decodable { var requester: UUID; var addressee: UUID; var status: String }
    let (data, code) = try await account.call("GET", "/rest/v1/friendships?select=requester,addressee,status")
    guard code == 200 else { return }
    let rows = try JSONDecoder().decode([Row].self, from: data)
    let ids = rows.map { $0.requester == me ? $0.addressee : $0.requester }
    guard !ids.isEmpty else { friends = []; return }
    let (profileData, _) = try await account.call("GET", "/rest/v1/profiles?id=in.(\(ids.map(\.uuidString).joined(separator: ",")))&select=*")
    let profiles = Dictionary(uniqueKeysWithValues: try JSONDecoder().decode([Profile].self, from: profileData).map { ($0.id, $0) })
    friends = rows.compactMap { row in
      let other = row.requester == me ? row.addressee : row.requester
      guard let profile = profiles[other] else { return nil }
      return Friend(profile: profile, accepted: row.status == "accepted", incoming: row.addressee == me)
    }.sorted { ($0.accepted ? 1 : 0, $0.profile.social) > ($1.accepted ? 1 : 0, $1.profile.social) }
  }

  // MARK: Hangouts

  func invite(_ friend: Profile) {
    guard let me, hangout == nil, waitingFor == nil else { return }
    Task {
      do {
        let (data, code) = try await account.call(
          "POST", "/rest/v1/hangouts?select=id", body: ["host": me.uuidString, "guest": friend.id.uuidString], prefer: "return=representation")
        guard code == 201, let id = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first?["id"] as? String,
          let hangoutID = UUID(uuidString: id)
        else { throw CloudError(message: "Couldn't start a hangout.") }
        waitingFor = friend
        enter(Hangout(id: hangoutID, friend: friend, host: true))
        watchInvitation(hangoutID)
      } catch { status = error.localizedDescription }
    }
  }
  func accept(_ invite: Invite) {
    invites.removeAll { $0.id == invite.id }
    Task {
      do {
        let (data, code) = try await account.call("POST", "/rest/v1/rpc/accept_hangout", body: ["hangout": invite.id.uuidString])
        guard code == 200 else { throw CloudError(message: String(data: data, encoding: .utf8)?.contains("no longer") == true ? "That invitation expired." : "Couldn't join the hangout.") }
        var state = Hangout(id: invite.id, friend: invite.from, host: false)
        state.started = Date()
        state.me = CGPoint(x: 0.7, y: 0.7)
        enter(state)
      } catch { status = error.localizedDescription }
    }
  }
  func decline(_ invite: Invite) {
    invites.removeAll { $0.id == invite.id }
    Task { _ = try? await account.call("POST", "/rest/v1/rpc/decline_hangout", body: ["hangout": invite.id.uuidString]) }
  }
  func move(to point: CGPoint) {
    guard hangout != nil else { return }
    hangout?.me = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    sendPosition()
  }
  func emote(_ kind: String) {
    guard hangout != nil else { return }
    hangout?.myEmote = kind
    room?.broadcast("emote", ["kind": kind])
    Task {
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      if hangout?.myEmote == kind { hangout?.myEmote = nil }
    }
  }
  /// Leaving ends the hangout for both, and the server awards points for time spent together.
  func leave() {
    guard let current = hangout else { return }
    room?.broadcast("left")
    Task {
      let (data, _) = (try? await account.call("POST", "/rest/v1/rpc/end_hangout", body: ["hangout": current.id.uuidString])) ?? (Data(), 0)
      let reward = Int(String(data: data, encoding: .utf8) ?? "") ?? 0
      finish(reward: reward)
    }
  }
  func dismissSummary() { hangout = nil }

  private func enter(_ state: Hangout) {
    hangout = state
    let room = socket.channel("hangout:\(state.id.uuidString)")
    room.onBroadcast = { [weak self] event, payload in self?.roomEvent(event, payload) }
    room.onJoin = { [weak self] ok, reason in
      guard let self else { return }
      if ok {
        self.room?.broadcast("hello")
        self.sendPosition(force: true)
      } else {
        self.status = reason ?? "Couldn't open the playground."
      }
    }
    room.join()
    self.room = room
  }
  private func roomEvent(_ event: String, _ payload: [String: Any]) {
    guard hangout != nil else { return }
    switch event {
    case "hello":
      if hangout?.started == nil { hangout?.started = Date() }
      waitingFor = nil
      sendPosition(force: true)
    case "pos":
      if let x = payload["x"] as? Double, let y = payload["y"] as? Double { hangout?.them = CGPoint(x: x, y: y) }
      if hangout?.started == nil { hangout?.started = Date(); waitingFor = nil }
    case "emote":
      let kind = payload["kind"] as? String
      hangout?.theirEmote = kind
      Task {
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if hangout?.theirEmote == kind { hangout?.theirEmote = nil }
      }
    case "left":
      guard let current = hangout, current.reward == nil else { return }
      Task {
        let (data, _) = (try? await account.call("POST", "/rest/v1/rpc/end_hangout", body: ["hangout": current.id.uuidString])) ?? (Data(), 0)
        finish(reward: Int(String(data: data, encoding: .utf8) ?? "") ?? 0)
      }
    default: break
    }
  }
  private func sendPosition(force: Bool = false) {
    guard let current = hangout, force || Date().timeIntervalSince(lastSent) > 0.15 else { return }
    lastSent = Date()
    room?.broadcast("pos", ["x": Double(current.me.x), "y": Double(current.me.y)])
  }
  private func finish(reward: Int) {
    room?.leave()
    room = nil
    waitingFor = nil
    poll?.cancel()
    hangout?.reward = reward
    account.reloadProfile()
    refresh()
  }
  private func watchInvitation(_ id: UUID) {
    poll?.cancel()
    poll = Task {
      let deadline = Date().addingTimeInterval(600)
      while !Task.isCancelled, Date() < deadline, waitingFor != nil {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard let (data, _) = try? await account.call("GET", "/rest/v1/hangouts?id=eq.\(id.uuidString)&select=status"),
          let row = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first,
          let state = row["status"] as? String
        else { continue }
        if state == "active" {
          if hangout?.started == nil { hangout?.started = Date() }
          waitingFor = nil
        } else if state == "declined" {
          status = "@\(waitingFor?.username ?? "friend") can't hang out right now."
          cancelInvite(id)
          return
        }
      }
      if waitingFor != nil { cancelInvite(id); status = "No answer this time." }
    }
  }
  func cancelWaiting() {
    guard let id = hangout?.id else { return }
    cancelInvite(id)
  }
  private func cancelInvite(_ id: UUID) {
    Task { _ = try? await account.call("POST", "/rest/v1/rpc/decline_hangout", body: ["hangout": id.uuidString]) }
    room?.leave()
    room = nil
    waitingFor = nil
    hangout = nil
    poll?.cancel()
  }
  private func invited(_ data: [String: Any]) {
    guard data["type"] as? String == "INSERT", let record = data["record"] as? [String: Any],
      record["status"] as? String == "invited",
      let id = (record["id"] as? String).flatMap(UUID.init(uuidString:)),
      let host = (record["host"] as? String).flatMap(UUID.init(uuidString:)),
      !invites.contains(where: { $0.id == id })
    else { return }
    Task {
      if friends.first(where: { $0.id == host }) == nil { try? await loadFriends() }
      guard let profile = friends.first(where: { $0.id == host })?.profile else { return }
      invites.append(Invite(id: id, from: profile, received: Date()))
      notify("@\(profile.username) wants to hang out", body: "Open Molt's Molting page to join.")
    }
  }
  private func loadInvites() async throws {
    guard let me else { return }
    let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
    let (data, code) = try await account.call("GET", "/rest/v1/hangouts?guest=eq.\(me.uuidString)&status=eq.invited&created_at=gt.\(since)&select=id,host")
    guard code == 200, let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
    for row in rows {
      guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)), let host = (row["host"] as? String).flatMap(UUID.init(uuidString:)),
        let profile = friends.first(where: { $0.id == host })?.profile, !invites.contains(where: { $0.id == id })
      else { continue }
      invites.append(Invite(id: id, from: profile, received: Date()))
    }
  }
  private func notify(_ title: String, body: String) {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.inviteNotification, content: content, trigger: nil))
  }

  // MARK: Lending your setup

  func lend(to friend: Profile, days: Int?) {
    guard let me else { return }
    var body: [String: Any] = [
      "owner": me.uuidString, "borrower": friend.id.uuidString,
      "title": "\(account.profile.map { "@" + $0.username } ?? "A friend")'s setup", "payload": captureSetup(),
    ]
    if let days { body["expires_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(days) * 86400)) }
    Task {
      let (_, code) = (try? await account.call("POST", "/rest/v1/loans", body: body)) ?? (Data(), 0)
      status = (200..<300).contains(code) ? "Lent your setup to @\(friend.username)." : "Couldn't lend your setup."
      try? await loadLoans()
    }
  }
  /// Tries on a friend's setup. Your own setup is kept safe and comes back when you return it.
  func borrow(_ loan: Loan) {
    guard borrowing == nil, let payload = try? JSONSerialization.jsonObject(with: loan.payload) as? [String: Any] else { return }
    let backup = captureSetup()
    guard let saved = try? JSONSerialization.data(withJSONObject: backup) else { return }
    UserDefaults.standard.set(saved, forKey: "setupBackup")
    if let data = try? JSONEncoder().encode(StoredLoan(loan: loan)) { UserDefaults.standard.set(data, forKey: "borrowedLoan") }
    borrowing = loan
    applySetup(payload)
    status = "Trying on \(loan.title)."
  }
  func giveBack() {
    guard let loan = borrowing else { return }
    restoreOwnSetup()
    Task {
      _ = try? await account.call("PATCH", "/rest/v1/loans?id=eq.\(loan.id.uuidString)", body: ["returned_at": ISO8601DateFormatter().string(from: Date())])
      try? await loadLoans()
    }
  }
  func takeBack(_ loan: Loan) {
    Task {
      _ = try? await account.call("DELETE", "/rest/v1/loans?id=eq.\(loan.id.uuidString)")
      try? await loadLoans()
    }
  }
  private func restoreOwnSetup() {
    if let data = UserDefaults.standard.data(forKey: "setupBackup"),
      let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      applySetup(backup)
    }
    UserDefaults.standard.removeObject(forKey: "setupBackup")
    UserDefaults.standard.removeObject(forKey: "borrowedLoan")
    borrowing = nil
    status = "Your own setup is back."
  }
  /// A loan ends when it expires or the owner takes it back.
  private func checkLoanExpiry() {
    guard let loan = borrowing else { return }
    if let expires = loan.expires, expires < Date() { restoreOwnSetup() }
  }
  private func loadLoans() async throws {
    let (data, code) = try await account.call("GET", "/rest/v1/loans?select=*&returned_at=is.null&order=created_at.desc")
    guard code == 200, let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    func date(_ value: Any?) -> Date? { (value as? String).flatMap { formatter.date(from: $0) ?? plain.date(from: $0) } }
    loans = rows.compactMap { row in
      guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
        let owner = (row["owner"] as? String).flatMap(UUID.init(uuidString:)),
        let borrower = (row["borrower"] as? String).flatMap(UUID.init(uuidString:)),
        let payload = row["payload"], let data = try? JSONSerialization.data(withJSONObject: payload)
      else { return nil }
      return Loan(id: id, owner: owner, borrower: borrower, title: row["title"] as? String ?? "Setup", payload: data, expires: date(row["expires_at"]), returned: nil)
    }
    // If the owner took their setup back, return to yours.
    if let current = borrowing, !loans.contains(where: { $0.id == current.id }) { restoreOwnSetup() }
    checkLoanExpiry()
  }
  private struct StoredLoan: Codable {
    var id: UUID, owner: UUID, borrower: UUID, title: String, payload: Data, expires: Date?
    init(loan: Loan) { id = loan.id; owner = loan.owner; borrower = loan.borrower; title = loan.title; payload = loan.payload; expires = loan.expires }
    var loan: Loan { Loan(id: id, owner: owner, borrower: borrower, title: title, payload: payload, expires: expires, returned: nil) }
  }
}
