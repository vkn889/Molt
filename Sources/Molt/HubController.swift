import AppKit
import MoltCore
import SwiftUI

@MainActor final class HubController: ObservableObject {
  struct Saved: Codable {
    var cards = ["Today", "Music", "Weather", "Mac", "Scenes", "Usage"]
    var scenes: [HubScene] = []
    var playlists: [String] = []
    var wallpapers: [String] = []
    var reports: [String: String] = [:]
    var cliIntervals: [ActivityInterval] = []
    var usageConsent = false
    var inputRate = 0.0, outputRate = 0.0, cacheRate = 0.0
    var morning = true
  }
  @Published var saved = Saved()
  @Published var status = "Your little Mac hub."
  let media = NowPlayingController()
  @Published var city = ""
  @Published var places: [Place] = []
  @Published var weather = "Choose a city to check the weather."
  @Published var busy = false
  @Published var tokens: [TokenRecord] = []
  @Published var importStatus = "Import is off. No AI logs are read."
  @Published var importBusy = false
  @Published var pendingScene: HubScene?
  private var lastSample = Date()
  private var lastTools: Set<String> = []
  private var sampling = false
  private var originalWallpapers: [(NSScreen, URL)] = []
  private let url: URL
  private var storageBlocked = false
  init(directory: URL) {
    url = directory.appendingPathComponent("hub.json")
    if FileManager.default.fileExists(atPath: url.path) {
      do { saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)) }
      catch { storageBlocked = true; status = "Hub data could not load. Original file preserved." }
    }
  }
  func save() {
    guard !storageBlocked else { return }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(saved).write(to: url, options: .atomic)
    } catch { status = "Could not save hub preferences: \(error.localizedDescription)" }
  }
  func moveCard(_ card: String, offset: Int) {
    guard let index = saved.cards.firstIndex(of: card), saved.cards.indices.contains(index + offset) else { return }
    saved.cards.swapAt(index, index + offset); save()
  }
  func toggleCard(_ card: String) {
    if saved.cards.contains(card) { saved.cards.removeAll { $0 == card } } else { saved.cards.append(card) }; save()
  }
  private func runScript(_ source: String, completion: @escaping (String) -> Void) {
    guard !busy else { return }; busy = true
    // Runs only after an explicit control change. macOS manages Automation permission.
    DispatchQueue.global(qos: .userInitiated).async {
      var error: NSDictionary?
      let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
      let text = error.map { "Automation unavailable: \($0[NSAppleScript.errorMessage] ?? "Permission denied")" } ?? value?.stringValue ?? ""
      Task { @MainActor in self.busy = false; completion(text) }
    }
  }
  func readVolume(_ completion: @escaping (Int) -> Void) {
    runScript("output volume of (get volume settings)") { if let value = Int($0) { completion(value) } }
  }
  func volume(_ value: Int) {
    runScript("set volume output volume \(min(100, max(0, value)))") { self.status = $0.isEmpty ? "Volume changed." : $0 }
  }
  func addPlaylist(_ value: String) {
    guard let url = URL(string: value), url.scheme == "https", ["open.spotify.com", "music.apple.com"].contains(url.host ?? ""), url.user == nil, url.password == nil else {
      status = "Use a Spotify or Apple Music HTTPS playlist link."; return
    }
    if !saved.playlists.contains(value) { saved.playlists.append(value); save() }
  }
  func openPlaylist(_ value: String) {
    guard saved.playlists.contains(value), let url = URL(string: value) else { return }
    status = NSWorkspace.shared.open(url) ? "Playlist opened. Playback is controlled by your music service." : "Could not open playlist."
  }
  func chooseWallpaper() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic]; panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url, !saved.wallpapers.contains(url.path) { saved.wallpapers.append(url.path); save() }
  }
  func applyWallpaper(_ path: String) {
    guard saved.wallpapers.contains(path) else { return }
    do {
      originalWallpapers = NSScreen.screens.compactMap { screen in NSWorkspace.shared.desktopImageURL(for: screen).map { (screen, $0) } }
      for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:]) }
      status = "Wallpaper applied to current desktops. Restore is available this session."
    } catch { status = "Wallpaper failed: \(error.localizedDescription)" }
  }
  func restoreWallpaper() {
    do {
      for (screen, url) in originalWallpapers { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
      status = originalWallpapers.isEmpty ? "No wallpaper change to restore." : "Previous wallpaper restored."
      originalWallpapers = []
    } catch { status = error.localizedDescription }
  }
  func dock(_ key: String, value: String) {
    let valid: [String: [String]] = ["orientation": ["left", "bottom", "right"], "autohide": ["true", "false"], "tilesize": ["36", "48", "64", "80"]]
    guard valid[key]?.contains(value) == true, !busy else { return }
    busy = true
    Task {
      let succeeded = await Task.detached {
        let write = Process(); write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        let type = key == "orientation" ? "-string" : key == "autohide" ? "-bool" : "-int"
        write.arguments = ["write", "com.apple.dock", key, type, value]
        do { try write.run(); write.waitUntilExit(); guard write.terminationStatus == 0 else { return false }
          let restart = Process(); restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); restart.arguments = ["Dock"]
          try restart.run(); restart.waitUntilExit(); return restart.terminationStatus == 0
        } catch { return false }
      }.value
      status = succeeded ? "Dock preference applied. The Dock restarted to refresh." : "Dock change failed. Use System Settings instead."
      busy = false
    }
  }
  func chooseApps(for scene: inout HubScene) {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true; panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if panel.runModal() == .OK { scene.apps = Array(panel.urls.prefix(6)).map(\.path) }
  }
  func runScene(_ scene: HubScene, controller: PetController) {
    var results: [String] = []
    if !scene.wallpaper.isEmpty { applyWallpaper(scene.wallpaper); results.append(status) }
    if !scene.playlist.isEmpty { openPlaylist(scene.playlist); results.append(status) }
    for path in scene.apps {
      let url = URL(fileURLWithPath: path)
      if url.pathExtension == "app" { results.append(NSWorkspace.shared.open(url) ? "Opened \(url.lastPathComponent)." : "Could not open \(url.lastPathComponent).") }
    }
    if scene.minutes > 0 {
      if controller.organization.sessions.contains(where: { $0.finished == nil }) { results.append("Existing focus session kept.") }
      else { controller.focus(minutes: min(180, scene.minutes)); results.append("Focus requested: \(scene.minutes) minutes.") }
    }
    status = results.joined(separator: "\n"); pendingScene = nil
  }
  struct Place: Decodable, Identifiable {
    var id: Int; var name: String; var latitude: Double; var longitude: Double; var country: String?
  }
  func findCity() {
    guard !busy, !city.isEmpty else { return }; busy = true
    Task {
      defer { busy = false }
      do {
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [.init(name: "name", value: String(city.prefix(100))), .init(name: "count", value: "5")]
        let data = try await fetch(parts.url!)
        struct Response: Decodable { var results: [Place]? }
        places = try JSONDecoder().decode(Response.self, from: data).results ?? []
        if places.isEmpty { weather = "No matching city found." }
      } catch { weather = error.localizedDescription }
    }
  }
  func loadWeather(_ place: Place) {
    guard !busy else { return }; busy = true
    Task {
      defer { busy = false }
      do {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(place.latitude)&longitude=\(place.longitude)&current=temperature_2m,apparent_temperature,weather_code&timezone=auto")!
        let data = try await fetch(url)
        struct Response: Decodable { struct Current: Decodable { var temperature_2m: Double; var apparent_temperature: Double; var weather_code: Int }; var current: Current }
        let value = try JSONDecoder().decode(Response.self, from: data).current
        weather = "\(place.name): \(value.temperature_2m)°C, feels like \(value.apparent_temperature)°C · \(weatherDescription(value.weather_code)) · updated \(Date().formatted(date: .omitted, time: .shortened))"
      } catch { weather = "Weather unavailable: \(error.localizedDescription)" }
    }
  }
  private func weatherDescription(_ code: Int) -> String {
    switch code {
    case 0: return "Clear skies"
    case 1...3: return "Partly cloudy / overcast"
    case 45, 48: return "Fog"
    case 51...67: return "Drizzle or rain"
    case 71...77: return "Snow"
    case 80...82: return "Rain showers"
    case 85, 86: return "Snow showers"
    case 95...99: return "Thunderstorms"
    default: return "Conditions unavailable"
    }
  }
  private func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url); request.timeoutInterval = 15
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw MoltError.invalid("Weather service unavailable.") }
    return data
  }
}

