import AppKit
import CryptoKit
import Network
import Security
import SwiftUI

struct Playlist: Identifiable, Equatable {
  enum Source: String { case spotify = "Spotify", appleMusic = "Apple Music" }
  var id: String
  var source: Source
  var name: String
  var detail: String
  /// A Spotify URI, or an Apple Music persistent ID.
  var reference: String
  var imageURL: URL?
}

/// Both music services behind one shelf. Playback runs in the background; Molt launches a
/// player hidden when one is needed, so you never have to switch to it.
@MainActor final class MusicLibrary: ObservableObject {
  let spotify = SpotifyAccount()
  let appleMusic = AppleMusicLibrary()
  @Published var source: Playlist.Source {
    didSet { UserDefaults.standard.set(source.rawValue, forKey: "librarySource") }
  }
  init() {
    source = Playlist.Source(rawValue: UserDefaults.standard.string(forKey: "librarySource") ?? "") ?? .spotify
  }
  func refresh() {
    if spotify.connected { spotify.loadPlaylists() }
    if appleMusic.connected { appleMusic.load() }
  }
  func play(_ playlist: Playlist) {
    switch playlist.source {
    case .spotify: spotify.play(playlist)
    case .appleMusic: appleMusic.play(playlist)
    }
  }
}

enum BackgroundApp {
  /// Starts an app without bringing it forward, then waits briefly for it to accept scripting.
  static func ensureRunning(_ bundleID: String) async -> Bool {
    if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return true }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.hides = true
    configuration.addsToRecentItems = false
    guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil else { return false }
    try? await Task.sleep(nanoseconds: 2_500_000_000)
    return true
  }
  static func isInstalled(_ bundleID: String) -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }
  static func script(_ source: String) async -> (String?, Int?) {
    await Task.detached(priority: .userInitiated) { () -> (String?, Int?) in
      var error: NSDictionary?
      let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
      if let error { return (nil, error[NSAppleScript.errorNumber] as? Int) }
      return (value?.stringValue ?? "", nil)
    }.value
  }
}

// MARK: Spotify

