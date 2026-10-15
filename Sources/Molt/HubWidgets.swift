import AppKit
import EventKit
import MoltCore
import SwiftUI

/// A Hub widget's card: a tinted icon and title, NEW for a while if it's new, then the content.
struct Tile<Content: View>: View {
  var title: String
  var icon: String
  var tint: Color? = nil
  @ViewBuilder var content: Content
  @Environment(\.widgetKind) private var kind
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint ?? Color.white.opacity(0.55))
        Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        Spacer(minLength: 2)
        if WidgetKind.isFresh(kind) {
          Text("NEW").font(.system(size: 9.5, weight: .bold)).tracking(0.4).foregroundStyle(Color(red: 0.36, green: 0.8, blue: 0.55))
        }
      }
      content
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 16))
  }
}

private struct WidgetKindKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
  var widgetKind: String {
    get { self[WidgetKindKey.self] }
    set { self[WidgetKindKey.self] = newValue }
  }
}

/// Focus at a glance: the time left as a ring, with Molt in its glasses. Opens the Focus page.
struct FocusTile: View {
  @ObservedObject var controller: PetController
  @AppStorage("focusMinutes") private var minutes = 25
  var body: some View {
    let tint = MoltTheme.body(controller.companion.appearance.palette)
    let today = FocusMath.today(controller.organization.sessions, now: Date())
    Button { controller.tab = "Focus" } label: {
      Tile(title: "Focus", icon: "timer", tint: tint) {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let session = controller.openFocus
          let left = session.map { controller.focusClock($0, at: context.date) } ?? Double(minutes * 60)
          let progress = session.map { $0.target > 0 ? min(1, $0.duration(at: context.date) / $0.target) : 0 } ?? 0
          HStack(spacing: 12) {
            ZStack {
              Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
              Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
              Text(Self.clock(left)).font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(session != nil && session?.lastResumed == nil ? Color.white.opacity(0.5) : .white)
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
              CreatureView(appearance: controller.companion.appearance.wearing("glasses"), mood: session?.lastResumed != nil ? "working" : "idle", followsPointer: false)
                .frame(width: 40, height: 37)
              Text(Self.status(session, today: today.count)).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
            }
          }
          .padding(.top, 2)
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain).help("Open Focus")
  }
  static func status(_ session: FocusSession?, today: Int) -> String {
    if let session { return session.lastResumed == nil ? "Paused" : Self.ordinal(today + 1) + " today" }
    return today == 0 ? "Ready" : "\(today) today"
  }
  static func ordinal(_ n: Int) -> String {
    let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd"][min(n % 10, 4) < 4 ? n % 10 : 0]
    return "\(n)\(suffix)"
  }
  static func clock(_ seconds: Double) -> String {
    let s = Int(seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
  }
}

struct TasksTile: View {
  @ObservedObject var controller: PetController
  var span = 1
  @State private var draft = ""
  private var tasks: [WorkTask] {
    let open = controller.organization.tasks.filter { $0.completed == nil }
    return Array((open.filter(\.today) + open.filter { !$0.today }.reversed()).prefix(span == 2 ? 4 : 3))
  }
  var body: some View {
    Tile(title: "Tasks", icon: "checklist") {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(tasks) { task in
          Button {
            controller.updateOrganization { $0.completeTask(task.id, now: Date()) }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(task.today ? Color.accentColor : Color.white.opacity(0.4))
              Text(task.title).font(.system(size: 11)).lineLimit(1).foregroundStyle(Color.white.opacity(0.88))
              Spacer(minLength: 0)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain).help("Mark done")
        }
        if tasks.isEmpty {
          Text("All clear.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      TextField("Add a task", text: $draft).textFieldStyle(.plain).font(.system(size: 11))
        .padding(.horizontal, 8).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
        .onSubmit(add)
    }
  }
  private func add() {
    let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    controller.updateOrganization { o in
      var task = WorkTask(String(title.prefix(200)))
      task.today = o.tasks.filter { $0.today && $0.completed == nil }.count < 3
      o.tasks.append(task)
    }
    draft = ""
  }
}

struct WeatherTile: View {
  @ObservedObject var hub: HubController
  @State private var editing = false
  /// In your units, or Fahrenheit or Celsius as chosen in Settings › Hub.
  static func temperature(_ celsius: Double) -> String {
    let fahrenheit = UserDefaults.standard.object(forKey: "weatherFahrenheit") as? Bool ?? (Locale.current.measurementSystem == .us)
    let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
    return "\(Int(value.rounded()))°" + (fahrenheit ? "F" : "C")
  }
  var body: some View {
    Tile(title: hub.saved.place?.name ?? "Weather", icon: "location.fill") {
      if let weather = hub.weather, !editing {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22))
          Text(WeatherTile.temperature(weather.temperature))
            .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
        }
        Text(weather.summary).font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        HStack {
          Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!).font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(0.3))
          Spacer()
          Button { editing = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)) }
            .buttonStyle(NotchIconButtonStyle(size: 22)).help("Change city").accessibilityLabel("Change city")
        }
      } else if hub.saved.place != nil && !editing {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        TextField("Search a city", text: $hub.city).textFieldStyle(.plain).font(.system(size: 11))
          .padding(.horizontal, 8).frame(height: 24)
          .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
          .onSubmit(hub.findCity)
        VStack(alignment: .leading, spacing: 4) {
          ForEach(hub.places.prefix(3)) { place in
            Button { editing = false; hub.choose(place) } label: {
              Text([place.name, place.country].compactMap { $0 }.joined(separator: ", "))
                .font(.system(size: 11)).lineLimit(1).foregroundStyle(Color.white.opacity(0.85))
            }.buttonStyle(.plain)
          }
          if !hub.status.isEmpty { Text(hub.status).font(.system(size: 10)).foregroundStyle(.secondary) }
        }
      }
    }
    .onAppear { hub.refreshWeather() }
  }
}

