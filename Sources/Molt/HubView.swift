import AppKit
import MoltCore
import SwiftUI

struct HubView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  @State private var playlist = ""
  @State private var scene = HubScene(name: "Study together")
  @State private var volume = 50.0
  @State private var customize = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 16) {
        Button { controller.tab = "Home" } label: {
          CreatureView(appearance: controller.companion.appearance, atlasURL: controller.atlasURL, mood: controller.mood, moving: !controller.companion.preferences.reducedMotion)
            .frame(width: 48, height: 48)
        }.accessibilityLabel("Customize your companion")
        VStack(alignment: .leading, spacing: 4) {
          Text("Hey, it’s \(controller.petName)!").font(MoltTheme.display(24))
          Text(controller.message).font(.callout).lineLimit(2)
        }
        Spacer()
        Button("Arrange") { customize.toggle() }
      }
      HStack {
        Button("Chat") { controller.tab = "Ask Molt" }
        Button("Today") { controller.tab = "Today" }
        Button("Care") { controller.tab = "Molt" }
        Button("Play") { controller.tab = "Play" }
      }
      if let key = hub.saved.reports.keys.sorted().last, let report = hub.saved.reports[key] {
        DisclosureGroup("Morning postcard · " + String(key.prefix(10))) { Text(report).font(.callout).textSelection(.enabled) }
      }
      if customize {
        ForEach(["Today", "Music", "Weather", "Mac", "Scenes", "Usage"], id: \.self) { card in
          HStack {
            Button(hub.saved.cards.contains(card) ? "✓ \(card)" : "+ \(card)") { hub.toggleCard(card) }
            if hub.saved.cards.contains(card) {
              Button("Move up") { hub.moveCard(card, offset: -1) }
              Button("Move down") { hub.moveCard(card, offset: 1) }
            }
          }
        }
      }
      ForEach(hub.saved.cards, id: \.self) { card in
        MoltCard(title: card) {
          switch card {
          case "Today": today
          case "Music": music
          case "Weather": weather
          case "Mac": mac
          case "Scenes": scenes
          default: UsageHubView(controller: controller, hub: hub)
          }
        }
      }
      Text(hub.status).font(.caption).textSelection(.enabled)
    }
  }
  private var today: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(controller.organization.tasks.first(where: { $0.today && $0.completed == nil })?.title ?? "A little room for your next good idea.")
      ForEach(controller.contexts.events.prefix(2), id: \.eventIdentifier) { event in
        Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) · \(event.title ?? "Event")").font(.caption)
      }
      HStack {
        Button("Focus 25m") { controller.focus(minutes: 25) }
        Button("Priorities & reminders") { controller.tab = "Today" }
      }
    }
  }
  private var music: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Music service", selection: $hub.musicApp) { Text("Music").tag("Music"); Text("Spotify").tag("Spotify") }.pickerStyle(.segmented)
      Text(hub.music)
      HStack {
        Button("Previous") { hub.player("previous track") }
        Button("Play / pause") { hub.player("playpause") }
        Button("Next") { hub.player("next track") }
        Button("Refresh track") { hub.player("status") }
      }.disabled(hub.busy)
      HStack { Slider(value: $volume, in: 0...100); Button("Set volume \(Int(volume))%") { hub.volume(Int(volume)) }.disabled(hub.busy) }
      TextField("Paste an Apple Music or Spotify playlist link", text: $playlist)
      Button("Save favorite") { hub.addPlaylist(playlist) }
      ForEach(hub.saved.playlists, id: \.self) { value in
        HStack { Button("Open playlist") { hub.openPlaylist(value) }; Text(value).font(.caption).lineLimit(1); Button("Remove") { hub.saved.playlists.removeAll { $0 == value }; hub.save() } }
      }
      Text("macOS asks for Automation permission when you use playback controls. Playlist links open in their service; autoplay is not guaranteed.").font(.caption)
    }
  }
  private var weather: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack { TextField("City", text: $hub.city); Button("Find city", action: hub.findCity).disabled(hub.busy) }
      ForEach(hub.places) { place in
        Button("\(place.name), \(place.country ?? "")") { hub.loadWeather(place) }.disabled(hub.busy)
      }
      Text(hub.weather)
      Link("Weather by Open-Meteo · CC BY 4.0", destination: URL(string: "https://open-meteo.com/")!).font(.caption)
      Text("Only the city search and selected coordinates are sent to Open-Meteo. No location permission is needed.").font(.caption)
    }
  }
  private var mac: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack { Button("Add wallpaper", action: hub.chooseWallpaper); Button("Restore wallpaper", action: hub.restoreWallpaper) }
      ForEach(hub.saved.wallpapers, id: \.self) { path in
        HStack { Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1); Button("Apply") { hub.applyWallpaper(path) }; Button("Remove") { hub.saved.wallpapers.removeAll { $0 == path }; hub.save() } }
      }
      Text("Dock position").font(.headline)
      HStack { ForEach(["left", "bottom", "right"], id: \.self) { value in Button(value.capitalized) { hub.dock("orientation", value: value) } } }
      HStack { Button("Auto-hide Dock") { hub.dock("autohide", value: "true") }; Button("Always show Dock") { hub.dock("autohide", value: "false") } }
      HStack { ForEach(["36", "48", "64", "80"], id: \.self) { value in Button("\(value) px") { hub.dock("tilesize", value: value) } } }
      Text("Dock controls apply immediately and restart the Dock. Wallpaper affects current desktops, not every Space. These controls do not install Dock skins.").font(.caption)
    }.disabled(hub.busy)
  }
  private var scenes: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(hub.saved.scenes) { value in
        HStack { Text(value.name); Button("Review scene") { hub.pendingScene = value }; Button("Remove") { hub.saved.scenes.removeAll { $0.id == value.id }; hub.save() } }
      }
      if let pending = hub.pendingScene {
        Text("Review: \(pending.name)").font(.headline)
        Text("Focus: \(pending.minutes) min\nPlaylist: \(pending.playlist.isEmpty ? "None" : pending.playlist)\nWallpaper: \(pending.wallpaper.isEmpty ? "Unchanged" : URL(fileURLWithPath: pending.wallpaper).lastPathComponent)\nApps: \(pending.apps.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))").font(.caption)
        HStack { Button("Run these actions") { hub.runScene(pending, controller: controller) }; Button("Cancel") { hub.pendingScene = nil } }
      }
      DisclosureGroup("Create a scene") {
        TextField("Scene name", text: $scene.name)
        Stepper("Focus: \(scene.minutes) minutes (0 disables)", value: $scene.minutes, in: 0...180)
        Picker("Playlist", selection: $scene.playlist) { Text("None").tag(""); ForEach(hub.saved.playlists, id: \.self) { Text($0).tag($0) } }
        Picker("Wallpaper", selection: $scene.wallpaper) { Text("Unchanged").tag(""); ForEach(hub.saved.wallpapers, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0) } }
        Button("Choose apps") { hub.chooseApps(for: &scene) }
        Text(scene.apps.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")).font(.caption)
        Button("Save scene") { hub.saved.scenes.append(scene); hub.save(); scene = HubScene(name: "New scene") }.disabled(scene.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }
}