@MainActor final class SpotifyAccount: ObservableObject {
  struct Tokens: Codable { var access: String; var refresh: String; var expires: Date }
  struct Remote {
    var title: String, artist: String, album: String
    var duration: Double, position: Double, playing: Bool
    var artwork: URL?
  }
  static let port: UInt16 = 43821
  static let redirect = "http://127.0.0.1:43821/callback"
  static let scopes = "playlist-read-private playlist-read-collaborative user-library-read user-read-playback-state user-modify-playback-state user-read-currently-playing"
  @Published var clientID: String { didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespaces), forKey: "spotifyClientID") } }
  @Published private(set) var connected = false
  @Published private(set) var connecting = false
  @Published private(set) var userName: String?
  @Published private(set) var playlists: [Playlist] = []
  @Published private(set) var loading = false
  @Published var status = ""
  private var tokens: Tokens?
  private var listener: NWListener?
  private var verifier = ""
  private var state = ""

  init() {
    clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
    tokens = Keychain.read()
    connected = tokens != nil
    userName = UserDefaults.standard.string(forKey: "spotifyUser")
  }

  func connect() {
    let id = clientID.trimmingCharacters(in: .whitespaces)
    guard id.count >= 16, id.allSatisfy({ $0.isLetter || $0.isNumber }) else {
      status = "Paste the Client ID from your Spotify developer app first."
      return
    }
    verifier = Self.random(64)
    state = Self.random(24)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    do { try listen() } catch {
      status = "Could not start the sign-in listener on port \(Self.port)."
      return
    }
    var parts = URLComponents(string: "https://accounts.spotify.com/authorize")!
    parts.queryItems = [
      .init(name: "client_id", value: id), .init(name: "response_type", value: "code"),
      .init(name: "redirect_uri", value: Self.redirect), .init(name: "scope", value: Self.scopes),
      .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
      .init(name: "state", value: state),
    ]
    connecting = true
    status = "Finish signing in with Spotify in your browser."
    NSWorkspace.shared.open(parts.url!)
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 180_000_000_000)
      guard let self, self.connecting else { return }
      self.stopListening()
      self.status = "Spotify sign-in timed out. Try again."
    }
  }
  func disconnect() {
    Keychain.delete()
    tokens = nil
    connected = false
    playlists = []
    userName = nil
    UserDefaults.standard.removeObject(forKey: "spotifyUser")
    status = ""
  }

  func loadPlaylists() {
    guard connected, !loading else { return }
    loading = true
    Task {
      defer { loading = false }
      do {
        if userName == nil, let me = try await json("GET", "/v1/me") {
          userName = me["display_name"] as? String ?? me["id"] as? String
          UserDefaults.standard.set(userName, forKey: "spotifyUser")
        }
        var found: [Playlist] = []
        var next: String? = "/v1/me/playlists?limit=50"
        while let path = next, found.count < 200 {
          guard let page = try await json("GET", path) else { break }
          for item in page["items"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String, let uri = item["uri"] as? String else { continue }
            let images = item["images"] as? [[String: Any]] ?? []
            let count = ((item["tracks"] as? [String: Any])?["total"] as? Int) ?? 0
            found.append(Playlist(
              id: "spotify:" + id, source: .spotify, name: item["name"] as? String ?? "Playlist",
              detail: "\(count) songs", reference: uri,
              imageURL: (images.last(where: { ($0["width"] as? Int ?? 0) >= 200 }) ?? images.first)?["url"].flatMap { $0 as? String }.flatMap(URL.init(string:))))
          }
          next = (page["next"] as? String).map { $0.replacingOccurrences(of: "https://api.spotify.com", with: "") }
        }
        playlists = found
        status = found.isEmpty ? "No playlists in this Spotify account yet." : ""
      } catch { status = (error as? SpotifyError)?.message ?? "Spotify is unavailable right now." }
    }
  }

  func play(_ playlist: Playlist) {
    guard playlist.reference.range(of: "^spotify:[a-z]+:[A-Za-z0-9]+$", options: .regularExpression) != nil else { return }
    Task {
      // The desktop app plays in the background when installed; otherwise use any active device.
      if BackgroundApp.isInstalled("com.spotify.client") {
        guard await BackgroundApp.ensureRunning("com.spotify.client") else { status = "Could not start Spotify."; return }
        let (_, error) = await BackgroundApp.script("tell application id \"com.spotify.client\" to play track \"\(playlist.reference)\"")
        if error == nil { status = ""; return }
      }
      do {
        let body = try JSONSerialization.data(withJSONObject: ["context_uri": playlist.reference])
        let (_, code) = try await request("PUT", "/v1/me/player/play", body: body)
        status = code == 404 ? "Open Spotify on any device, then choose the playlist again." : code == 403 ? "Remote playback needs Spotify Premium." : ""
      } catch { status = (error as? SpotifyError)?.message ?? "Could not start playback." }
    }
  }

  // MARK: Now playing on other devices

  func currentlyPlaying() async -> Remote? {
    guard connected, let row = try? await json("GET", "/v1/me/player/currently-playing"),
      let item = row["item"] as? [String: Any]
    else { return nil }
    let album = item["album"] as? [String: Any]
    let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    let images = album?["images"] as? [[String: Any]] ?? []
    return Remote(
      title: item["name"] as? String ?? "", artist: artists.joined(separator: ", "),
      album: album?["name"] as? String ?? "",
      duration: Double(item["duration_ms"] as? Int ?? 0) / 1000,
      position: Double(row["progress_ms"] as? Int ?? 0) / 1000,
      playing: row["is_playing"] as? Bool ?? false,
      artwork: (images.first?["url"] as? String).flatMap(URL.init(string:)))
  }
  func control(_ command: String, seconds: Double = 0) {
    Task {
      switch command {
      case "play": _ = try? await request("PUT", "/v1/me/player/play")
      case "pause": _ = try? await request("PUT", "/v1/me/player/pause")
      case "next": _ = try? await request("POST", "/v1/me/player/next")
      case "previous": _ = try? await request("POST", "/v1/me/player/previous")
      case "seek": _ = try? await request("PUT", "/v1/me/player/seek?position_ms=\(Int(seconds * 1000))")
      default: break
      }
    }
  }

  // MARK: Web API

  struct SpotifyError: Error { var message: String }
  private func json(_ method: String, _ path: String) async throws -> [String: Any]? {
    let (data, code) = try await request(method, path)
    guard code == 200 else { return nil }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
  private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, Int) {
    guard let token = try await accessToken() else { throw SpotifyError(message: "Connect Spotify first.") }
    var request = URLRequest(url: URL(string: "https://api.spotify.com" + path)!)
    request.httpMethod = method
    request.timeoutInterval = 15
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    else if method != "GET" { request.setValue("0", forHTTPHeaderField: "Content-Length") }
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401 { disconnect(); throw SpotifyError(message: "Spotify signed out. Connect again.") }
    return (data, code)
  }
  private func accessToken() async throws -> String? {
    guard let tokens else { return nil }
    if tokens.expires > Date().addingTimeInterval(60) { return tokens.access }
    let fresh = try await exchange([
      "grant_type": "refresh_token", "refresh_token": tokens.refresh, "client_id": clientID,
    ], keeping: tokens.refresh)
    return fresh.access
  }
  private func exchange(_ form: [String: String], keeping refresh: String? = nil) async throws -> Tokens {
    var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var parts = URLComponents()
    parts.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
    request.httpBody = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let access = row["access_token"] as? String
    else {
      if refresh != nil { disconnect() }
      throw SpotifyError(message: "Spotify did not accept the sign-in. Check the Client ID and redirect URI.")
    }
    let value = Tokens(
      access: access, refresh: row["refresh_token"] as? String ?? refresh ?? "",
      expires: Date().addingTimeInterval(Double(row["expires_in"] as? Int ?? 3600)))
    tokens = value
    Keychain.write(value)
    connected = true
    return value
  }

  // MARK: Loopback sign-in

  private func listen() throws {
    stopListening()
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
    parameters.allowLocalEndpointReuse = true
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in
      connection.start(queue: .main)
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
        let line = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
        let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let query = URLComponents(string: "http://127.0.0.1" + target)
        let handled = query?.path == "/callback"
        let page = handled ? "Molt is connected to Spotify. You can close this tab." : "Not found"
        let response = "HTTP/1.1 \(handled ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body style=\"font:15px -apple-system;padding:40px;background:#000;color:#fff\">\(page)</body></html>"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        guard handled else { return }
        let items = query?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let returnedState = items.first { $0.name == "state" }?.value
        Task { @MainActor [weak self] in self?.finish(code: code, state: returnedState) }
      }
    }
    listener.start(queue: .main)
    self.listener = listener
  }
  private func stopListening() {
    listener?.cancel()
    listener = nil
    connecting = false
  }
  private func finish(code: String?, state returned: String?) {
    stopListening()
    guard let code, returned == state else { status = "Spotify sign-in was canceled."; return }
    Task {
      do {
        _ = try await exchange([
          "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirect,
          "client_id": clientID, "code_verifier": verifier,
        ])
        status = ""
        NSApp.activate(ignoringOtherApps: true)
        loadPlaylists()
      } catch { status = (error as? SpotifyError)?.message ?? "Spotify sign-in failed." }
    }
  }
  private static func random(_ length: Int) -> String {
    let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var generator = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
  }

  /// Tokens live in the login keychain, never in preferences.
  private enum Keychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.molt.spotify", kSecAttrAccount as String: "tokens"]
    static func read() -> Tokens? {
      var q = query
      q[kSecReturnData as String] = true
      var item: CFTypeRef?
      guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
      return try? JSONDecoder().decode(Tokens.self, from: data)
    }
    static func write(_ tokens: Tokens) {
      guard let data = try? JSONEncoder().encode(tokens) else { return }
      if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
      }
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
  }
}

