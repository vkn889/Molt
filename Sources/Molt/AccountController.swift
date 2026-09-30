import AppKit
import MoltCore
import SwiftUI
import UserNotifications

/// Molt's Supabase project. The publishable key is designed to ship in apps; row-level security
/// on the server decides what each signed-in user can read and write.
enum MoltCloud {
  static let url = URL(string: "https://ybriadfpmsdntplqpexg.supabase.co")!
  static let key = "sb_publishable_krM_gnB_gUq13p3UT2ocpg_sT0jJQ0B"
}

struct CloudError: LocalizedError {
  var message: String
  var errorDescription: String? { message }
}

struct Profile: Codable, Identifiable, Equatable {
  var id: UUID
  var username: String
  var moltName: String
  var palette: String
  var points: Int
  var social: Int
  var discoverable: Bool
  enum CodingKeys: String, CodingKey {
    case id, username, palette, points, social, discoverable
    case moltName = "molt_name"
  }
  /// A friendly name for social status.
  var socialTitle: String {
    switch social {
    case 0: return "New in town"
    case 1...4: return "Friendly"
    case 5...14: return "Outgoing"
    case 15...39: return "Social butterfly"
    default: return "Star of the notch"
    }
  }
}

/// One Molt account per Mac. You sign in once; the session is kept in the keychain and refreshed
/// quietly, so Molt never asks again unless you sign out.
@MainActor final class AccountController: ObservableObject {
  enum Phase: Equatable {
    case loading, signedOut, confirmEmail(String), needsCode(String), signedIn
  }
  struct Session: Codable {
    var access: String
    var refresh: String
    var expires: Date
    var user: UUID
  }
  struct Enrollment: Equatable { var factor: String; var secret: String; var uri: String }

  @Published private(set) var phase: Phase = .loading
  @Published private(set) var profile: Profile?
  @Published private(set) var mfaEnabled = false
  @Published private(set) var enrollment: Enrollment?
  @Published private(set) var busy = false
  @Published var status = ""
  private var session: Session?
  private var pending: (email: String, password: String)?
  private let keychain = KeychainItem<Session>(service: "app.molt.account", account: "session")
  private let preview: Bool
  static let reminderID = "molt-2fa-reminder"

  init(preview: Bool = false) {
    self.preview = preview
    if preview {
      profile = Profile(id: UUID(), username: "molt_fan", moltName: "Molt", palette: "sage", points: 120, social: 6, discoverable: true)
      phase = .signedIn
      return
    }
    if let data = UserDefaults.standard.data(forKey: "accountProfile") {
      profile = try? JSONDecoder().decode(Profile.self, from: data)
    }
    session = keychain.read()
    guard session != nil else { phase = .signedOut; return }
    // A saved session means you are signed in, even offline; the server catches up when it can.
    phase = .signedIn
    Task { await restore() }
  }

  /// Previews render the first-run screen without touching the network.
  func previewSignedOut() { if preview { phase = .signedOut } }
  var userID: UUID? { session?.user ?? (preview ? profile?.id : nil) }

  // MARK: Sign up and sign in