struct TopAppsTile: View {
  @ObservedObject var controller: PetController
  var span = 1
  var body: some View {
    Tile(title: "Top apps today", icon: "chart.bar.fill") {
      if !controller.organization.consent.tracking {
        Text("See which apps you use most.").font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Button("Turn on") {
          controller.updateOrganization { $0.consent.tracking = true }
          controller.configureContext()
        }
      } else if top.isEmpty {
        Text("Collecting… Check back in a few minutes.").font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if span == 2 {
        HStack(alignment: .top, spacing: 10) {
          ForEach(top, id: \.id) { app in
            VStack(spacing: 4) {
              if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 38, height: 38) }
              Text(app.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
              Text(Self.duration(app.seconds)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
          }
        }.frame(maxHeight: .infinity)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(top, id: \.id) { app in
            HStack(spacing: 8) {
              if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
              } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12)).frame(width: 22, height: 22)
              }
              Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(.white)
              Spacer(minLength: 4)
              Text(Self.duration(app.seconds)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }
  struct AppTime { var id: String; var name: String; var seconds: Double; var icon: NSImage? }
  private var top: [AppTime] {
    let start = Calendar.current.startOfDay(for: Date())
    var totals: [String: (String, Double)] = [:]
    for interval in controller.organization.intervals {
      let seconds = min(interval.end, Date()).timeIntervalSince(max(interval.start, start))
      guard seconds > 0 else { continue }
      totals[interval.app, default: (interval.name, 0)].1 += seconds
    }
    return totals.sorted { $0.value.1 > $1.value.1 }.prefix(span == 2 ? 4 : 3).map { id, value in
      AppTime(
        id: id, name: value.0, seconds: value.1,
        icon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) })
    }
  }
  static func duration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(1, minutes))m"
  }
}

// MARK: Catalog