extension HubController {
  func setUsageConsent(_ enabled: Bool) {
    saved.usageConsent = enabled; lastTools = []; lastSample = Date(); save()
    if enabled {
      let key = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
      saved.reports.removeValue(forKey: key); save(); importUsage()
    } else { tokens = []; importStatus = "AI usage import paused." }
  }
  func forgetUsage() {
    saved.usageConsent = false; saved.cliIntervals = []; saved.reports = [:]; tokens = []; lastTools = []
    save(); importStatus = "Molt's AI usage and reports cleared. Source logs were not changed."
  }
  func importUsage(reportIntervals: [ActivityInterval]? = nil) {
    guard saved.usageConsent, !importBusy else { return }
    importBusy = true; importStatus = "Reading local numeric usage records…"
    Task {
      let result = await Task.detached(priority: .utility) { () -> ([TokenRecord], Bool) in
        let home = FileManager.default.homeDirectoryForCurrentUser
        var all: [String: TokenRecord] = [:]; var bytes = 0; var files = 0; var partial = false
        for (tool, relative) in [("Claude Code", ".claude/projects"), ("Codex", ".codex/sessions")] {
          let root = home.appendingPathComponent(relative)
          guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
          for case let file as URL in enumerator {
            if files >= 500 || bytes >= 64_000_000 { partial = true; break }
            guard file.pathExtension == "jsonl", let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
            guard let size = values.fileSize, size <= 8_000_000, bytes + size <= 64_000_000 else { partial = true; continue }
            guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else { continue }
            bytes += data.count; files += 1
            for record in LocalUsageParser.records(lines: text.components(separatedBy: .newlines), tool: tool, source: file.lastPathComponent) where record.date > Date().addingTimeInterval(-30 * 86400) {
              all[tool + record.id] = record
            }
          }
        }
        return (Array(all.values), partial)
      }.value
      if saved.usageConsent {
        tokens = result.0
        importStatus = "Imported \(tokens.count) numeric records. \(result.1 ? "Partial scan: size/file limit reached." : "Standard local session folders scanned.") No prompts retained. Costs are estimates, not subscription charges."
      }
      importBusy = false
      if let reportIntervals, saved.usageConsent { makeMorningReport(reportIntervals) }
    }
  }
  func tickUsage(_ intervals: [ActivityInterval]) {
    let reportKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
    if saved.morning, Calendar.current.component(.hour, from: Date()) >= 7, saved.reports[reportKey] == nil {
      if saved.usageConsent { importUsage(reportIntervals: intervals) } else { makeMorningReport(intervals) }
    }
    guard saved.usageConsent, !sampling else { return }
    sampling = true
    let now = Date(), start = lastSample, old = lastTools
    lastSample = now
    Task {
      let tools = await Task.detached { () -> Set<String> in
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-axo", "comm="]
        let pipe = Pipe(); process.standardOutput = pipe
        do {
          try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
          var found: Set<String> = []
          for path in String(decoding: data, as: UTF8.self).components(separatedBy: .newlines) {
            let name = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespaces)).lastPathComponent.lowercased()
            if name == "claude" { found.insert("Claude Code process") }
            if name == "codex", !path.contains(".app/") { found.insert("Codex CLI process") }
          }
          return found
        } catch { return [] }
      }.value
      defer { sampling = false }
      guard saved.usageConsent else { return }
      if now.timeIntervalSince(start) <= 90 {
        for tool in old.intersection(tools) {
          saved.cliIntervals.append(ActivityInterval(app: tool, name: tool, start: start, end: now, category: "AI process running"))
        }
      }
      lastTools = tools
      saved.cliIntervals.removeAll { $0.end < now.addingTimeInterval(-30 * 86400) }
      save()
    }
  }
  func makeMorningReport(_ intervals: [ActivityInterval]) {
    guard saved.morning, Calendar.current.component(.hour, from: Date()) >= 7 else { return }
    let today = Calendar.current.startOfDay(for: Date())
    let key = ISO8601DateFormatter().string(from: today)
    guard saved.reports[key] == nil,
      let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else { return }
    let appTimes = UsageMath.seconds(intervals, from: yesterday, to: today)
    let cliTimes = UsageMath.seconds(saved.cliIntervals, from: yesterday, to: today)
    let records = tokens.filter { $0.date >= yesterday && $0.date < today }
    let cost = UsageMath.estimate(records, inputRate: saved.inputRate, outputRate: saved.outputRate, cacheRate: saved.cacheRate)
    var report = "Good morning! Yesterday's observed foreground time: \(Int(appTimes.values.reduce(0,+) / 60)) min.\n"
    report += appTimes.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key): \(Int($0.value / 60)) min" }.joined(separator: "\n")
    report += "\nAI processes running (may overlap): " + cliTimes.map { "\($0.key): \(Int($0.value / 60)) min" }.joined(separator: ", ")
    report += "\nImported tokens: \(records.reduce(0) { $0 + $1.input + $1.output + $1.cached }). Estimated cost: \(cost.map { String(format: "$%.4f", $0) } ?? "unavailable")."
    report += "\nOnly time observed while Molt ran is included. Missing imports are not proof of zero usage."
    saved.reports[key] = report
    for key in saved.reports.keys.sorted().dropLast(30) { saved.reports.removeValue(forKey: key) }
    save()
  }
}