private extension Data {
  var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}

// MARK: Apple Music

@MainActor final class AppleMusicLibrary: ObservableObject {
  @Published private(set) var connected = UserDefaults.standard.bool(forKey: "appleMusicConnected")
  @Published private(set) var playlists: [Playlist] = []
  @Published private(set) var covers: [String: NSImage] = [:]
  @Published private(set) var loading = false
  @Published var status = ""
  private var requestedCovers: Set<String> = []

  var installed: Bool { BackgroundApp.isInstalled("com.apple.Music") }
  func connect() {
    connected = true
    UserDefaults.standard.set(true, forKey: "appleMusicConnected")
    load()
  }
  func disconnect() {
    connected = false
    UserDefaults.standard.set(false, forKey: "appleMusicConnected")
    playlists = []
    covers = [:]
    requestedCovers = []
  }
  func load() {
    guard connected, !loading else { return }
    loading = true
    Task {
      defer { loading = false }
      guard await BackgroundApp.ensureRunning("com.apple.Music") else { status = "Apple Music is not installed."; return }
      let (text, error) = await BackgroundApp.script("""
        tell application id "com.apple.Music"
        set out to ""
        repeat with p in (every user playlist whose special kind is none)
        set out to out & (persistent ID of p) & tab & (name of p) & tab & (count of tracks of p) & linefeed
        end repeat
        return out
        end tell
        """)
      if let error {
        status = error == -1743 ? "Allow Molt to control Music in System Settings." : "Could not read your Apple Music library."
        return
      }
      playlists = (text ?? "").components(separatedBy: "\n").compactMap { line in
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 3, !parts[0].isEmpty else { return nil }
        return Playlist(id: "music:" + parts[0], source: .appleMusic, name: parts[1], detail: "\(parts[2]) songs", reference: parts[0])
      }
      status = playlists.isEmpty ? "No playlists in your library yet." : ""
    }
  }
  func loadCover(_ playlist: Playlist) {
    guard !requestedCovers.contains(playlist.reference), Self.safe(playlist.reference) else { return }
    requestedCovers.insert(playlist.reference)
    let id = playlist.reference
    Task {
      let data = await Task.detached(priority: .utility) { () -> Data? in
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application id \"com.apple.Music\"\ntry\nreturn raw data of artwork 1 of track 1 of (first user playlist whose persistent ID is \"\(id)\")\non error\nreturn \"\"\nend try\nend tell")
        let descriptor = script?.executeAndReturnError(&error)
        return descriptor.flatMap { $0.descriptorType == typeUnicodeText ? nil : $0.data }
      }.value
      if let data, let image = NSImage(data: data) { covers[id] = image }
    }
  }
  func play(_ playlist: Playlist) {
    guard Self.safe(playlist.reference) else { return }
    Task {
      guard await BackgroundApp.ensureRunning("com.apple.Music") else { return }
      let (_, error) = await BackgroundApp.script("tell application id \"com.apple.Music\" to play (first user playlist whose persistent ID is \"\(playlist.reference)\")")
      status = error == nil ? "" : "Could not play that playlist."
    }
  }
  /// Persistent IDs are hexadecimal; anything else never reaches a script.
  private static func safe(_ id: String) -> Bool { !id.isEmpty && id.allSatisfy(\.isHexDigit) }
}
