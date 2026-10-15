import AppKit
import MoltCore
import SwiftUI

/// Start typing with the notch open to jump anywhere: pages, widgets, actions and settings.
/// Arrows move, Return opens, Escape goes back, and holding Option shows each shortcut.
struct JumpView: View {
  @ObservedObject var coordinator: IslandCoordinator
  @Binding var query: String
  @FocusState private var focused: Bool
  static func height(results: Int) -> CGFloat { 104 + CGFloat(max(1, results)) * 50 }
  var body: some View {
    let results = coordinator.jumpResults(query)
    let selected = results.isEmpty ? 0 : min(coordinator.jumpSelection, results.count - 1)
    VStack(spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
        TextField("Search Molt", text: $query).textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
          .focused($focused)
          .onSubmit { if results.indices.contains(selected) { run(results[selected]) } }
          .onChange(of: query) { value in
            coordinator.jumpSelection = 0
            if value.isEmpty { coordinator.jump = nil }
          }
        // Molt peeks at what you're typing.
        CreatureView(appearance: coordinator.controller.companion.appearance, mood: "idle", followsPointer: false, gaze: (-1, 0))
          .frame(width: 24, height: 22)
          .onTapGesture { coordinator.jump = nil }
          .help("Close search (esc)")
      }
      .padding(.horizontal, 12).frame(height: 40)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
      VStack(spacing: 0) {
        if results.isEmpty {
          HStack(spacing: 10) {
            Image(systemName: "questionmark.circle").font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.35)).frame(width: 30)
            Text("Nothing called \u{201C}\(query)\u{201D}").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
            Spacer()
          }.frame(height: 50)
        }
        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
          row(item, selected: index == selected)
            .onTapGesture { run(item) }
            .onHover { if $0 { coordinator.jumpSelection = index } }
        }
      }
      Spacer(minLength: 0)
      HStack(spacing: 16) {
        hint("↑↓", "move"); hint("↩", "open"); hint("⌥", "hold for shortcuts")
        Spacer()
        Text("Just start typing when the notch is open").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.3))
      }
    }
    .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 12)
    .onAppear { focused = true; moveCursorToEnd() }
    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: selected)
  }
  private func row(_ item: JumpItem, selected: Bool) -> some View {
    let symbol = JumpCatalog.symbol(item.id)
    // Focus gets its green; everything else a quiet tile.
    let green = symbol.1 == .green
    return HStack(spacing: 12) {
      Image(systemName: symbol.0).font(.system(size: 14, weight: .semibold)).foregroundStyle(green ? Color(red: 0.36, green: 0.8, blue: 0.55) : Color.white.opacity(0.8))
        .frame(width: 30, height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(green ? Color(red: 0.36, green: 0.8, blue: 0.55).opacity(0.18) : Color.white.opacity(0.07)))
      VStack(alignment: .leading, spacing: 1) {
        highlighted(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        Text(item.subtitle).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
      }
      Spacer(minLength: 6)
      if let shortcut = selected ? "↩" : item.shortcut {
        Text(shortcut).font(.system(size: 10.5, weight: .semibold)).tracking(0.3)
          .foregroundStyle(Color.white.opacity(coordinator.optionHeld || selected ? 0.75 : 0.45))
          .padding(.horizontal, 6).frame(height: 18).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(coordinator.optionHeld ? 0.14 : 0.08)))
      }
    }
    .padding(.horizontal, 12).frame(height: 50)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(selected ? 0.09 : 0)))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }
  /// As in the mockup: what comes before your match in bold, the match underlined in the accent.
  private func highlighted(_ title: String) -> Text {
    guard let range = JumpSearch.highlight(query, in: title) else { return Text(title) }
    return Text(title[..<range.lowerBound]).fontWeight(.heavy) + Text(title[range]).underline(color: .accentColor) + Text(title[range.upperBound...])
  }
  private func hint(_ key: String, _ label: String) -> some View {
    HStack(spacing: 4) {
      Text(key).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 5).frame(height: 16)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
      Text(label).font(.system(size: 10))
    }.foregroundStyle(Color.white.opacity(0.4))
  }
  private func run(_ item: JumpItem) {
    let text = query
    coordinator.jump = nil
    JumpCatalog.perform(item.id, query: text, coordinator: coordinator)
  }
  /// The first letter came from the key that opened search; keep typing after it, not before.
  private func moveCursorToEnd() {
    DispatchQueue.main.async {
      if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.setSelectedRange(NSRange(location: editor.string.count, length: 0)) }
    }
  }
}