struct WidgetKind: Identifiable {
  var id: String
  var title: String
  var symbol: String
  /// Allowed sizes, smallest first.
  var spans: [Int]
  var blurb: String
  /// Where it's listed when adding widgets: Molt, Mac, Agents, Music or Tools.
  var category: String {
    switch id {
    case "focus", "molt", "weekRecap", "tray", "habits", "breaks", "focusStats", "dailyBrief": return "Molt"
    case "agentUsage", "agents", "planUsage", "github": return "Agents"
    case "nowPlaying", "playlists", "soundOutput": return "Music"
    case "macHealth", "topApps", "downloads", "clock", "weather", "upNext", "batteries", "network", "systemGraph", "screenshots", "recentFiles",
      "inUse", "camera", "worldClocks", "weatherHourly", "quickToggles", "reminders", "countdown": return "Mac"
    default: return "Tools"
    }
  }
  /// New or redesigned in this version.
  var badge: String? {
    switch id {
    case "tray", "clipboard", "timer", "countdown", "breaks", "habits", "reminders", "batteries", "network", "systemGraph", "worldClocks",
      "soundOutput", "screenshots", "recentFiles", "calculator", "camera", "inUse", "dailyBrief", "focusStats", "weatherHourly", "colors", "quickToggles":
      return "New"
    case "focus", "upNext": return "New look"
    default: return nil
    }
  }
  static let categories = ["All", "New", "Molt", "Mac", "Agents", "Music", "Tools"]
  var tint: Color {
    switch id {
    case "focus", "molt", "habits", "breaks", "focusStats": return Color(red: 0.36, green: 0.8, blue: 0.55)
    case "upNext", "worldClocks", "network", "weatherHourly": return Color(red: 0.39, green: 0.82, blue: 1)
    case "nowPlaying", "playlists", "soundOutput": return Color(red: 1, green: 0.39, blue: 0.51)
    case "recorder", "inUse": return .red
    case "clock", "timer", "countdown", "planUsage": return .orange
    case "shortcuts", "quickToggles": return .yellow
    case "batteries", "macHealth", "systemGraph": return .white
    case "colors": return .cyan
    case "dailyBrief": return .purple
    default: return .accentColor
    }
  }
  /// New widgets say so on the Hub for two weeks after the update that brought them.
  static func isFresh(_ id: String) -> Bool {
    guard find(id)?.badge != nil else { return false }
    let since = UserDefaults.standard.object(forKey: "moltNewSince") as? Date ?? Date()
    return Date().timeIntervalSince(since) < 14 * 86400
  }
  static let catalog: [WidgetKind] = [
    WidgetKind(id: "focus", title: "Focus", symbol: "timer", spans: [1], blurb: "A focus timer, with Molt"),
    WidgetKind(id: "tray", title: "Tray", symbol: "tray.fill", spans: [1, 2], blurb: "Files and links you dropped on Molt"),
    WidgetKind(id: "tasks", title: "Tasks", symbol: "checklist", spans: [1, 2], blurb: "Today's to-dos"),
    WidgetKind(id: "weather", title: "Weather", symbol: "cloud.sun.fill", spans: [1], blurb: "Your city's weather"),
    WidgetKind(id: "topApps", title: "Top apps", symbol: "chart.bar.fill", spans: [1, 2], blurb: "Most-used apps today"),
    WidgetKind(id: "shortcuts", title: "Shortcuts", symbol: "square.grid.2x2.fill", spans: [1, 2], blurb: "One-click actions you choose"),
    WidgetKind(id: "recorder", title: "Screen recorder", symbol: "record.circle", spans: [1], blurb: "Record your screen in one click"),
    WidgetKind(id: "lens", title: "Lens", symbol: "text.viewfinder", spans: [1], blurb: "Ask about your screen"),
    WidgetKind(id: "molt", title: "Molt", symbol: "leaf.fill", spans: [1], blurb: "Molt's mood and needs"),
    WidgetKind(id: "agentUsage", title: "Agent usage", symbol: "terminal.fill", spans: [1], blurb: "Claude Code and Codex tokens"),
    WidgetKind(id: "agents", title: "Agents", symbol: "bolt.fill", spans: [1], blurb: "Who's working and who needs you"),
    WidgetKind(id: "planUsage", title: "Plan usage", symbol: "gauge.with.dots.needle.67percent", spans: [1, 2], blurb: "Claude and Codex limits, with a forecast"),
    WidgetKind(id: "weekRecap", title: "Your week", symbol: "sparkles.rectangle.stack.fill", spans: [2], blurb: "A recap card you can share"),
    WidgetKind(id: "github", title: "GitHub", symbol: "arrow.triangle.pull", spans: [1, 2], blurb: "PRs, checks and your streak"),
    WidgetKind(id: "upNext", title: "Next up", symbol: "calendar", spans: [1, 2], blurb: "Your next event, with a countdown and Join"),
    WidgetKind(id: "macHealth", title: "Mac health", symbol: "cpu", spans: [1], blurb: "Battery, CPU, memory, storage"),
    WidgetKind(id: "nowPlaying", title: "Now playing", symbol: "music.note", spans: [1, 2], blurb: "Music controls"),
    WidgetKind(id: "playlists", title: "Playlists", symbol: "music.note.list", spans: [2], blurb: "Tap a cover to play"),
    WidgetKind(id: "clock", title: "Clock", symbol: "clock.fill", spans: [1], blurb: "Time and date"),
    WidgetKind(id: "downloads", title: "Downloads", symbol: "arrow.down.circle.fill", spans: [1, 2], blurb: "Your latest downloads"),
    WidgetKind(id: "quickNote", title: "Quick note", symbol: "note.text", spans: [1, 2], blurb: "A scratchpad that saves itself"),
    WidgetKind(id: "webSearch", title: "Web search", symbol: "magnifyingglass", spans: [1, 2], blurb: "Search from the notch"),
    WidgetKind(id: "clipboard", title: "Clipboard", symbol: "doc.on.clipboard", spans: [1, 2], blurb: "What you've copied, ready to copy again"),
    WidgetKind(id: "timer", title: "Timer", symbol: "stopwatch.fill", spans: [1, 2], blurb: "A timer, a stopwatch and alarms"),
    WidgetKind(id: "countdown", title: "Countdown", symbol: "calendar.badge.clock", spans: [1, 2], blurb: "Days until something big"),
    WidgetKind(id: "breaks", title: "Breaks", symbol: "drop.fill", spans: [1], blurb: "Water and stretch reminders, with Molt"),
    WidgetKind(id: "habits", title: "Habits", symbol: "checkmark.seal.fill", spans: [1, 2], blurb: "Daily check-offs with streaks"),
    WidgetKind(id: "reminders", title: "Reminders", symbol: "list.bullet.circle.fill", spans: [1, 2], blurb: "Your Apple Reminders"),
    WidgetKind(id: "batteries", title: "Batteries", symbol: "battery.75", spans: [1, 2], blurb: "AirPods, keyboard, mouse and trackpad"),
    WidgetKind(id: "network", title: "Network", symbol: "wifi", spans: [1, 2], blurb: "Live speed, Wi-Fi and IP"),
    WidgetKind(id: "systemGraph", title: "System graph", symbol: "waveform.path.ecg", spans: [1, 2], blurb: "CPU and memory over time"),
    WidgetKind(id: "worldClocks", title: "World clocks", symbol: "globe", spans: [1, 2], blurb: "The time in other cities"),
    WidgetKind(id: "soundOutput", title: "Sound output", symbol: "hifispeaker.fill", spans: [1], blurb: "Switch speakers and set the volume"),
    WidgetKind(id: "screenshots", title: "Screenshots", symbol: "camera.viewfinder", spans: [1, 2], blurb: "Your latest, ready to drag"),
    WidgetKind(id: "recentFiles", title: "Recent files", symbol: "clock.arrow.circlepath", spans: [1, 2], blurb: "What you opened lately"),
    WidgetKind(id: "calculator", title: "Calculator", symbol: "plus.forwardslash.minus", spans: [1], blurb: "Math, percentages and unit conversions"),
    WidgetKind(id: "camera", title: "Camera mirror", symbol: "video.fill", spans: [1], blurb: "Check how you look before a call"),
    WidgetKind(id: "inUse", title: "Mic & camera", symbol: "mic.fill", spans: [1], blurb: "Whether you're live"),
    WidgetKind(id: "dailyBrief", title: "Daily brief", symbol: "sun.horizon.fill", spans: [2], blurb: "Your day in three sentences, from Molt"),
    WidgetKind(id: "focusStats", title: "Focus stats", symbol: "chart.bar.fill", spans: [1, 2], blurb: "This week's focus, day by day"),
    WidgetKind(id: "weatherHourly", title: "Weather by hour", symbol: "cloud.sun.fill", spans: [2], blurb: "The next 12 hours"),
    WidgetKind(id: "colors", title: "Colors", symbol: "eyedropper", spans: [1, 2], blurb: "Colors you've picked, to copy"),
    WidgetKind(id: "quickToggles", title: "Quick toggles", symbol: "switch.2", spans: [1, 2], blurb: "Awake, dark mode, icons, Wi-Fi, Bluetooth, Focus"),
  ]
  static func find(_ id: String) -> WidgetKind? { catalog.first { $0.id == id } }
}

