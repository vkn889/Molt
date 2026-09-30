import AppKit
import Combine
import SwiftUI

/// Follows Spotify and Apple Music automatically. Track changes arrive through the players'
/// own distributed notifications; AppleScript is used only for position, artwork and controls,
/// and only against a player that is already running, so Molt never launches one by itself.
@MainActor final class NowPlayingController: ObservableObject {
  enum Player: String, CaseIterable {
    case spotify = "Spotify", music = "Music"
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var notification: String {
      self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"
    }
    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
  }
  struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
  }
  @Published private(set) var player: Player?
  @Published private(set) var track: Track?
  @Published private(set) var isPlaying = false
  @Published private(set) var artwork: NSImage?
  @Published private(set) var position: Double = 0
  @Published private(set) var positionDate = Date()
  @Published private(set) var permissionNeeded = false
  /// True while the notch is open; position is polled only then.
  var active = false {
    didSet {
      guard active != oldValue else { return }
      poll?.invalidate()
      poll = nil
      guard active else { return }
      refresh()
      poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, self.player != nil else { return }
          self.refresh()
        }
      }
    }
  }
  private let queue = DispatchQueue(label: "app.molt.now-playing", qos: .userInitiated)
  private var poll: Timer?
  private var artworkKey: String?
  private var refreshing = false
  private var observers: [NSObjectProtocol] = []

  init() {
    let distributed = DistributedNotificationCenter.default()
    for candidate in Player.allCases {
      observers.append(
        distributed.addObserver(forName: .init(candidate.notification), object: nil, queue: .main) {
          [weak self] note in
          let info = note.userInfo ?? [:]
          Task { @MainActor [weak self] in self?.received(info, from: candidate) }
        })
    }
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
      ) { [weak self] note in
        let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        Task { @MainActor [weak self] in
          guard let self, let player = self.player, id == player.bundleID else { return }
          self.clear()
          self.refresh()
        }
      })
  }

  var appIcon: NSImage? {
    guard let player, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
  func elapsed(at date: Date) -> Double {
    guard let track else { return 0 }
    let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
    return track.duration > 0 ? min(track.duration, max(0, value)) : max(0, value)
  }

  // MARK: Controls

  func playPause() {
    guard let player else { openPreferredPlayer(); return }
    isPlaying.toggle()
    position = elapsed(at: Date())
    positionDate = Date()
    command("playpause", on: player)
  }
  func next() { if let player { command("next track", on: player) } }
  func previous() { if let player { command("previous track", on: player) } }
  func seek(to seconds: Double) {
    guard let player, let track else { return }
    let target = min(max(0, seconds), max(0, track.duration - 1))
    position = target
    positionDate = Date()
    command(String(format: "set player position to %.2f", locale: Locale(identifier: "en_US_POSIX"), target), on: player)
  }
  func openPlayerApp() {
    let bundleID = (player ?? .music).bundleID
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init())
  }
  func openAutomationSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
      NSWorkspace.shared.open(url)
    }
  }
  private func openPreferredPlayer() {
    let preferred = Player.allCases.first {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
    }
    guard let preferred, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferred.bundleID)
    else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init())
  }
  private func command(_ verb: String, on player: Player) {
    let allowed = ["playpause", "next track", "previous track"]
    guard allowed.contains(verb) || verb.hasPrefix("set player position to ") else { return }
    guard player.isRunning else { clear(); return }
    let source = "tell application id \"\(player.bundleID)\" to \(verb)"
    queue.async {
      let result = Self.run(source)
      Task { @MainActor in
        if case .failure(let failure) = result, failure.permission { self.permissionNeeded = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        self.refresh()
      }
    }
  }

  // MARK: State

  private func received(_ info: [AnyHashable: Any], from source: Player) {
    let state = (info["Player State"] as? String)?.lowercased() ?? ""
    if state == "stopped" || !source.isRunning {
      if player == source { clear() }
      return
    }
    // A paused player never steals focus from one that is playing.
    if state != "playing", let player, player != source, isPlaying { return }
    let title = info["Name"] as? String ?? ""
    guard !title.isEmpty else { refresh(); return }
    let millis = (info[source == .spotify ? "Duration" : "Total Time"] as? NSNumber)?.doubleValue ?? 0
    player = source
    track = Track(
      title: title, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
      duration: millis / 1000)
    isPlaying = state == "playing"
    if let seconds = (info["Playback Position"] as? NSNumber)?.doubleValue {
      position = seconds
      positionDate = Date()
    }
    refresh()
  }
  private func clear() {
    player = nil
    track = nil
    isPlaying = false
    artwork = nil
    artworkKey = nil
    position = 0
  }
  func refresh() {
    guard !refreshing else { return }
    let running = Player.allCases.filter(\.isRunning)
    guard !running.isEmpty else { clear(); return }
    refreshing = true
    let current = player
    queue.async {
      var snapshots: [(Player, Snapshot)] = []
      var denied = false
      for candidate in running {
        switch Self.run(Self.statusScript(candidate)) {
        case .success(let text): if let snapshot = Snapshot(text) { snapshots.append((candidate, snapshot)) }
        case .failure(let failure): denied = denied || failure.permission
        }
      }
      Task { @MainActor in
        self.refreshing = false
        self.permissionNeeded = denied && snapshots.isEmpty
        let chosen =
          snapshots.first { $0.1.playing }
          ?? snapshots.first { $0.0 == current }
          ?? snapshots.first
        // Without Automation access, keep whatever the players' own notifications reported.
        guard let (source, snapshot) = chosen else {
          if !denied { self.clear() }
          return
        }
        self.apply(snapshot, from: source)
      }
    }
  }
  private func apply(_ snapshot: Snapshot, from source: Player) {
    player = source
    track = snapshot.track
    isPlaying = snapshot.playing
    position = snapshot.position
    positionDate = Date()
    let key = "\(source.rawValue)|\(snapshot.track.title)|\(snapshot.track.album)|\(snapshot.track.artist)"
    guard key != artworkKey else { return }
    artworkKey = key
    artwork = nil
    loadArtwork(source, remote: snapshot.artworkURL, key: key)
  }
  private func loadArtwork(_ source: Player, remote: String?, key: String) {
    if source == .spotify {
      guard let remote, let url = URL(string: remote), url.scheme == "https",
        let host = url.host, host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com")
      else { return }
      Task {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request), data.count < 4_000_000,
          let image = NSImage(data: data), artworkKey == key
        else { return }
        artwork = image
      }
    } else {
      queue.async {
        var error: NSDictionary?
        let script = NSAppleScript(
          source: "tell application id \"com.apple.Music\"\ntry\nreturn raw data of artwork 1 of current track\non error\nreturn \"\"\nend try\nend tell")
        let descriptor = script?.executeAndReturnError(&error)
        let data = descriptor.flatMap { $0.descriptorType == typeUnicodeText ? nil : $0.data }
        Task { @MainActor in
          guard self.artworkKey == key, let data, let image = NSImage(data: data) else { return }
          self.artwork = image
        }
      }
    }
  }

  // MARK: Scripting

  private struct Snapshot {
    var track: Track
    var playing: Bool
    var position: Double
    var artworkURL: String?
    init?(_ text: String) {
      let parts = text.components(separatedBy: "\t")
      guard parts.count >= 6, parts[0] != "stopped", !parts[1].isEmpty else { return nil }
      func number(_ value: String) -> Double { Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0 }
      track = Track(title: parts[1], artist: parts[2], album: parts[3], duration: number(parts[4]))
      playing = parts[0] == "playing"
      position = number(parts[5])
      artworkURL = parts.count > 6 && !parts[6].isEmpty ? parts[6] : nil
    }
  }
  nonisolated private static func statusScript(_ player: Player) -> String {
    let duration = player == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
    let artwork = player == .spotify ? " & tab & (artwork url of t)" : ""
    return """
      tell application id "\(player.bundleID)"
      if player state is stopped then return "stopped"
      set t to current track
      set s to "paused"
      if player state is playing then set s to "playing"
      return s & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & \(duration) & tab & (player position)\(artwork)
      end tell
      """
  }
  /// Failure carries whether macOS Automation permission was refused.
  nonisolated private static func run(_ source: String) -> Result<String, ScriptFailure> {
    var error: NSDictionary?
    let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error {
      let code = error[NSAppleScript.errorNumber] as? Int ?? 0
      return .failure(ScriptFailure(permission: code == -1743 || code == -10004))
    }
    return .success(value?.stringValue ?? "")
  }
  struct ScriptFailure: Error { var permission: Bool }
}