/// Everything search can find, and what each one does.
@MainActor enum JumpCatalog {
  private static var shortcuts: [String: String] {
    Dictionary(IslandCoordinator.shortcutList.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
  }
  static func items(controller: PetController) -> [JumpItem] {
    let keys = shortcuts
    var items: [JumpItem] = []
    let focus = controller.openFocus
    if let focus {
      items.append(JumpItem(id: focus.lastResumed == nil ? "focus:resume" : "focus:pause", title: focus.lastResumed == nil ? "Resume focus" : "Pause focus", subtitle: "Focus", keywords: ["timer", "pomodoro"]))
      items.append(JumpItem(id: "focus:stop", title: "Stop focus", subtitle: "Focus", keywords: ["timer", "end"]))
      items.append(JumpItem(id: "page:Focus", title: "Focus session", subtitle: "\(Int(controller.focusClock(focus, at: Date()) / 60)) minutes left", keywords: ["timer"]))
    } else {
      let minutes = UserDefaults.standard.object(forKey: "focusMinutes") as? Int ?? 25
      items.append(JumpItem(id: "focus:start", title: "Start a focus session", subtitle: "\(minutes) minutes · \(controller.petName) works with you", keywords: ["timer", "pomodoro", "work", "study"]))
      items.append(JumpItem(id: "page:Focus", title: "Focus", subtitle: "Choose how long", keywords: ["timer", "pomodoro"]))
    }
    let pages: [(String, String, String, [String], String?)] = [
      ("page:Notch", "Home", "Music, calendar and your Mac", ["music", "calendar", "today"], "⌘⇧↩"),
      ("page:Hub", "Hub", "Your widgets", ["widgets"], keys["Hub"]),
      ("page:Play", "Play", "Games and care for \(controller.petName)", ["games", "feed", "pet"], nil),
      ("page:Molting", "Molting", "Friends and hangouts", ["friends", "hangout", "social"], nil),
      ("page:Ask Molt", "Chat", "Ask \(controller.petName) anything", ["ask", "assistant", "ai"], keys["Chat"]),
      ("lens", "Ask about your screen", "Lens", ["lens", "screenshot", "explain"], "⌘⇧L"),
      ("agents:Agents", "Agents", "What's running, and what needs you", ["claude", "codex", "terminal"], keys["Agents"]),
      ("agents:Usage", "Plan usage", "Claude and Codex limits", ["limits", "tokens", "claude", "codex"], keys["Plan usage"]),
      ("agents:GitHub", "GitHub", "Pull requests, checks and your streak", ["pr", "pull", "ci"], keys["GitHub"]),
      ("page:AddWidget", "Add a widget", "Hub", ["widget", "new", "gallery"], nil),
      ("page:Wardrobe", "Wardrobe", "Outfits for \(controller.petName)", ["outfit", "clothes", "hat"], keys["Wardrobe"]),
      ("page:Health", "Mac health", "What's using your Mac", ["battery", "cpu", "memory", "storage"], nil),
      ("page:Settings", "Settings", "Molt, the notch and connections", ["preferences", "options"], nil),
      ("page:NotchSettings", "Notch layout", "Settings › Notch: tabs, order, hover", ["tabs", "order", "hover", "arrange"], nil),
    ]
    let prefs = NotchPrefs.shared
    items += pages.filter { prefs.shows(String($0.0.split(separator: ":").last ?? "")) && ($0.0 != "lens" || prefs.has("lens")) }
      .map { JumpItem(id: $0.0, title: $0.1, subtitle: $0.2, keywords: $0.3, shortcut: $0.4) }
    items.append(JumpItem(id: "settings", title: "All settings", subtitle: "The Settings window", keywords: ["preferences", "options", "permissions", "shortcuts"], shortcut: "⌘,"))
    let media = controller.hub.media
    if media.track != nil {
      items.append(JumpItem(id: "music:toggle", title: media.isPlaying ? "Pause music" : "Play music", subtitle: media.track?.title ?? "Music", keywords: ["song", "spotify"]))
      items.append(JumpItem(id: "music:next", title: "Next track", subtitle: "Music", keywords: ["skip", "song"]))
    }
    let paused = controller.organization.consent.paused
    items.append(JumpItem(id: "tracking", title: paused ? "Resume app tracking" : "Pause app tracking", subtitle: "Action", keywords: ["privacy", "usage"]))
    items += QuickActions.catalog.filter { !["focus", "lens"].contains($0.id) }
      .map { JumpItem(id: "action:\($0.id)", title: $0.title, subtitle: "Action", keywords: []) }
    let placed = Set(controller.hub.layout.map(\.kind))
    items += WidgetKind.catalog.filter { prefs.shows($0.id) }.map {
      JumpItem(id: "widget:\($0.id)", title: "\($0.title) widget", subtitle: placed.contains($0.id) ? "Hub" : "Add to your Hub", keywords: [$0.blurb])
    }
    return items
  }
  static func symbol(_ id: String) -> (String, Color) {
    let (kind, value) = split(id)
    switch kind {
    case "focus": return ("timer", .green)
    case "page":
      switch value {
      case "Focus": return ("timer", .green)
      case "Notch": return ("house.fill", .white)
      case "Hub": return ("square.grid.2x2.fill", .white)
      case "Play": return ("gamecontroller.fill", .white)
      case "Molting": return ("person.2.fill", .white)
      case "Ask Molt": return ("bubble.left.fill", .accentColor)
      case "Wardrobe": return ("tshirt.fill", .pink)
      case "Health": return ("cpu", .white)
      default: return ("gearshape.fill", .gray)
      }
    case "lens": return ("text.viewfinder", .accentColor)
    case "agents": return value == "GitHub" ? ("arrow.triangle.pull", .white) : value == "Usage" ? ("gauge.with.dots.needle.67percent", .orange) : ("terminal.fill", .white)
    case "music": return ("music.note", .pink)
    case "tracking": return ("pause.circle.fill", .white)
    case "action":
      let action = QuickActions.catalog.first { $0.id == value }
      return (action?.symbol ?? "bolt.fill", action?.tint == .white ? .white : action?.tint ?? .yellow)
    case "widget": return (WidgetKind.find(value)?.symbol ?? "square.grid.2x2", .accentColor)
    default: return ("magnifyingglass", .white)
    }
  }
  static func perform(_ id: String, query: String, coordinator: IslandCoordinator) {
    let controller = coordinator.controller
    let (kind, value) = split(id)
    switch kind {
    case "focus":
      switch value {
      case "start":
        let minutes = JumpSearch.minutes(in: query) ?? UserDefaults.standard.object(forKey: "focusMinutes") as? Int ?? 25
        controller.focus(minutes: minutes)
        controller.tab = "Focus"
      default: controller.changeFocus(value)
      }
    case "page": controller.tab = value
    case "lens": coordinator.startLens()
    case "settings": SettingsWindow.shared.show()
    case "agents": UserDefaults.standard.set(value == "Agents" ? "Live" : value, forKey: "agentsTab"); controller.tab = "Agents"
    case "music": value == "next" ? controller.hub.media.next() : controller.hub.media.playPause()
    case "tracking":
      controller.updateOrganization { $0.consent.paused.toggle() }
      controller.configureContext()
    case "action": controller.hub.actions.run("action:\(value)")
    case "widget":
      if !controller.hub.layout.contains(where: { $0.kind == value }), let widget = WidgetKind.find(value) { controller.hub.add(widget) }
      controller.tab = "Hub"
    default: break
    }
  }
  private static func split(_ id: String) -> (String, String) {
    guard let colon = id.firstIndex(of: ":") else { return (id, "") }
    return (String(id[..<colon]), String(id[id.index(after: colon)...]))
  }
}