/// Renders one placed widget.
struct WidgetView: View {
  var widget: HubWidget
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  var body: some View {
    tile.environment(\.widgetKind, widget.kind)
  }
  @ViewBuilder private var tile: some View {
    switch widget.kind {
    case "focus": FocusTile(controller: controller)
    case "tasks": TasksTile(controller: controller, span: widget.span)
    case "weather": WeatherTile(hub: hub)
    case "topApps": TopAppsTile(controller: controller, span: widget.span)
    case "shortcuts": ShortcutsTile(widget: widget, actions: hub.actions)
    case "recorder": RecorderTile(actions: hub.actions)
    case "lens": LensTile(open: { hub.actions.onLens() })
    case "molt": MoltTile(controller: controller)
    case "agentUsage": AgentUsageTile(sessions: hub.sessions)
    case "agents": AgentsTile(controller: controller, agents: controller.agents)
    case "planUsage": PlanUsageTile(plans: controller.plans, span: widget.span, open: { show(controller, "Usage") })
    case "weekRecap": WeekRecapTile(controller: controller, agents: controller.agents, github: controller.github, sessions: hub.sessions)
    case "github": GitHubTile(github: controller.github, span: widget.span, open: { show(controller, "GitHub") })
    case "upNext": UpNextTile(controller: controller, contexts: controller.contexts, span: widget.span)
    case "macHealth": MacHealthTile(controller: controller)
    case "nowPlaying": NowPlayingTile(media: hub.media, span: widget.span)
    case "playlists": PlaylistsTile(library: hub.library, spotify: hub.library.spotify, appleMusic: hub.library.appleMusic)
    case "clock": ClockTile()
    case "downloads": DownloadsTile(span: widget.span)
    case "quickNote": QuickNoteTile(hub: hub)
    case "tray": TrayTile(hub: hub, span: widget.span)
    case "clipboard": ClipboardTile(clipboard: hub.clipboard, span: widget.span)
    case "timer": TimerTile(timers: hub.timers, span: widget.span)
    case "countdown": CountdownTile(daily: hub.daily, span: widget.span)
    case "breaks": BreaksTile(daily: hub.daily)
    case "habits": HabitsTile(daily: hub.daily, span: widget.span)
    case "reminders": RemindersTile(reminders: hub.reminders, span: widget.span)
    case "batteries": BatteriesTile(devices: hub.devices, controller: controller, span: widget.span)
    case "network": NetworkTile(network: hub.network, span: widget.span)
    case "systemGraph": SystemGraphTile(system: hub.system, span: widget.span)
    case "worldClocks": WorldClocksTile(span: widget.span)
    case "soundOutput": SoundOutputTile(audio: hub.audio)
    case "screenshots": ScreenshotsTile(span: widget.span)
    case "recentFiles": RecentFilesTile(recent: hub.recent, span: widget.span)
    case "calculator": CalculatorTile()
    case "camera": CameraTile()
    case "inUse": InUseTile(inUse: hub.inUse)
    case "dailyBrief": DailyBriefTile(controller: controller, assistant: controller.assistant)
    case "focusStats": FocusStatsTile(controller: controller, span: widget.span)
    case "weatherHourly": WeatherHourlyTile(hub: hub, span: widget.span)
    case "colors": ColorsTile(actions: hub.actions, span: widget.span)
    case "quickToggles": QuickTogglesTile(actions: hub.actions, span: widget.span)
    default: WebSearchTile(span: widget.span)
    }
  }
}

@MainActor private func show(_ controller: PetController, _ tab: String) {
  UserDefaults.standard.set(tab, forKey: "agentsTab")
  controller.tab = "Agents"
}

// MARK: Developer widgets