struct UsageHubView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Observe foreground app time", isOn: Binding(get: { controller.organization.consent.tracking }, set: { value in controller.updateOrganization { $0.consent.tracking = value }; controller.configureContext() }))
      Text("Local estimates while Molt runs; idle time beyond two minutes and sleeping time are excluded. This is not Apple's Screen Time database.").font(.caption)
      let start = Calendar.current.startOfDay(for: Date())
      let totals = UsageMath.seconds(controller.organization.intervals, from: start, to: Date())
      ForEach(totals.keys.sorted(), id: \.self) { name in Text("\(name): \(Int((totals[name] ?? 0) / 60)) min").font(.caption) }
      Toggle("Read Claude Code / Codex usage logs and process time", isOn: Binding(get: { hub.saved.usageConsent }, set: hub.setUsageConsent))
      Text("Reads numeric usage from ~/.claude/projects and ~/.codex/sessions. Prompts are not retained or sent anywhere. Process-running time can overlap with app time and does not measure attention.").font(.caption)
      Button("Refresh token records") { hub.importUsage() }.disabled(!hub.saved.usageConsent || hub.importBusy)
      Text(hub.importStatus).font(.caption)
      ForEach(["Claude Code", "Codex"], id: \.self) { tool in
        let records = hub.tokens.filter { $0.tool == tool && $0.date >= start }
        Text("\(tool) today: \(records.reduce(0) { $0 + $1.input + $1.cached + $1.output }) imported tokens").font(.caption)
      }
      DisclosureGroup("Optional cost estimate rates, USD per million tokens") {
        Text("Enter rates matching your usage. Cache creation is counted as input; estimates are approximate and are not your subscription bill.").font(.caption)
        TextField("Input", value: $hub.saved.inputRate, format: .number)
        TextField("Output", value: $hub.saved.outputRate, format: .number)
        TextField("Cached input", value: $hub.saved.cacheRate, format: .number)
        Button("Save rates", action: hub.save)
      }
      let records = hub.tokens.filter { $0.date >= start }
      let reported = records.compactMap(\.reportedCost)
      if !reported.isEmpty { Text("Reported cost from \(reported.count) records: " + String(format: "$%.4f", reported.reduce(0,+))).font(.caption) }
      Text("Estimated today: \(UsageMath.estimate(records, inputRate: hub.saved.inputRate, outputRate: hub.saved.outputRate, cacheRate: hub.saved.cacheRate).map { String(format: "$%.4f", $0) } ?? "unavailable; set rates")").font(.caption)
      Toggle("Morning report after 7 AM", isOn: Binding(get: { hub.saved.morning }, set: { hub.saved.morning = $0; hub.save() }))
      Text("Reports appear here when Molt is running, or on the next launch after 7 AM. No background system daemon is installed.").font(.caption)
      ForEach(hub.saved.reports.keys.sorted().reversed(), id: \.self) { key in
        DisclosureGroup(String(key.prefix(10))) { Text(hub.saved.reports[key] ?? "").font(.caption).textSelection(.enabled) }
      }
      Button("Forget Molt AI usage & reports", action: hub.forgetUsage)
      Button("Tracking exclusions & app history") { controller.tab = "Activity" }
    }
  }
}