  func signUp(email: String, password: String, username: String) {
    let email = email.trimmingCharacters(in: .whitespaces).lowercased()
    let username = username.trimmingCharacters(in: .whitespaces).lowercased()
    if let problem = AccountRules.usernameProblem(username) { status = problem; return }
    guard AccountRules.emailLooksValid(email) else { status = "Enter a valid email address."; return }
    if let problem = AccountRules.passwordProblem(password) { status = problem; return }
    run {
      let (available, _) = try await self.call("POST", "/rest/v1/rpc/username_available", body: ["name": username], signed: false)
      guard String(data: available, encoding: .utf8)?.contains("true") == true else {
        throw CloudError(message: "@\(username) is taken. Try another.")
      }
      let (data, code) = try await self.call(
        "POST", "/auth/v1/signup", body: ["email": email, "password": password, "data": ["username": username]], signed: false)
      guard code == 200 else { throw Self.error(data, fallback: "Could not create your account.") }
      let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
      if row["access_token"] != nil {
        try await self.adopt(row)
      } else {
        self.pending = (email, password)
        self.phase = .confirmEmail(email)
        self.status = ""
      }
    }
  }
  /// After the confirmation link, sign in with what was just entered.
  func continueAfterConfirming() {
    guard let pending else { phase = .signedOut; return }
    signIn(email: pending.email, password: pending.password)
  }
  func signIn(email: String, password: String) {
    let email = email.trimmingCharacters(in: .whitespaces).lowercased()
    guard AccountRules.emailLooksValid(email), !password.isEmpty else { status = "Enter your email and password."; return }
    run {
      let (data, code) = try await self.call(
        "POST", "/auth/v1/token?grant_type=password", body: ["email": email, "password": password], signed: false)
      guard code == 200 else {
        let error = Self.error(data, fallback: "Email or password is incorrect.")
        if error.message.localizedCaseInsensitiveContains("not confirmed") {
          self.pending = (email, password)
          self.phase = .confirmEmail(email)
          return
        }
        throw error
      }
      try await self.adopt(try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:])
    }
  }
  func resetPassword(email: String) {
    let email = email.trimmingCharacters(in: .whitespaces).lowercased()
    guard AccountRules.emailLooksValid(email) else { status = "Enter your email first."; return }
    run {
      _ = try await self.call("POST", "/auth/v1/recover", body: ["email": email], signed: false)
      self.status = "If that email has an account, a reset link is on its way."
    }
  }
  func signOut() {
    let token = session?.access
    Task { if let token { _ = try? await self.call("POST", "/auth/v1/logout?scope=local", token: token) } }
    keychain.delete()
    session = nil
    profile = nil
    mfaEnabled = false
    enrollment = nil
    UserDefaults.standard.removeObject(forKey: "accountProfile")
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    phase = .signedOut
    status = ""
  }

  // MARK: Two-factor authentication (authenticator app, TOTP)

  func verifySignInCode(_ code: String) {
    guard case .needsCode(let factor) = phase else { return }
    run { try await self.verify(factor: factor, code: code) }
  }
  func startTwoFactor() {
    run {
      // Clear any unfinished setup first so a new QR code is always valid.
      for factor in try await self.factors() where factor.status != "verified" {
        _ = try? await self.call("DELETE", "/auth/v1/factors/\(factor.id)")
      }
      let (data, code) = try await self.call(
        "POST", "/auth/v1/factors", body: ["factor_type": "totp", "friendly_name": "Molt \(Int(Date().timeIntervalSince1970))"])
      guard code == 200, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let id = row["id"] as? String, let totp = row["totp"] as? [String: Any],
        let secret = totp["secret"] as? String, let uri = totp["uri"] as? String
      else { throw Self.error(data, fallback: "Could not start two-factor setup.") }
      self.enrollment = Enrollment(factor: id, secret: secret, uri: uri)
    }
  }
  func confirmTwoFactor(_ code: String) {
    guard let enrollment else { return }
    run {
      try await self.verify(factor: enrollment.factor, code: code)
      self.enrollment = nil
      self.status = "Two-factor authentication is on."
    }
  }
  func cancelTwoFactor() {
    guard let enrollment else { return }
    self.enrollment = nil
    Task { _ = try? await call("DELETE", "/auth/v1/factors/\(enrollment.factor)") }
  }
  func disableTwoFactor() {
    run {
      for factor in try await self.factors() where factor.status == "verified" {
        let (data, code) = try await self.call("DELETE", "/auth/v1/factors/\(factor.id)")
        guard code == 200 else { throw Self.error(data, fallback: "Sign in again with your code to turn this off.") }
      }
      self.mfaEnabled = false
      self.scheduleReminder()
      self.status = "Two-factor authentication is off."
    }
  }

  // MARK: Profile

  func updateProfile(moltName: String? = nil, palette: String? = nil, discoverable: Bool? = nil) {
    guard let id = userID, var next = profile else { return }
    var body: [String: Any] = [:]
    if let moltName { body["molt_name"] = String(moltName.prefix(40)); next.moltName = String(moltName.prefix(40)) }
    if let palette { body["palette"] = palette; next.palette = palette }
    if let discoverable { body["discoverable"] = discoverable; next.discoverable = discoverable }
    guard !body.isEmpty, next != profile else { return }
    setProfile(next)
    guard !preview else { return }
    Task { _ = try? await call("PATCH", "/rest/v1/profiles?id=eq.\(id.uuidString)", body: body) }
  }
  func reloadProfile() {
    guard !preview else { return }
    Task { try? await loadProfile() }
  }

  // MARK: Requests

  /// Calls the Supabase API. Signed requests carry the user's token, refreshed when needed.
  func call(_ method: String, _ path: String, body: Any? = nil, signed: Bool = true, token: String? = nil, prefer: String? = nil) async throws -> (Data, Int) {
    var request = URLRequest(url: URL(string: MoltCloud.url.absoluteString + path)!)
    request.httpMethod = method
    request.timeoutInterval = 20
    request.setValue(MoltCloud.key, forHTTPHeaderField: "apikey")
    if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
    if signed {
      var bearer = token
      if bearer == nil { bearer = try await accessToken() }
      guard let bearer else { throw CloudError(message: "Sign in to continue.") }
      request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    } catch {
      throw CloudError(message: "Molt can't reach its server. Check your connection.")
    }
  }
  func accessToken() async throws -> String? {
    guard var current = session else { return nil }
    if current.expires > Date().addingTimeInterval(60) { return current.access }
    let (data, code) = try await call(
      "POST", "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refresh], signed: false)
    guard code == 200, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let access = row["access_token"] as? String, let refresh = row["refresh_token"] as? String
    else {
      // A rejected refresh token means the session was revoked; ask to sign in again.
      if (400..<500).contains(code) { signOut() }
      throw CloudError(message: "Your session ended. Sign in again.")
    }
    current.access = access
    current.refresh = refresh
    current.expires = Date().addingTimeInterval(Double(row["expires_in"] as? Int ?? 3600))
    session = current
    keychain.write(current)
    return access
  }

  // MARK: Internals

  private func run(_ work: @escaping () async throws -> Void) {
    guard !busy else { return }
    busy = true
    status = ""
    Task {
      defer { self.busy = false }
      do { try await work() } catch { self.status = error.localizedDescription }
    }
  }
  private func restore() async {
    do {
      _ = try await accessToken()
      try await refreshFactors()
      try await loadProfile()
    } catch {}
  }
  /// Stores a new session, then asks for a code if this account uses two-factor authentication.
  private func adopt(_ row: [String: Any]) async throws {
    guard let access = row["access_token"] as? String, let refresh = row["refresh_token"] as? String,
      let user = (row["user"] as? [String: Any])?["id"] as? String, let id = UUID(uuidString: user)
    else { throw CloudError(message: "The server sent an unexpected reply.") }
    let next = Session(access: access, refresh: refresh, expires: Date().addingTimeInterval(Double(row["expires_in"] as? Int ?? 3600)), user: id)
    session = next
    keychain.write(next)
    pending = nil
    let verified = try await factors().filter { $0.status == "verified" }
    mfaEnabled = !verified.isEmpty
    if let factor = verified.first, AccountRules.claims(access)?["aal"] as? String != "aal2" {
      phase = .needsCode(factor.id)
      return
    }
    try await loadProfile()
    phase = .signedIn
    scheduleReminder()
  }
  private func verify(factor: String, code: String) async throws {
    let digits = code.filter(\.isNumber)
    guard digits.count == 6 else { throw CloudError(message: "Enter the 6-digit code from your authenticator app.") }
    let (challenge, challengeCode) = try await call("POST", "/auth/v1/factors/\(factor)/challenge")
    guard challengeCode == 200, let id = (try JSONSerialization.jsonObject(with: challenge) as? [String: Any])?["id"] as? String
    else { throw Self.error(challenge, fallback: "Could not check the code.") }
    let (data, verifyCode) = try await call("POST", "/auth/v1/factors/\(factor)/verify", body: ["challenge_id": id, "code": digits])
    guard verifyCode == 200, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw Self.error(data, fallback: "That code didn't work. Try the newest one.")
    }
    if let access = row["access_token"] as? String, let refresh = row["refresh_token"] as? String, let user = session?.user {
      let next = Session(access: access, refresh: refresh, expires: Date().addingTimeInterval(Double(row["expires_in"] as? Int ?? 3600)), user: user)
      session = next
      keychain.write(next)
    }
    mfaEnabled = true
    try await loadProfile()
    phase = .signedIn
    scheduleReminder()
  }
  private struct Factor { var id: String; var status: String }
  private func factors() async throws -> [Factor] {
    let (data, code) = try await call("GET", "/auth/v1/user")
    guard code == 200, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return (row["factors"] as? [[String: Any]] ?? []).compactMap { factor in
      guard factor["factor_type"] as? String == "totp", let id = factor["id"] as? String else { return nil }
      return Factor(id: id, status: factor["status"] as? String ?? "")
    }
  }
  private func refreshFactors() async throws {
    mfaEnabled = try await factors().contains { $0.status == "verified" }
    scheduleReminder()
  }
  private func loadProfile() async throws {
    guard let id = session?.user else { return }
    let (data, code) = try await call("GET", "/rest/v1/profiles?id=eq.\(id.uuidString)&select=*")
    guard code == 200, let profile = try JSONDecoder().decode([Profile].self, from: data).first else { return }
    setProfile(profile)
  }
  private func setProfile(_ value: Profile) {
    profile = value
    if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "accountProfile") }
  }
  /// While two-factor authentication is off, a gentle reminder arrives once a week.
  private func scheduleReminder() {
    guard Bundle.main.bundleURL.pathExtension == "app", !preview else { return }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    guard !mfaEnabled, session != nil else { return }
    center.requestAuthorization(options: [.alert]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Keep your Molt account safe"
      content.body = "Turn on two-factor authentication in Molt's Settings. It takes a minute."
      var when = DateComponents()
      when.weekday = 2
      when.hour = 10
      center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }
  }
  private static func error(_ data: Data, fallback: String) -> CloudError {
    let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let text = row?["msg"] as? String ?? row?["message"] as? String ?? row?["error_description"] as? String
    return CloudError(message: text.map { $0.hasSuffix(".") ? $0 : $0 + "." } ?? fallback)
  }
}