struct AgentsTile: View {
  @ObservedObject var controller: PetController
  @ObservedObject var agents: AgentController
  var body: some View {
    Button { show(controller, "Live") } label: {
      Tile(title: "Agents", icon: "bolt.fill") {
        HStack(spacing: 8) {
          CreatureView(appearance: controller.companion.appearance, mood: agents.mood ?? "idle", shell: controller.shellColor, followsPointer: false)
            .frame(width: 52, height: 48)
          VStack(alignment: .leading, spacing: 1) {
            Text(agents.needsYou ? "Needs you" : agents.working.isEmpty ? "All quiet" : "\(agents.working.count) working")
              .font(.system(size: 13, weight: .semibold)).foregroundStyle(agents.needsYou ? .orange : .white)
            Text(agents.working.first?.project ?? "\(agents.saved.tasksFinished) tasks done").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if let last = agents.finished.first {
          Text("\(AgentKind.find(last.agent)?.name ?? "Agent") finished \(last.date.formatted(.relative(presentation: .named)))")
            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}

struct PlanUsageTile: View {
  @ObservedObject var plans: PlanController
  var span: Int
  var open: () -> Void
  var body: some View {
    Button(action: open) {
      Tile(title: "Plan usage", icon: "gauge.with.dots.needle.67percent") {
        if plans.all.isEmpty {
          Text("Claude and Codex limits appear here.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Text("Set up in Agents › Usage").font(.system(size: 10)).foregroundStyle(Color.accentColor)
        } else if span == 2 {
          HStack(alignment: .top, spacing: 12) {
            ForEach(plans.all, id: \.tool) { limits in
              VStack(alignment: .leading, spacing: 5) {
                Text(limits.tool).font(.system(size: 11, weight: .semibold)).foregroundStyle(limits.tool == "Codex" ? .teal : .orange)
                if let window = limits.session { LimitBar(title: "5 hours", window: window, tint: limits.tool == "Codex" ? .teal : .orange) }
                if let window = limits.week { LimitBar(title: "Week", window: window, tint: limits.tool == "Codex" ? .teal : .orange, compact: true) }
              }
            }
          }
        } else {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(plans.all, id: \.tool) { limits in
              if let window = limits.session ?? limits.week {
                LimitBar(title: limits.tool, window: window, tint: limits.tool == "Codex" ? .teal : .orange, compact: true)
              }
            }
          }
          Spacer(minLength: 0)
          if let window = plans.all.compactMap(\.session).max(by: { $0.used < $1.used }) {
            Text(PlanController.pace(window)).font(.system(size: 9)).foregroundStyle(window.forecast(now: Date()) != nil ? Color.orange : Color.secondary).lineLimit(1)
          }
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onAppear { plans.refresh() }
  }
}

struct GitHubTile: View {
  @ObservedObject var github: GitHubController
  var span: Int
  var open: () -> Void
  var body: some View {
    Button(action: open) {
      Tile(title: "GitHub", icon: "arrow.triangle.pull") {
        if let summary = github.summary {
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(summary.streak)").font(.system(size: 24, weight: .semibold).monospacedDigit())
                Text("day streak").font(.system(size: 10)).foregroundStyle(.secondary)
              }
              row("arrow.triangle.pull", "My PRs", "\(summary.mine.count)", .white)
              row("eye", "To review", "\(summary.reviews.count)", summary.waiting(now: Date()).isEmpty ? .white : .orange)
              row("circle.fill", summary.branch ?? "CI", GitHubPanel.label(summary.ci), GitHubPanel.color(summary.ci))
            }
            if span == 2 { ContributionGrid(days: summary.days, weeks: 16).frame(maxWidth: .infinity) }
          }
        } else {
          Text(github.enabled ? (github.status.isEmpty ? "Loading…" : github.status) : "Your PRs, checks and streak.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if !github.enabled { Text("Turn on").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor) }
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onAppear { github.refresh() }
  }
  private func row(_ symbol: String, _ title: String, _ value: String, _ tint: Color) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 6 : 9)).foregroundStyle(tint == .white ? Color.secondary : tint).frame(width: 12)
      Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      Spacer(minLength: 2)
      Text(value).font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
    }
  }
}

/// The week at a glance, in a card that saves as a picture to share.
struct WeekRecapTile: View {
  @ObservedObject var controller: PetController
  @ObservedObject var agents: AgentController
  @ObservedObject var github: GitHubController
  @ObservedObject var sessions: SessionsController
  @State private var saved = ""
  var body: some View {
    ZStack(alignment: .topTrailing) {
      WeekRecapCard(recap: recap)
      Button(action: share) {
        Label(saved.isEmpty ? "Share" : saved, systemImage: saved.isEmpty ? "square.and.arrow.up" : "checkmark")
          .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).frame(height: 20)
          .background(Capsule().fill(Color.white.opacity(0.12)))
      }
      .buttonStyle(.plain).padding(10).help("Save this card to your Desktop and copy it")
    }
    .onAppear { sessions.scan() }
  }
  private var recap: WeekRecap {
    let week = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-6 * 86400)
    return WeekRecap(
      appearance: controller.companion.appearance, name: controller.petName, level: controller.companion.experience / 100 + 1,
      tokens: sessions.tokens(since: week), tasks: agents.finishedThisWeek,
      contributions: github.summary.map { $0.days.suffix(7).reduce(0) { $0 + $1.count } }, streak: github.summary?.streak)
  }
  private func share() {
    let renderer = ImageRenderer(content: WeekRecapCard(recap: recap, poster: true).frame(width: 600, height: 315).environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { return }
    let name = "Molt week \(Date().formatted(.dateTime.year().month().day())).png".replacingOccurrences(of: "/", with: "-")
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").appendingPathComponent(name)
    try? png.write(to: url, options: .atomic)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    saved = "Saved"
  }
}

struct WeekRecap {
  var appearance: Appearance
  var name: String
  var level: Int
  var tokens: Int
  var tasks: Int
  var contributions: Int?
  var streak: Int?
}

struct WeekRecapCard: View {
  var recap: WeekRecap
  /// The shareable version: its own background and a little more room.
  var poster = false
  var body: some View {
    HStack(spacing: poster ? 24 : 14) {
      CreatureView(appearance: recap.appearance, mood: "celebrating", moving: !poster, followsPointer: false, clock: poster ? 1000.2 : nil)
        .frame(width: poster ? 150 : 70, height: poster ? 140 : 65)
      VStack(alignment: .leading, spacing: poster ? 10 : 5) {
        Text("\(recap.name)'s week").font(.system(size: poster ? 26 : 13, weight: .semibold))
        HStack(spacing: poster ? 22 : 10) {
          stat(SessionsView.compact(recap.tokens), "agent tokens")
          stat("\(recap.tasks)", "tasks done")
          if poster, let contributions = recap.contributions { stat("\(contributions)", "contributions") }
          if let streak = recap.streak { stat("\(streak)", "day streak") }
        }
        Text("Level \(recap.level) · made with Molt").font(.system(size: poster ? 13 : 9)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(poster ? 34 : 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      Group {
        if poster {
          LinearGradient(colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color(red: 0.12, green: 0.2, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
          NotchSurface(radius: 16)
        }
      })
    .foregroundStyle(.white)
  }
  private func stat(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(value).font(.system(size: poster ? 30 : 17, weight: .semibold).monospacedDigit())
      Text(label).font(.system(size: poster ? 12 : 9)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
  }
}

// MARK: Shortcut widgets

/// Actions you pick, as tiles of icons. Small shows four; wide shows eight.
struct ShortcutsTile: View {
  var widget: HubWidget
  @ObservedObject var actions: QuickActions
  var body: some View {
    let columns = widget.span == 2 ? 4 : 2
    let items = Array(widget.items.prefix(columns * 2))
    Tile(title: "Actions", icon: "bolt.fill", tint: .yellow) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
        ForEach(items, id: \.self) { item in
          Button { actions.run(item) } label: {
            VStack(spacing: 3) {
              if let icon = actions.icon(item) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
              } else {
                let symbol = actions.symbol(item)
                Image(systemName: symbol.0).font(.system(size: 15, weight: .medium))
                  .symbolRenderingMode(.palette)
                  .foregroundStyle(symbol.0.hasSuffix("circle.fill") ? Color.white : symbol.1, symbol.1, symbol.1)
              }
              Text(Self.short(actions.title(item))).font(.system(size: 11, weight: .semibold)).lineLimit(1).foregroundStyle(Color.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(actions.isActive(item) ? 0.16 : 0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
          }
          .buttonStyle(BareButtonStyle()).help(actions.title(item)).accessibilityLabel(actions.title(item))
        }
      }
      if items.isEmpty {
        Text("Edit the Hub to choose actions.").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      if actions.confirmingTrash {
        HStack(spacing: 6) {
          Text("Empty Trash?").font(.system(size: 10, weight: .semibold))
          Button("Empty", action: actions.emptyTrash).foregroundStyle(.red)
          Button("Cancel") { actions.confirmingTrash = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
    }
  }
  /// Tile labels say it in a word: "Ask about screen" is "Ask".
  static func short(_ title: String) -> String {
    let words = ["Record screen": "Record", "Ask about screen": "Ask", "Dark mode": "Dark", "Focus 25m": "Focus", "Pick color": "Color",
      "Keep awake": "Awake", "Sleep screen": "Sleep", "Empty Trash": "Trash", "System Settings": "Settings", "Screenshot": "Shot"]
    return words[title] ?? title
  }
}

struct RecorderTile: View {
  @ObservedObject var actions: QuickActions
  var body: some View {
    Tile(title: "Screen recorder", icon: "record.circle") {
      Spacer(minLength: 0)
      HStack {
        Spacer()
        Button { actions.run("action:record") } label: {
          ZStack {
            Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 3).frame(width: 52, height: 52)
            if actions.recording == nil {
              Circle().fill(Color.red).frame(width: 40, height: 40)
            } else {
              RoundedRectangle(cornerRadius: 5).fill(Color.red).frame(width: 22, height: 22)
            }
          }.contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(actions.recording == nil ? "Start recording" : "Stop recording")
        Spacer()
      }
      if let started = actions.recording {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(HangoutView.clock(context.date.timeIntervalSince(started))).font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.red).frame(maxWidth: .infinity)
        }
      } else {
        Text(actions.status.isEmpty ? "Saves to Movies" : actions.status).font(.system(size: 10)).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
  }
}

struct LensTile: View {
  var open: () -> Void
  var body: some View {
    Tile(title: "Lens", icon: "text.viewfinder") {
      Spacer(minLength: 0)
      Button(action: open) {
        VStack(spacing: 6) {
          Image(systemName: "viewfinder").font(.system(size: 30, weight: .light)).foregroundStyle(Color.accentColor)
          Text("Ask about screen").font(.system(size: 11, weight: .medium))
        }.frame(maxWidth: .infinity).contentShape(Rectangle())
      }.buttonStyle(.plain).help("Select part of your screen (⌘⇧L)")
      Spacer(minLength: 0)
    }
  }
}

struct WebSearchTile: View {
  var span: Int
  @State private var query = ""
  static let engines: [(String, String, String)] = [
    ("Google", "https://www.google.com/search?q=", "magnifyingglass"), ("YouTube", "https://www.youtube.com/results?search_query=", "play.rectangle.fill"),
    ("Wikipedia", "https://en.wikipedia.org/w/index.php?search=", "book.closed.fill"), ("Maps", "https://maps.apple.com/?q=", "map.fill"),
  ]
  var body: some View {
    Tile(title: "Web search", icon: "magnifyingglass") {
      TextField("Search the web", text: $query).textFieldStyle(.plain).font(.system(size: 12))
        .padding(.horizontal, 9).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        .onSubmit { search(Self.engines[0].1) }
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        ForEach(Self.engines.prefix(4), id: \.0) { engine in
          Button { search(engine.1) } label: {
            Group {
              if span == 2 {
                Label(engine.0, systemImage: engine.2).padding(.horizontal, 8)
              } else {
                Image(systemName: engine.2).frame(width: 26)
              }
            }
            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
            .frame(height: 24).background(Capsule().fill(Color.white.opacity(0.08)))
          }.buttonStyle(.plain).disabled(query.isEmpty).help("Search \(engine.0)").accessibilityLabel("Search \(engine.0)")
        }
      }
    }
  }
  private func search(_ base: String) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: base + encoded)
    else { return }
    NSWorkspace.shared.open(url)
    query = ""
  }
}

// MARK: Glance widgets

/// Molt's needs, labeled, as in the mockup. Opens Play.
struct MoltTile: View {
  @ObservedObject var controller: PetController
  var body: some View {
    Button { controller.tab = "Play" } label: {
      Tile(title: controller.petName, icon: "leaf.fill", tint: MoltTheme.body(controller.companion.appearance.palette)) {
        HStack(spacing: 12) {
          CreatureView(appearance: controller.companion.appearance, mood: controller.isResting ? "sleeping" : controller.displayMood, poked: controller.poked)
            .frame(width: 54, height: 50)
          VStack(alignment: .leading, spacing: 7) {
            bar("Food", "hunger", .orange)
            bar("Energy", "energy", .yellow)
            bar("Love", "affection", Color(red: 1, green: 0.27, blue: 0.23))
          }
        }
        .padding(.top, 4)
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain).help("Play with \(controller.petName)")
  }
  private func bar(_ title: String, _ key: String, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.55))
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.12))
          Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, (controller.state.stats[key] ?? 0) / 100)))
        }
      }.frame(height: 4)
    }
  }
}

struct AgentUsageTile: View {
  @ObservedObject var sessions: SessionsController
  var body: some View {
    Tile(title: "Agent usage", icon: "terminal.fill") {
      if sessions.enabled {
        let today = Calendar.current.startOfDay(for: Date())
        Text(SessionsView.compact(sessions.tokens(since: today))).font(.system(size: 26, weight: .semibold).monospacedDigit())
        Text("tokens today").font(.system(size: 10)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          Label(SessionsView.compact(sessions.tokens(tool: "Claude Code", since: today)), systemImage: "circle.fill").foregroundStyle(.orange)
          Label(SessionsView.compact(sessions.tokens(tool: "Codex", since: today)), systemImage: "circle.fill").foregroundStyle(.teal)
        }.font(.system(size: 10, weight: .medium)).labelStyle(DotLabel())
      } else {
        Text("Claude Code and Codex usage.").font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("Turn on") { sessions.enabled = true }
      }
    }
    .onAppear { sessions.scan() }
  }
  struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
      HStack(spacing: 3) { configuration.icon.font(.system(size: 5)); configuration.title.foregroundStyle(.white) }
    }
  }
}

/// Your next event with a countdown and a Join button for calls; wide, the next three.
struct UpNextTile: View {
  @ObservedObject var controller: PetController
  @ObservedObject var contexts: ContextAdapters
  var span: Int
  var body: some View {
    let upcoming = Array(contexts.events.filter { $0.endDate > Date() && !$0.isAllDay }.prefix(span == 2 ? 3 : 1))
    Tile(title: "Next up", icon: "calendar", tint: Color(red: 0.39, green: 0.82, blue: 1)) {
      if !controller.organization.consent.calendar {
        Text("See your next events.").font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("Turn on in Settings") { controller.tab = "Settings" }
      } else if upcoming.isEmpty {
        Text("Nothing coming up.").font(.system(size: 11)).foregroundStyle(.secondary)
      } else {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          if span == 1, let event = upcoming.first {
            VStack(alignment: .leading, spacing: 1) {
              Self.countdownText(event.startDate, now: context.date)
              Text(event.title ?? "Event").font(.system(size: 13.5, weight: .semibold)).lineLimit(1).padding(.top, 2)
              Text(Self.detail(event)).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
          } else {
            VStack(alignment: .leading, spacing: 7) {
              ForEach(upcoming, id: \.eventIdentifier) { event in
                HStack(spacing: 7) {
                  RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: event.calendar?.color ?? .systemBlue)).frame(width: 3, height: 26)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(event.title ?? "Event").font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(Self.when(event.startDate, now: context.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
        }
        Spacer(minLength: 0)
        if let event = upcoming.first, let link = Self.callLink(event) {
          HStack {
            Spacer()
            Button("Join") { NSWorkspace.shared.open(link) }.buttonStyle(PillButtonStyle(tint: .accentColor))
              .help("Join \(link.host ?? "the call")")
          }
        }
      }
    }
  }
  static func when(_ date: Date, now: Date) -> String {
    let minutes = Int(date.timeIntervalSince(now) / 60)
    if minutes <= 0 { return "Now" }
    if minutes < 60 { return "in \(minutes) min" }
    return Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
  }
  /// The countdown, large, with its unit small: "12 min".
  static func countdownText(_ date: Date, now: Date) -> Text {
    let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
    let big = Font.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()
    let small = Font.system(size: 15, weight: .semibold, design: .rounded)
    if minutes <= 0 { return Text("Now").font(big) }
    if minutes < 60 { return Text("\(minutes)").font(big) + Text(" min").font(small).foregroundColor(Color.white.opacity(0.55)) }
    if minutes < 180 { return Text("\(minutes / 60)").font(big) + Text("h ").font(small) + Text("\(minutes % 60)").font(big) + Text("m").font(small) }
    return Text(date.formatted(date: .omitted, time: .shortened)).font(big)
  }
  /// Where and with how many: "Zoom · 4 people".
  static func detail(_ event: EKEvent) -> String {
    let place = callLink(event)?.host.map(service) ?? event.location ?? event.startDate.formatted(date: .omitted, time: .shortened)
    let people = event.attendees?.count ?? 0
    return [place, people > 1 ? "\(people) people" : nil].compactMap { $0 }.joined(separator: " · ")
  }
  /// "12 min", "1h 20m", or the time when it's further off.
  static func countdown(_ date: Date, now: Date) -> String {
    let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
    if minutes <= 0 { return "Now" }
    if minutes < 60 { return "\(minutes) min" }
    if minutes < 180 { return "\(minutes / 60)h \(minutes % 60)m" }
    return date.formatted(date: .omitted, time: .shortened)
  }
  /// The name of the service a call link goes to.
  static func service(_ host: String) -> String {
    let names = ["zoom.us": "Zoom", "meet.google.com": "Google Meet", "teams.microsoft.com": "Teams", "webex.com": "Webex",
      "whereby.com": "Whereby", "facetime.apple.com": "FaceTime", "around.co": "Around"]
    return names.first { host.hasSuffix($0.key) }?.value ?? host
  }
  /// A video call link in the event, if there is one.
  static func callLink(_ event: EKEvent) -> URL? {
    if let url = event.url, url.scheme == "https" { return url }
    let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
    guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let links = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).filter { $0.scheme == "https" }
    let calls = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "whereby.com", "facetime.apple.com", "around.co"]
    return links.first { url in calls.contains { url.host?.hasSuffix($0) == true } } ?? links.first
  }
}

struct MacHealthTile: View {
  @ObservedObject var controller: PetController
  var body: some View {
    Button { controller.tab = "Health" } label: {
      MacHealthCard(controller: controller)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchSurface(radius: 16))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).help("See what's using your Mac")
  }
}

/// The song and what's next, as in the mockup; without a queue, the controls.
struct NowPlayingTile: View {
  @ObservedObject var media: NowPlayingController
  var span: Int
  var body: some View {
    Tile(title: media.upNext.isEmpty ? "Now playing" : "Up next", icon: "music.note") {
      HStack(spacing: 10) {
        artwork.frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 1) {
          Text(media.track?.title ?? "Not playing").font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Text(media.track?.artist ?? "Spotify or Apple Music").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.top, 2)
      if media.upNext.isEmpty {
        Spacer(minLength: 0)
        HStack(spacing: span == 2 ? 14 : 8) {
          Spacer(minLength: 0)
          Button(action: media.previous) { Image(systemName: "backward.fill").font(.system(size: 12)) }
            .buttonStyle(NotchIconButtonStyle(size: 26)).accessibilityLabel("Previous track")
          Button(action: media.playPause) { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15)) }
            .buttonStyle(NotchIconButtonStyle(size: 30, prominent: true)).accessibilityLabel(media.isPlaying ? "Pause" : "Play")
          Button(action: media.next) { Image(systemName: "forward.fill").font(.system(size: 12)) }
            .buttonStyle(NotchIconButtonStyle(size: 26)).accessibilityLabel("Next track")
          Spacer(minLength: 0)
        }
      } else {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(Array(media.upNext.prefix(span == 2 ? 3 : 2).enumerated()), id: \.offset) { index, item in
            Text("\(index + 2) · \(item.title)").font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
          }
        }
        .padding(.top, 4)
      }
    }
    .onAppear { media.active = true }
  }
  private var artwork: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16))
      if let art = media.artwork { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
      else { Image(systemName: "music.note").foregroundStyle(Color.white.opacity(0.3)) }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

struct PlaylistsTile: View {
  @ObservedObject var library: MusicLibrary
  @ObservedObject var spotify: SpotifyAccount
  @ObservedObject var appleMusic: AppleMusicLibrary
  var body: some View {
    let items = Array((spotify.playlists + appleMusic.playlists).prefix(8))
    Tile(title: "Playlists", icon: "music.note.list") {
      if items.isEmpty {
        Text(spotify.connected || appleMusic.connected ? "Loading your playlists…" : "Connect Spotify or Apple Music from Home's playlist button.")
          .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(items) { playlist in
              Button { library.play(playlist) } label: {
                Group {
                  if playlist.source == .spotify {
                    RemoteCover(url: playlist.imageURL)
                  } else if let image = appleMusic.covers[playlist.reference] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                  } else {
                    CoverPlaceholder().onAppear { appleMusic.loadCover(playlist) }
                  }
                }
                .frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 9))
              }.buttonStyle(.plain).help("Play \(playlist.name)").accessibilityLabel("Play \(playlist.name)")
            }
          }
        }
      }
    }
    .onAppear(perform: library.refresh)
  }
}

