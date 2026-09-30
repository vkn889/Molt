import AppKit
import MoltCore
import SwiftUI

@MainActor final class HubController: ObservableObject {
  /// Unknown keys from earlier versions are ignored; every field is optional so old files load.
  struct Saved: Codable {
    var place: Place?
    var usageConsent: Bool?
  }
  struct Place: Codable, Identifiable, Equatable {
    var id: Int; var name: String; var latitude: Double; var longitude: Double; var country: String?
  }
  struct Weather: Equatable {
    var temperature: Double
    var code: Int
    var updated: Date
    var symbol: String {
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
  let media = NowPlayingController()
  let library = MusicLibrary()
  let sessions: SessionsController
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
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(place.latitude)&longitude=\(place.longitude)&current=temperature_2m,weather_code&timezone=auto")!
        let data = try await fetch(url)
        struct Response: Decodable { struct Current: Decodable { var temperature_2m: Double; var weather_code: Int }; var current: Current }
        let value = try JSONDecoder().decode(Response.self, from: data).current
        weather = Weather(temperature: value.temperature_2m, code: value.weather_code, updated: Date())
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
