import AppKit
import MoltCore
import SwiftUI

@MainActor final class HubController: ObservableObject {
  /// Unknown keys from earlier versions are ignored; every field is optional so old files load.
  struct Saved: Codable {
    var place: Place?
    var usageConsent: Bool?
    var widgets: [HubWidget]?
    var note: String?
    /// Files and links dropped on Molt to keep.
    var tray: [TrayItem]?
  }
  struct Place: Codable, Identifiable, Equatable {
    var id: Int; var name: String; var latitude: Double; var longitude: Double; var country: String?
  }
  struct Weather: Equatable {
    var temperature: Double
    var code: Int
    var updated: Date
    /// The next 12 hours.
    var hours: [Hour] = []
    struct Hour: Equatable { var date: Date; var temperature: Double; var code: Int; var symbol: String { Weather.symbol(code) } }
    var symbol: String { Self.symbol(code) }
    static func symbol(_ code: Int) -> String {
      switch code {
      case 0: return "sun.max.fill"
      case 1...3: return "cloud.sun.fill"
      case 45, 48: return "cloud.fog.fill"
      case 51...67, 80...82: return "cloud.rain.fill"
      case 71...77, 85, 86: return "cloud.snow.fill"
      case 95...99: return "cloud.bolt.rain.fill"
      default: return "cloud.fill"
      }
    }
    var summary: String {
      switch code {
      case 0: return "Clear"
      case 1...3: return "Partly cloudy"
      case 45, 48: return "Fog"
      case 51...67: return "Rain"
      case 71...77: return "Snow"
      case 80...82: return "Showers"
      case 85, 86: return "Snow showers"
      case 95...99: return "Storms"
      default: return "Unavailable"
      }
    }
  }
  @Published var saved = Saved()
  @Published var status = ""
  @Published var city = ""
  @Published var places: [Place] = []
  @Published var weather: Weather?
  @Published var busy = false
  @Published var editing = false
  /// The widget gallery: what you've typed, the kind you're browsing, and where the new widget goes.
  @Published var pickerQuery = ""
  @Published var pickerCategory = "All"
  var pickerSlot: Int?
  /// How many rows the Hub can grow to, from one to three.
  @Published var rows = min(HubLayout.maxRows, max(1, UserDefaults.standard.object(forKey: "hubRows") as? Int ?? HubLayout.defaultRows)) {
    didSet { UserDefaults.standard.set(rows, forKey: "hubRows") }
  }
  let media = NowPlayingController()
  let actions = QuickActions()
  let library = MusicLibrary()
  let sessions: SessionsController
  let clipboard: ClipboardHistory
  let timers = TimerController()
  let daily: DailyController
  let reminders = RemindersController()
  let devices = DeviceBatteries()
  let network = NetworkMonitor()
  let system = SystemGraph()
  let audio = AudioOutputs()
  let inUse = MediaInUse()
  let recent = RecentFiles()
  private let url: URL
  private var storageBlocked = false
  init(directory: URL) {
    url = directory.appendingPathComponent("hub.json")
    var loaded = Saved()
    var failed = false
    if FileManager.default.fileExists(atPath: url.path) {
      do { loaded = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)) } catch { failed = true }
    }
    sessions = SessionsController(directory: directory, consent: loaded.usageConsent ?? false)
    clipboard = ClipboardHistory(directory: directory)
    daily = DailyController(directory: directory)
    saved = loaded
    if failed { storageBlocked = true; status = "Hub data could not load. Original file preserved." }
    media.spotify = library.spotify
  }
  func save() {
    guard !storageBlocked else { return }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(saved).write(to: url, options: .atomic)
    } catch { status = "Could not save hub preferences: \(error.localizedDescription)" }
  }

  // MARK: Widgets

  var layout: [HubWidget] {
    HubLayout.sanitize(saved.widgets ?? HubLayout.defaults, known: Set(WidgetKind.catalog.map(\.id)), rows: rows)
  }
  func setLayout(_ layout: [HubWidget]?) {
    guard let layout else { return }
    saved.widgets = layout
    save()
  }
  func add(_ kind: WidgetKind, at index: Int? = nil) {
    let items = kind.id == "shortcuts" ? ["action:record", "action:lens", "action:dark", "action:focus"] : []
    // The smallest size that fits where it's going, or anywhere after.
    for span in kind.spans {
      if let next = HubLayout.add(HubWidget(kind: kind.id, span: span, items: items), at: index, to: layout, rows: rows)
        ?? HubLayout.add(HubWidget(kind: kind.id, span: span, items: items), to: layout, rows: rows)
      {
        setLayout(next)
        return
      }
    }
  }
  func remove(_ id: UUID) { setLayout(HubLayout.remove(id, from: layout)) }
  func resize(_ widget: HubWidget) { setLayout(HubLayout.resize(widget.id, to: widget.span == 1 ? 2 : 1, in: layout, rows: rows)) }
  func move(_ id: UUID, before target: UUID?) { setLayout(HubLayout.move(id, before: target, in: layout, rows: rows)) }
  func setItems(_ id: UUID, _ items: [String]) {
    var next = layout
    guard let index = next.firstIndex(where: { $0.id == id }) else { return }
    next[index].items = Array(items.prefix(8))
    setLayout(next)
  }
  func canResize(_ widget: HubWidget) -> Bool {
    guard let kind = WidgetKind.find(widget.kind), kind.spans.count > 1 else { return false }
    return HubLayout.resize(widget.id, to: widget.span == 1 ? 2 : 1, in: layout, rows: rows) != nil
  }

  // MARK: Tray

  var tray: [TrayItem] { saved.tray ?? [] }
  func keep(_ urls: [URL]) {
    let items = urls.map { $0.isFileURL ? TrayItem(kind: .file, value: $0.path) : TrayItem(kind: .link, value: $0.absoluteString) }
    saved.tray = Tray.adding(items, to: tray)
    save()
  }
  func removeFromTray(_ id: UUID) {
    saved.tray = tray.filter { $0.id != id }
    save()
  }
  /// Files that were moved or deleted since they were kept drop out of the tray.
  func pruneTray() {
    let kept = tray.filter { $0.kind == .link || FileManager.default.fileExists(atPath: $0.value) }
    if kept.count != tray.count { saved.tray = kept; save() }
  }

  // MARK: Volume

  private func runScript(_ source: String, completion: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      var error: NSDictionary?
      let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
      let text = error == nil ? value?.stringValue ?? "" : ""
      Task { @MainActor in completion(text) }
    }
  }
  func readVolume(_ completion: @escaping (Int) -> Void) {
    runScript("output volume of (get volume settings)") { if let value = Int($0) { completion(value) } }
  }
  func volume(_ value: Int) {
    runScript("set volume output volume \(min(100, max(0, value)))") { _ in }
  }

  // MARK: Weather

  func findCity() {
    guard !busy, !city.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [.init(name: "name", value: String(city.prefix(100))), .init(name: "count", value: "4")]
        let data = try await fetch(parts.url!)
        struct Response: Decodable { var results: [Place]? }
        places = try JSONDecoder().decode(Response.self, from: data).results ?? []
        status = places.isEmpty ? "No matching city." : ""
      } catch { status = "Weather unavailable." }
    }
  }
  func choose(_ place: Place) {
    saved.place = place
    save()
    places = []
    city = ""
    weather = nil
    refreshWeather(force: true)
  }
  /// Refreshes at most every 20 minutes unless forced.
  func refreshWeather(force: Bool = false) {
    guard let place = saved.place, !busy else { return }
    if !force, let weather, Date().timeIntervalSince(weather.updated) < 1200 { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(place.latitude)&longitude=\(place.longitude)&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&forecast_hours=13&timezone=auto&timeformat=unixtime")!
        let data = try await fetch(url)
        struct Response: Decodable {
          struct Current: Decodable { var temperature_2m: Double; var weather_code: Int }
          struct Hourly: Decodable { var time: [Double]; var temperature_2m: [Double]; var weather_code: [Int] }
          var current: Current
          var hourly: Hourly?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let value = response.current
        let hourly = response.hourly
        let hours = hourly.map { h in
          zip(h.time, zip(h.temperature_2m, h.weather_code)).map { Weather.Hour(date: Date(timeIntervalSince1970: $0), temperature: $1.0, code: $1.1) }
            .filter { $0.date > Date().addingTimeInterval(-3600) }.prefix(12)
        } ?? []
        weather = Weather(temperature: value.temperature_2m, code: value.weather_code, updated: Date(), hours: Array(hours))
        status = ""
      } catch { status = "Weather unavailable." }
    }
  }
  private func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url); request.timeoutInterval = 15
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw MoltError.invalid("Weather service unavailable.") }
    return data
  }
}