struct ClockTile: View {
  var body: some View {
    TimelineView(.everyMinute) { context in
      Tile(title: context.date.formatted(.dateTime.weekday(.wide)), icon: "clock.fill") {
        Text(UserDefaults.standard.bool(forKey: "clock24") ? context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) : context.date.formatted(date: .omitted, time: .shortened))
          .font(.system(size: 32, weight: .semibold).monospacedDigit())
          .lineLimit(1).minimumScaleFactor(0.6)
        Text(context.date.formatted(.dateTime.month(.wide).day())).font(.system(size: 12)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        let hour = Calendar.current.component(.hour, from: context.date)
        Text(hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening").font(.system(size: 10)).foregroundStyle(.secondary)
      }
    }
  }
}

struct DownloadsTile: View {
  var span: Int
  @State private var files: [URL] = []
  var body: some View {
    Tile(title: "Downloads", icon: "arrow.down.circle.fill") {
      if files.isEmpty {
        Text("Nothing here yet.").font(.system(size: 11)).foregroundStyle(.secondary)
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: span), alignment: .leading, spacing: 6) {
          ForEach(files.prefix(span == 2 ? 6 : 3), id: \.self) { file in
            Button { NSWorkspace.shared.open(file) } label: {
              HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 18, height: 18)
                Text(file.lastPathComponent).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
              }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrag { NSItemProvider(object: file as NSURL) }
            .help("Open, or drag it somewhere")
          }
        }
      }
    }
    .task { files = await Self.recent() }
  }
  static func recent() async -> [URL] {
    await Task.detached(priority: .utility) { () -> [URL] in
      let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
      let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
      let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
      func date(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: Set(keys))
        return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
      }
      return Array(items.sorted { date($0) > date($1) }.prefix(6))
    }.value
  }
}

struct QuickNoteTile: View {
  @ObservedObject var hub: HubController
  @State private var text = ""
  @State private var saving: Task<Void, Never>?
  var body: some View {
    Tile(title: "Quick note", icon: "note.text") {
      TextEditor(text: $text).font(.system(size: 11)).scrollContentBackground(.hidden)
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
          if text.isEmpty {
            Text("Jot something down…").font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 5).allowsHitTesting(false)
          }
        }
        .onChange(of: text) { value in
          saving?.cancel()
          saving = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            hub.saved.note = String(value.prefix(5000))
            hub.save()
          }
        }
    }
    .onAppear { text = hub.saved.note ?? "" }
  }
}
