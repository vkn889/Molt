import AppKit
import MoltCore
import SwiftUI

struct Tile<Content: View>: View {
  var title: String
  var icon: String
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 16))
  }
}

struct FocusTile: View {
  @ObservedObject var controller: PetController
  @State private var minutes = 25
  var body: some View {
    Tile(title: "Focus", icon: "timer") {
      if let session = controller.organization.sessions.first(where: { $0.finished == nil }) {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let elapsed = session.duration(at: context.date)
          let remaining = session.target > 0 ? max(0, session.target - elapsed) : elapsed
          Text(Self.clock(remaining)).font(.system(size: 30, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
          Text(session.lastResumed == nil ? "Paused" : session.target > 0 ? "remaining" : "elapsed")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        HStack(spacing: 4) {
          icon(session.lastResumed == nil ? "play.fill" : "pause.fill", session.lastResumed == nil ? "Resume" : "Pause") {
            controller.changeFocus(session.lastResumed == nil ? "resume" : "pause")
          }
          icon("plus", "Add 5 minutes") { controller.changeFocus("extend") }
          icon("stop.fill", "Stop") { controller.changeFocus("stop") }
        }
      } else {
        Text(Self.clock(Double(minutes * 60))).font(.system(size: 30, weight: .semibold).monospacedDigit())
          .foregroundStyle(Color.white.opacity(0.85))
        HStack(spacing: 4) {
          ForEach([15, 25, 50], id: \.self) { value in
            Button { minutes = value } label: {
              Text("\(value)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(minutes == value ? Color.white : Color.white.opacity(0.5))
                .frame(width: 28, height: 20)
                .background(Capsule().fill(Color.white.opacity(minutes == value ? 0.16 : 0.05)))
            }.buttonStyle(.plain).accessibilityLabel("\(value) minutes")
          }
        }
        Spacer(minLength: 0)
        icon("play.fill", "Start focus") { controller.focus(minutes: minutes) }
      }
    }
  }
  private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
      .buttonStyle(NotchIconButtonStyle(size: 28, prominent: true))
      .background(Circle().fill(Color.white.opacity(0.08)))
      .help(label).accessibilityLabel(label)
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
  var body: some View {
    Tile(title: hub.saved.place?.name ?? "Weather", icon: "location.fill") {
      if let weather = hub.weather, !editing {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22))
          Text(Measurement(value: weather.temperature, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))))
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
  static let catalog: [WidgetKind] = [
    WidgetKind(id: "focus", title: "Focus", symbol: "timer", spans: [1], blurb: "A focus timer"),
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
    WidgetKind(id: "upNext", title: "Up next", symbol: "calendar", spans: [1, 2], blurb: "Your next events"),
    WidgetKind(id: "macHealth", title: "Mac health", symbol: "cpu", spans: [1], blurb: "Battery, CPU, memory, storage"),
    WidgetKind(id: "nowPlaying", title: "Now playing", symbol: "music.note", spans: [1, 2], blurb: "Music controls"),
    WidgetKind(id: "playlists", title: "Playlists", symbol: "music.note.list", spans: [2], blurb: "Tap a cover to play"),
    WidgetKind(id: "clock", title: "Clock", symbol: "clock.fill", spans: [1], blurb: "Time and date"),
    WidgetKind(id: "downloads", title: "Downloads", symbol: "arrow.down.circle.fill", spans: [1, 2], blurb: "Your latest downloads"),
    WidgetKind(id: "quickNote", title: "Quick note", symbol: "note.text", spans: [1, 2], blurb: "A scratchpad that saves itself"),
    WidgetKind(id: "webSearch", title: "Web search", symbol: "magnifyingglass", spans: [1, 2], blurb: "Search from the notch"),
  ]
  static func find(_ id: String) -> WidgetKind? { catalog.first { $0.id == id } }
}

/// Renders one placed widget.
struct WidgetView: View {
  var widget: HubWidget
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  var body: some View {
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

struct ShortcutsTile: View {
  var widget: HubWidget
  @ObservedObject var actions: QuickActions
  var body: some View {
    let columns = widget.span == 2 ? 4 : 2
    let items = Array(widget.items.prefix(columns * 2))
    VStack(alignment: .leading, spacing: 6) {
      Grid(horizontalSpacing: 6, verticalSpacing: 6) {
        ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
          GridRow {
            ForEach(items[start..<min(start + columns, items.count)], id: \.self) { item in
          Button { actions.run(item) } label: {
            VStack(spacing: 3) {
              if let icon = actions.icon(item) {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
              } else {
                let symbol = actions.symbol(item)
                // Multi-layer symbols would take the page's white for their extra layers.
                Image(systemName: symbol.0).font(.system(size: 16, weight: .medium))
                  .symbolRenderingMode(.palette)
                  .foregroundStyle(symbol.0.hasSuffix("circle.fill") ? Color.white : symbol.1, symbol.1, symbol.1)
              }
              Text(actions.title(item)).font(.system(size: 9, weight: .medium)).lineLimit(1).foregroundStyle(Color.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(actions.isActive(item) ? 0.18 : 0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 11))
          }
          .buttonStyle(BareButtonStyle()).help(actions.title(item)).accessibilityLabel(actions.title(item))
            }
          }
        }
      }
      if items.isEmpty {
        Text("Edit the Hub to choose shortcuts.").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if actions.confirmingTrash {
        HStack(spacing: 6) {
          Text("Empty Trash?").font(.system(size: 10, weight: .semibold))
          Button("Empty", action: actions.emptyTrash).foregroundStyle(.red)
          Button("Cancel") { actions.confirmingTrash = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
        }
      } else if !actions.status.isEmpty {
        Text(actions.status).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 16))
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

struct MoltTile: View {
  @ObservedObject var controller: PetController
  var body: some View {
    Tile(title: controller.petName, icon: "leaf.fill") {
      HStack(spacing: 8) {
        CreatureView(appearance: controller.companion.appearance, mood: controller.isResting ? "sleeping" : controller.mood)
          .frame(width: 42, height: 39)
        VStack(alignment: .leading, spacing: 4) {
          bar("hunger", .orange)
          bar("energy", .yellow)
          bar("affection", .pink)
        }
      }
      Spacer(minLength: 0)
      Button("Play") { controller.tab = "Play" }
    }
  }
  private func bar(_ key: String, _ tint: Color) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.12))
        Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, (controller.state.stats[key] ?? 0) / 100)))
      }
    }.frame(height: 4)
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

struct UpNextTile: View {
  @ObservedObject var controller: PetController
  @ObservedObject var contexts: ContextAdapters
  var span: Int
  var body: some View {
    let upcoming = contexts.events.filter { $0.endDate > Date() }.prefix(span == 2 ? 3 : 2)
    Tile(title: "Up next", icon: "calendar") {
      if !controller.organization.consent.calendar {
        Text("See your next events.").font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("Turn on in Settings") { controller.tab = "Settings" }
      } else if upcoming.isEmpty {
        Text("Nothing coming up.").font(.system(size: 11)).foregroundStyle(.secondary)
      } else {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(upcoming), id: \.eventIdentifier) { event in
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
    }
  }
  static func when(_ date: Date, now: Date) -> String {
    let minutes = Int(date.timeIntervalSince(now) / 60)
    if minutes <= 0 { return "Now" }
    if minutes < 60 { return "in \(minutes) min" }
    return Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
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

struct NowPlayingTile: View {
  @ObservedObject var media: NowPlayingController
  var span: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        artwork.frame(width: span == 2 ? 72 : 46, height: span == 2 ? 72 : 46)
        VStack(alignment: .leading, spacing: 2) {
          Text(media.track?.title ?? "Not playing").font(.system(size: 12, weight: .semibold)).lineLimit(2)
          Text(media.track?.artist ?? "Spotify or Apple Music").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
      HStack(spacing: span == 2 ? 14 : 6) {
        Spacer(minLength: 0)
        Button(action: media.previous) { Image(systemName: "backward.fill").font(.system(size: 12)) }
          .buttonStyle(NotchIconButtonStyle(size: 28)).accessibilityLabel("Previous track")
        Button(action: media.playPause) { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16)) }
          .buttonStyle(NotchIconButtonStyle(size: 32, prominent: true)).accessibilityLabel(media.isPlaying ? "Pause" : "Play")
        Button(action: media.next) { Image(systemName: "forward.fill").font(.system(size: 12)) }
          .buttonStyle(NotchIconButtonStyle(size: 28)).accessibilityLabel("Next track")
        Spacer(minLength: 0)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 16))
    .onAppear { media.active = true }
  }
  private var artwork: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.16))
      if let art = media.artwork { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
      else { Image(systemName: "music.note").foregroundStyle(Color.white.opacity(0.3)) }
    }
    .clipShape(RoundedRectangle(cornerRadius: 9))
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
        Text(context.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 32, weight: .semibold).monospacedDigit())
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
