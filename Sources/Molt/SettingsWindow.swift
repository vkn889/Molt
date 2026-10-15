import AVFoundation
import AppKit
import Carbon
import CoreBluetooth
import EventKit
import MoltCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// All of Molt's settings, in a window of their own: the notch's Settings page has the everyday
/// ones and opens this for everything else.
@MainActor final class SettingsWindow {
  static let shared = SettingsWindow()
  private var window: NSWindow?
  weak var controller: PetController?
  weak var coordinator: IslandCoordinator?
  var replayTour: () -> Void = {}
  private let model = SettingsModel()
  func show(_ section: String? = nil) {
    guard let controller, let coordinator else { return }
    if let section, let found = SettingsSection(rawValue: section) { model.section = found }
    if window == nil {
      let view = SettingsRoot(model: model, controller: controller, coordinator: coordinator, prefs: coordinator.prefs, hub: controller.hub, replayTour: { [weak self] in self?.replayTour() })
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
      window.title = "Molt Settings"
      window.titlebarAppearsTransparent = true
      window.contentView = NSHostingView(rootView: view)
      window.contentMinSize = NSSize(width: 680, height: 460)
      window.isReleasedWhenClosed = false
      window.center()
      self.window = window
    }
    coordinator.collapse()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

@MainActor final class SettingsModel: ObservableObject {
  @Published var section: SettingsSection = .general
}

enum SettingsSection: String, CaseIterable, Identifiable {
  case general, appearance, notch, live, hub, features, focus, music, clipboard, agents, calendar, shortcuts, molt, privacy, account, data, about
  var id: String { rawValue }
  var title: String {
    switch self {
    case .live: return "Live activities"
    case .molt: return "Molt"
    case .privacy: return "Privacy & permissions"
    default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
  }
  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .appearance: return "paintpalette"
    case .notch: return "rectangle.topthird.inset.filled"
    case .live: return "dot.radiowaves.left.and.right"
    case .hub: return "square.grid.2x2"
    case .features: return "puzzlepiece.extension"
    case .focus: return "timer"
    case .music: return "music.note"
    case .clipboard: return "doc.on.clipboard"
    case .agents: return "terminal"
    case .calendar: return "calendar"
    case .shortcuts: return "keyboard"
    case .molt: return "leaf"
    case .privacy: return "hand.raised"
    case .account: return "person.crop.circle"
    case .data: return "externaldrive"
    case .about: return "info.circle"
    }
  }
}

struct SettingsRoot: View {
  @ObservedObject var model: SettingsModel
  @ObservedObject var controller: PetController
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var prefs: NotchPrefs
  @ObservedObject var hub: HubController
  var replayTour: () -> Void
  var body: some View {
    NavigationSplitView {
      List(SettingsSection.allCases, selection: Binding(get: { model.section }, set: { if let value = $0 { model.section = value } })) { section in
        Label(section.title, systemImage: section.symbol).tag(section)
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 200)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 10) {
            if model.section == .molt || model.section == .general {
              CreatureView(appearance: controller.companion.appearance, mood: "happy", followsPointer: false).frame(width: 34, height: 31)
            }
            Text(model.section.title).font(.system(size: 22, weight: .bold))
          }
          .padding(.bottom, 14)
          section
        }
        .padding(28)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(minWidth: 680, minHeight: 460)
  }
  @ViewBuilder private var section: some View {
    switch model.section {
    case .general: GeneralSettings(controller: controller, prefs: prefs, replayTour: replayTour)
    case .appearance: AppearanceSettings(controller: controller, prefs: prefs)
    case .notch: NotchWindowSettings(coordinator: coordinator, prefs: prefs)
    case .live: LiveSettings(prefs: prefs)
    case .hub: HubSettings(hub: hub, prefs: prefs)
    case .features: FeatureSettings(prefs: prefs)
    case .focus: FocusSettings(controller: controller, prefs: prefs)
    case .music: MusicSettings(controller: controller, spotify: hub.library.spotify, appleMusic: hub.library.appleMusic)
    case .clipboard: ClipboardSettings(clipboard: hub.clipboard, prefs: prefs)
    case .agents: AgentsSettings(controller: controller, coordinator: coordinator, prefs: prefs)
    case .calendar: CalendarSettings(controller: controller, contexts: controller.contexts, reminders: hub.reminders)
    case .shortcuts: ShortcutSettings(coordinator: coordinator)
    case .molt: MoltSettings(controller: controller, prefs: prefs)
    case .privacy: PrivacySettings(controller: controller, hub: hub, prefs: prefs)
    case .account: AccountSettings(controller: controller, account: controller.account, coordinator: coordinator)
    case .data: DataSettings(controller: controller, hub: hub)
    case .about: AboutSettings()
    }
  }
}

// MARK: Building blocks

/// A rounded group of rows, like System Settings.
struct SettingsGroup<Content: View>: View {
  var title: String?
  var footer: String?
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let title { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
      VStack(alignment: .leading, spacing: 0) { content }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
      if let footer { Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true) }
    }
    .padding(.bottom, 18)
  }
}

/// One row: a title, an optional explanation, and its control on the right.
struct SettingsRow<Control: View>: View {
  var title: String
  var detail: String? = nil
  @ViewBuilder var control: Control
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 13))
        if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
      }
      Spacer(minLength: 8)
      control
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
  }
}

struct SettingsToggle: View {
  var title: String
  var detail: String? = nil
  @Binding var isOn: Bool
  var body: some View {
    SettingsRow(title: title, detail: detail) { Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small) }
  }
}

private func petPref<T>(_ controller: PetController, _ key: WritableKeyPath<PetPreferences, T>) -> Binding<T> {
  Binding(get: { controller.companion.preferences[keyPath: key] }, set: { value in controller.changeCompanion { $0.preferences[keyPath: key] = value } })
}

// MARK: Sections

struct GeneralSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var prefs: NotchPrefs
  var replayTour: () -> Void
  var body: some View {
    SettingsGroup {
      SettingsToggle(title: "Open Molt when you log in", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { controller.setLogin($0) }))
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Wake-up animation", detail: "Molt wakes up and waves when you open it after quitting.", isOn: $prefs.wakeAnimation)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Sounds", detail: "A little pop when you care for Molt, and chimes for timers.", isOn: petPref(controller, \.sound))
    }
    SettingsGroup(footer: "Molt follows your Mac's language. Change it for Molt alone in System Settings › General › Language & Region › Applications.") {
      SettingsRow(title: "Language") {
        Button("Open Language & Region") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!) }
      }
    }
    SettingsGroup {
      SettingsRow(title: "Show the tour again", detail: "Molt walks you through everything it can do.") { Button("Start tour", action: replayTour) }
    }
  }
}

struct AppearanceSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var prefs: NotchPrefs
  @AppStorage("islandAccent") private var accent = "blue"
  var body: some View {
    SettingsGroup {
      SettingsRow(title: "Molt's color") {
        HStack(spacing: 10) {
          ForEach(["sage", "ocean", "sunset", "violet"], id: \.self) { palette in
            swatch(MoltTheme.body(palette), selected: controller.companion.appearance.palette == palette) { controller.changeCompanion { $0.appearance.palette = palette } }
          }
        }
      }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Accent") {
        HStack(spacing: 10) {
          ForEach(["blue", "mint", "violet", "amber", "rose"], id: \.self) { value in
            swatch(MoltTheme.accent(value), selected: accent == value) { accent = value }
          }
        }
      }
    }
    SettingsGroup(title: "The notch") {
      SettingsRow(title: "Corners", detail: "How round the open notch's lower corners are.") {
        HStack { Text("Square").font(.caption).foregroundStyle(.secondary); Slider(value: $prefs.cornerScale, in: 0.5...1.5).frame(width: 140); Text("Round").font(.caption).foregroundStyle(.secondary) }
      }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Animation", detail: "How the notch opens, closes and changes size.") {
        HStack { Text("Gentle").font(.caption).foregroundStyle(.secondary); Slider(value: $prefs.animationSpeed, in: 0.7...1.4).frame(width: 140); Text("Snappy").font(.caption).foregroundStyle(.secondary) }
      }
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Reduce motion", detail: "Crossfades instead of springs, and Molt keeps still.", isOn: petPref(controller, \.reducedMotion))
    }
  }
  private func swatch(_ color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Circle().fill(color).frame(width: 20, height: 20)
        .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-4))
    }.buttonStyle(.plain)
  }
}

struct NotchWindowSettings: View {
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    SettingsGroup(title: "Opening") {
      SettingsToggle(title: "Open on hover", isOn: $coordinator.hoverToOpen)
      SettingsRow(title: "Wait before opening") {
        HStack { Slider(value: $prefs.hoverDelay, in: 0...1, step: 0.05).frame(width: 160).disabled(!coordinator.hoverToOpen); Text(prefs.hoverDelay < 0.05 ? "Instantly" : String(format: "%.2g s", prefs.hoverDelay)).monospacedDigit().frame(width: 60, alignment: .trailing) }
      }
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Open on click", isOn: $prefs.openOnClick)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Open by scrolling down on the notch", isOn: $prefs.openOnScroll)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Type to jump", detail: "With the notch open, start typing to search pages, widgets and actions.", isOn: $prefs.typeToJump)
    }
    SettingsGroup(title: "Size and place") {
      SettingsToggle(title: "Fit to content", detail: "Each page sizes the notch to what's on it.", isOn: $prefs.fitContent)
      Divider().padding(.leading, 12)
      SettingsRow(title: "Display") {
        Picker("Display", selection: $coordinator.displayChoice) {
          Text("Built-in, with the notch").tag(-1)
          Text("The one you're using").tag(-2)
          ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Text(screen.localizedName).tag(index) }
        }.labelsHidden().frame(width: 220)
      }
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Keep to itself in full screen", detail: "When an app is full screen, nothing shows beside the closed notch.", isOn: $prefs.hideInFullScreen)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Compact approvals", detail: "Agent approvals start as a pill beside the notch; hover for the full card.", isOn: $prefs.compactApprovals)
    }
    SettingsGroup(title: "Tabs", footer: "Drag to reorder. Home always shows.") {
      List {
        ForEach(NotchLayout.allTabs(order: prefs.tabOrder), id: \.self) { route in
          let tab = IslandView.tabs.first { $0.route == route }
          HStack {
            Label(tab?.title ?? route, systemImage: tab?.icon ?? "circle")
            Spacer()
            Toggle("", isOn: Binding(get: { route == "Notch" || !prefs.hiddenTabs.contains(route) }, set: { prefs.setTab(route, shown: $0) }))
              .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(route == "Notch")
          }
        }
        .onMove { from, to in
          var all = NotchLayout.allTabs(order: prefs.tabOrder)
          all.move(fromOffsets: from, toOffset: to)
          prefs.tabOrder = all
        }
      }
      .frame(height: 150).scrollDisabled(true)
    }
  }
}

struct LiveSettings: View {
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    SettingsGroup(title: "Beside the closed notch", footer: "When several are going at once, the highest shows first; swipe sideways on the notch for the rest. Drag to reorder.") {
      List {
        ForEach(prefs.priority, id: \.self) { kind in
          HStack {
            Circle().fill(NotchSettingsView.tint(kind)).frame(width: 8, height: 8)
            Text(kind.title)
            Spacer()
            Toggle("", isOn: Binding(get: { !prefs.liveOff.contains(kind.rawValue) }, set: { on in
              if on { prefs.liveOff.remove(kind.rawValue) } else { prefs.liveOff.insert(kind.rawValue) }
            })).labelsHidden().toggleStyle(.switch).controlSize(.small)
          }
        }
        .onMove { from, to in prefs.priority.move(fromOffsets: from, toOffset: to) }
      }
      .frame(height: 170).scrollDisabled(true)
    }
    SettingsGroup {
      SettingsToggle(title: "Molt reacts to the Mac", detail: "Sleepy on low battery, with a note when it gets there.", isOn: $prefs.petReacts)
    }
  }
}

struct HubSettings: View {
  @ObservedObject var hub: HubController
  @ObservedObject var prefs: NotchPrefs
  @AppStorage("clock24") private var clock24 = false
  @AppStorage("weatherFahrenheit") private var fahrenheit = Locale.current.measurementSystem == .us
  var body: some View {
    SettingsGroup(footer: "The notch grows a row when the Hub needs it.") {
      SettingsRow(title: "Rows") {
        Picker("Rows", selection: $hub.rows) { Text("1").tag(1); Text("2").tag(2); Text("3").tag(3) }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
      }
    }
    SettingsGroup(title: "Your widgets", footer: "Drag to reorder. Add more from the Hub's pencil, or the + here.") {
      List {
        ForEach(hub.layout) { widget in
          let kind = WidgetKind.find(widget.kind)
          HStack {
            Image(systemName: kind?.symbol ?? "square").foregroundStyle(kind?.tint ?? .accentColor).frame(width: 20)
            Text(kind?.title ?? widget.kind)
            Spacer()
            if (kind?.spans.count ?? 1) > 1 {
              Picker("", selection: Binding(get: { widget.span }, set: { span in if span != widget.span { hub.resize(widget) } })) {
                Text("Regular").tag(1); Text("Wide").tag(2)
              }.labelsHidden().pickerStyle(.segmented).frame(width: 130).disabled(!hub.canResize(widget))
            }
            Button { hub.remove(widget.id) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain)
          }
        }
        .onMove { from, to in
          var layout = hub.layout
          layout.move(fromOffsets: from, toOffset: to)
          if HubLayout.fits(layout, rows: hub.rows) { hub.setLayout(layout) }
        }
      }
      .frame(height: min(320, CGFloat(max(1, hub.layout.count)) * 34 + 16))
      HStack {
        Menu("Add a widget") {
          ForEach(WidgetKind.categories.filter { $0 != "All" && $0 != "New" }, id: \.self) { category in
            Section(category) {
              ForEach(WidgetKind.catalog.filter { $0.category == category && prefs.shows($0.id) && !hub.layout.map(\.kind).contains($0.id) }) { kind in
                Button(kind.title) { hub.add(kind) }
              }
            }
          }
        }.fixedSize()
        Spacer()
        Button("Reset to the defaults") { hub.setLayout(HubLayout.defaults) }
      }
      .padding(12)
    }
    SettingsGroup(title: "Widget options") {
      SettingsToggle(title: "24-hour clock", isOn: $clock24)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Weather in Fahrenheit", isOn: $fahrenheit)
      Divider().padding(.leading, 12)
      SettingsRow(title: "Water break every") { Stepper("\(hub.daily.waterEvery) min", value: Binding(get: { hub.daily.waterEvery }, set: { hub.daily.waterEvery = $0 }), in: 10...180, step: 5) }
      SettingsRow(title: "Stretch break every") { Stepper("\(hub.daily.stretchEvery) min", value: Binding(get: { hub.daily.stretchEvery }, set: { hub.daily.stretchEvery = $0 }), in: 10...240, step: 5) }
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Break reminders", isOn: Binding(get: { hub.daily.breaksOn }, set: { hub.daily.breaksOn = $0 }))
    }
  }
}

struct FeatureSettings: View {
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    SettingsGroup(footer: "Anything you switch off disappears from Molt: its page, widgets, shortcuts and everything beside the notch. Its settings are kept for when you switch it back on.") {
      ForEach(Array(NotchPrefs.features.enumerated()), id: \.element.id) { index, feature in
        if index > 0 { Divider().padding(.leading, 44) }
        HStack(spacing: 12) {
          Image(systemName: feature.symbol).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 20)
          VStack(alignment: .leading, spacing: 2) {
            Text(feature.title).font(.system(size: 13))
            Text(feature.detail).font(.system(size: 11)).foregroundStyle(.secondary)
          }
          Spacer()
          Toggle(feature.title, isOn: Binding(get: { prefs.has(feature.id) }, set: { prefs.set(feature.id, on: $0) }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
      }
    }
  }
}

struct FocusSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var prefs: NotchPrefs
  @AppStorage("focusMinutes") private var minutes = 25
  @AppStorage("focusSound") private var sound = "Glass"
  var body: some View {
    SettingsGroup {
      SettingsRow(title: "Default length") { Stepper("\(minutes) minutes", value: $minutes, in: 5...60, step: 5) }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Sound when it ends") {
        Picker("", selection: $sound) {
          Text("None").tag("")
          ForEach(["Glass", "Hero", "Purr", "Ping", "Submarine", "Funk"], id: \.self) { Text($0).tag($0) }
        }.labelsHidden().frame(width: 140)
          .onChange(of: sound) { value in NSSound(named: value)?.play() }
      }
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Show the time beside the notch", isOn: Binding(get: { !prefs.liveOff.contains("focus") }, set: { on in
        if on { prefs.liveOff.remove("focus") } else { prefs.liveOff.insert("focus") }
      }))
    }
    SettingsGroup(footer: "Focus pauses when your Mac sleeps and while Molt is closed, so time away never counts. Finished sessions give Molt energy.") { EmptyView() }
  }
}

struct MusicSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var spotify: SpotifyAccount
  @ObservedObject var appleMusic: AppleMusicLibrary
  @AppStorage("moltDances") private var dances = true
  var body: some View {
    SettingsGroup(title: "Services", footer: "Spotify also shows what's up next. Apple Music shows it when you play from a playlist.") {
      SettingsRow(title: "Spotify", detail: spotify.userName.map { "Connected as \($0)" }) {
        Button(spotify.connected ? "Disconnect" : "Connect") { spotify.connected ? spotify.disconnect() : spotify.connect() }
      }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Apple Music") {
        Button(appleMusic.connected ? "Disconnect" : "Connect") { appleMusic.connected ? appleMusic.disconnect() : appleMusic.connect() }
      }
    }
    SettingsGroup {
      SettingsToggle(title: "Molt dances to your music", detail: "In headphones, under the cover on Home.", isOn: $dances)
    }
  }
}

struct ClipboardSettings: View {
  @ObservedObject var clipboard: ClipboardHistory
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    SettingsGroup(footer: "Your history is kept only on this Mac. Anything an app marks as a password or as private is never saved.") {
      SettingsToggle(title: "Clipboard history", isOn: Binding(get: { prefs.has("clipboard") }, set: { prefs.set("clipboard", on: $0) }))
      Divider().padding(.leading, 12)
      SettingsRow(title: "Keep") {
        Picker("", selection: $clipboard.limit) { ForEach([25, 50, 100, 200], id: \.self) { Text("\($0) items").tag($0) } }.labelsHidden().frame(width: 120)
      }
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Save images", isOn: $clipboard.keepImages)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Clear when Molt quits", detail: "Pinned items stay.", isOn: $clipboard.clearOnQuit)
      Divider().padding(.leading, 12)
      SettingsRow(title: clipboard.paused ? "Paused" : "Pause saving") {
        if clipboard.paused { Button("Resume") { clipboard.pausedUntil = nil } }
        else { Button("For an hour") { clipboard.pausedUntil = Date().addingTimeInterval(3600) } }
      }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Clear history", detail: "\(clipboard.items.count) items") { Button("Clear", role: .destructive) { clipboard.clear() } }
    }
    SettingsGroup(title: "Never save copies from", footer: "Password managers are ignored from the start.") {
      ForEach(clipboard.ignored, id: \.self) { id in
        HStack {
          if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
            Text(url.deletingPathExtension().lastPathComponent)
          } else {
            Image(systemName: "app.dashed").frame(width: 18)
            Text(id).foregroundStyle(.secondary)
          }
          Spacer()
          Button { clipboard.ignored.removeAll { $0 == id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
      }
      HStack {
        Button("Add an app…") {
          let panel = NSOpenPanel()
          panel.allowedContentTypes = [.application]
          panel.directoryURL = URL(fileURLWithPath: "/Applications")
          guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, !clipboard.ignored.contains(id) else { return }
          clipboard.ignored.append(id)
        }
        Spacer()
      }.padding(12)
    }
  }
}

struct AgentsSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    SettingsGroup(footer: "Connect Claude Code and Codex, choose what's always allowed, and set up plan usage and GitHub in Agents › Setup.") {
      SettingsToggle(title: "Coding agents", isOn: Binding(get: { prefs.has("agents") }, set: { prefs.set("agents", on: $0) }))
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Compact approvals", detail: "A pill beside the notch first; hover for the diff.", isOn: $prefs.compactApprovals)
      Divider().padding(.leading, 12)
      SettingsRow(title: "Agents setup") {
        Button("Open in the notch") {
          UserDefaults.standard.set("Setup", forKey: "agentsTab")
          controller.tab = "Agents"
          NSApp.keyWindow?.close()
          coordinator.open()
        }
      }
    }
  }
}

struct CalendarSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var contexts: ContextAdapters
  @ObservedObject var reminders: RemindersController
  var body: some View {
    SettingsGroup(title: "Calendars", footer: "Molt only reads your calendars, to show what's next. It never changes events.") {
      SettingsToggle(title: "Show my calendar", isOn: Binding(get: { controller.organization.consent.calendar }, set: setCalendar))
      if controller.organization.consent.calendar {
        ForEach(contexts.calendars, id: \.calendarIdentifier) { calendar in
          Divider().padding(.leading, 12)
          SettingsRow(title: calendar.title, detail: calendar.source?.title) {
            Toggle("", isOn: Binding(
              get: { controller.organization.consent.selectedCalendars.contains(calendar.calendarIdentifier) },
              set: { on in
                controller.updateOrganization { o in
                  if on { o.consent.selectedCalendars.append(calendar.calendarIdentifier) } else { o.consent.selectedCalendars.removeAll { $0 == calendar.calendarIdentifier } }
                }
                controller.configureContext()
              })).labelsHidden().toggleStyle(.checkbox)
          }
        }
      }
    }
    SettingsGroup(title: "Reminders", footer: "For the Reminders widget.") {
      if reminders.allowed {
        SettingsRow(title: "List") {
          Picker("", selection: $reminders.list) {
            Text("All lists").tag("")
            ForEach(reminders.lists, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
          }.labelsHidden().frame(width: 200)
        }
      } else {
        SettingsRow(title: "Show my Reminders") { Button("Allow") { reminders.requestAccess() } }
      }
    }
    .onAppear(perform: reminders.refresh)
  }
  private func setCalendar(_ value: Bool) {
    guard value else {
      controller.updateOrganization { $0.consent.calendar = false }
      controller.configureContext()
      return
    }
    controller.contexts.enableCalendar { granted in
      controller.updateOrganization { $0.consent.calendar = granted }
      controller.updateOrganization { $0.consent.selectedCalendars = controller.contexts.calendars.map(\.calendarIdentifier) }
      controller.configureContext()
    }
  }
}

struct ShortcutSettings: View {
  @ObservedObject var coordinator: IslandCoordinator
  @State private var recording: UInt32?
  @State private var monitor: Any?
  @State private var version = 0
  var body: some View {
    SettingsGroup(footer: "Click a shortcut, then press the keys you want, with at least one of ⌘ ⌃ ⌥. Esc cancels; ⌫ turns it off.") {
      ForEach(Array(HotKeys.actions.enumerated()), id: \.element.id) { index, action in
        if index > 0 { Divider().padding(.leading, 12) }
        SettingsRow(title: action.title) {
          HStack(spacing: 8) {
            if HotKeys.isCustom(action.id) {
              Button("Reset") { HotKeys.reset(action.id); coordinator.registerShortcut(); version += 1 }.buttonStyle(.link)
            }
            Button { start(action.id) } label: {
              Text(recording == action.id ? "Press keys…" : HotKeys.describe(HotKeys.binding(action.id)))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).frame(minWidth: 90)
            }
          }
        }
      }
    }
    .id(version)
    .onDisappear(perform: stop)
  }
  private func start(_ id: UInt32) {
    stop()
    recording = id
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let modifiers = HotKeys.carbon(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
      if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
      if event.keyCode == UInt16(kVK_Delete) { HotKeys.set(id, nil); finish(); return nil }
      guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { NSSound.beep(); return nil }
      HotKeys.set(id, HotKeys.Binding(key: Int(event.keyCode), modifiers: modifiers))
      finish()
      return nil
    }
  }
  private func finish() {
    stop()
    coordinator.registerShortcut()
    version += 1
  }
  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = nil
  }
}

struct MoltSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    SettingsGroup {
      SettingsRow(title: "Name") {
        TextField("Name", text: Binding(get: { controller.companion.name }, set: { value in controller.changeCompanion { $0.name = String(value.prefix(40)) } }))
          .frame(width: 180)
      }
    }
    SettingsGroup(title: "Bedtime", footer: "Molt sleeps through these hours, and stays quiet through the quiet ones.") {
      SettingsRow(title: "Sleeps from") { hour(petPref(controller, \.sleepStart)) }
      SettingsRow(title: "Wakes at") { hour(petPref(controller, \.sleepEnd)) }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Quiet from") { hour(petPref(controller, \.quietStart)) }
      SettingsRow(title: "Quiet until") { hour(petPref(controller, \.quietEnd)) }
    }
    SettingsGroup {
      SettingsToggle(title: "Reacts to the Mac", detail: "Sleepy on low battery.", isOn: $prefs.petReacts)
      Divider().padding(.leading, 12)
      SettingsToggle(title: "Sounds", isOn: petPref(controller, \.sound))
    }
  }
  private func hour(_ value: Binding<Int>) -> some View {
    Picker("", selection: value) {
      ForEach(0..<24, id: \.self) { hour in
        Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!.formatted(date: .omitted, time: .shortened)).tag(hour)
      }
    }.labelsHidden().frame(width: 110)
  }
}

/// Every permission Molt can ask for, in plain words: what it's for, whether it's on, and a
/// warning when one you allowed isn't needed by anything anymore.
struct PrivacySettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  @ObservedObject var prefs: NotchPrefs
  @State private var notifications: UNAuthorizationStatus = .notDetermined
  @State private var refresh = 0
  struct Permission { var title: String; var symbol: String; var why: String; var usedBy: [String]; var granted: Bool?; var needed: Bool; var pane: String }
  private var permissions: [Permission] {
    let placed = Set(hub.layout.map(\.kind))
    let shortcuts = hub.layout.flatMap(\.items)
    let screen = CGPreflightScreenCaptureAccess()
    let calendar = EKEventStore.authorizationStatus(for: .event)
    let reminders = EKEventStore.authorizationStatus(for: .reminder)
    let camera = AVCaptureDevice.authorizationStatus(for: .video)
    return [
      Permission(title: "Screen Recording", symbol: "rectangle.dashed.badge.record", why: "Lets Lens read what's on your screen, and the screen recorder record it.",
        usedBy: ["Lens", "Screen recorder"], granted: screen, needed: prefs.has("lens") || placed.contains("recorder") || shortcuts.contains("action:record"), pane: "Privacy_ScreenCapture"),
      Permission(title: "Automation", symbol: "gearshape.2", why: "Lets Molt follow Spotify and Apple Music, and switch dark mode or empty the Trash when you ask.",
        usedBy: ["Music", "Dark mode", "Empty Trash"], granted: nil, needed: true, pane: "Privacy_Automation"),
      Permission(title: "Calendars", symbol: "calendar", why: "Shows what's next today. Molt never changes your events.",
        usedBy: ["Home", "Next up", "Daily brief"], granted: Self.allowed(calendar), needed: prefs.has("calendar") && controller.organization.consent.calendar, pane: "Privacy_Calendars"),
      Permission(title: "Reminders", symbol: "list.bullet", why: "Shows your Reminders and ticks them off when you do.",
        usedBy: ["Reminders widget"], granted: Self.allowed(reminders), needed: placed.contains("reminders"), pane: "Privacy_Reminders"),
      Permission(title: "Camera", symbol: "video", why: "Shows you to yourself in the Camera mirror. The picture never leaves your Mac.",
        usedBy: ["Camera mirror"], granted: camera == .notDetermined ? nil : camera == .authorized, needed: placed.contains("camera"), pane: "Privacy_Camera"),
      Permission(title: "Bluetooth", symbol: "dot.radiowaves.left.and.right", why: "Lets the Quick toggles widget switch Bluetooth on and off. Molt never connects to or scans for devices.",
        usedBy: ["Quick toggles"], granted: CBManager.authorization == .notDetermined ? nil : CBManager.authorization == .allowedAlways,
        needed: placed.contains("quickToggles"), pane: "Privacy_Bluetooth"),
      Permission(title: "Notifications", symbol: "bell.badge", why: "Lets reminders you set reach you when Molt is closed.",
        usedBy: ["Reminders you set in Molt"], granted: notifications == .notDetermined ? nil : notifications == .authorized,
        needed: controller.organization.consent.notifications, pane: "notifications"),
    ]
  }
  static func allowed(_ status: EKAuthorizationStatus) -> Bool? {
    if status == .notDetermined { return nil }
    if #available(macOS 14.0, *) { return status == .fullAccess || status == .authorized }
    return status == .authorized
  }
  var body: some View {
    SettingsGroup(footer: "Every permission is optional. Molt asks only when you use something that needs it, and everything it stores stays on this Mac.") {
      ForEach(Array(permissions.enumerated()), id: \.offset) { index, permission in
        if index > 0 { Divider().padding(.leading, 44) }
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: permission.symbol).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 20).padding(.top, 2)
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(permission.title).font(.system(size: 13, weight: .medium))
              status(permission)
            }
            Text(permission.why).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Used by " + permission.usedBy.joined(separator: ", ")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            if permission.granted == true && !permission.needed {
              Label("Nothing uses this right now. You can turn it off.", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
            }
          }
          Spacer()
          Button("Open") { open(permission.pane) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
      }
    }
    .id(refresh)
    .task {
      // The notification center exists only inside an app bundle, not a development build.
      guard Bundle.main.bundleURL.pathExtension == "app" else { return }
      notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh += 1 }
  }
  @ViewBuilder private func status(_ permission: Permission) -> some View {
    let (text, tint): (String, Color) = permission.granted == true ? ("Allowed", .green) : permission.granted == false ? ("Not allowed", .secondary) : ("Not asked yet", .secondary)
    Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
      .padding(.horizontal, 6).padding(.vertical, 1.5).background(Capsule().fill(tint.opacity(0.12)))
  }
  private func open(_ pane: String) {
    let url = pane == "notifications" ? "x-apple.systempreferences:com.apple.preference.notifications" : "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    NSWorkspace.shared.open(URL(string: url)!)
  }
}

struct AccountSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var account: AccountController
  @ObservedObject var coordinator: IslandCoordinator
  var body: some View {
    SettingsGroup {
      SettingsRow(title: account.profile.map { "@\($0.username)" } ?? "Not signed in", detail: account.mfaEnabled ? "Two-factor authentication is on." : "Turn on two-factor authentication to keep your Molt safe.") {
        Button("Manage") {
          controller.tab = "Settings"
          NSApp.keyWindow?.close()
          coordinator.open()
        }
      }
    }
  }
}

/// Settings travel as one file: export them to set up another Mac the same way.
struct DataSettings: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  @State private var status = ""
  static let prefixes = ["notch", "molt", "island", "hub", "focus", "clipboard", "break", "alarms", "worldClocks", "colorHistory", "hotKeys", "timerTile", "reminders", "clock24", "weatherFahrenheit"]
  var body: some View {
    SettingsGroup(footer: "Settings only: your pet, history and clipboard aren't included. Export Molt itself from Play › Wardrobe.") {
      SettingsRow(title: "Export settings") { Button("Export…", action: export) }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Import settings") { Button("Import…", action: importSettings) }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Reset all settings", detail: "Back to how Molt started. Molt restarts.") { Button("Reset…", role: .destructive, action: reset) }
    }
    if !status.isEmpty { Text(status).font(.system(size: 11)).foregroundStyle(.secondary) }
  }
  private var keys: [String] {
    UserDefaults.standard.dictionaryRepresentation().keys.filter { key in Self.prefixes.contains { key.hasPrefix($0) } && key != "moltQuitByUser" && key != "moltLastVersion" && key != "moltTourDone" }
  }
  private func export() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Molt Settings.plist"
    panel.allowedContentTypes = [.propertyList]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    var values: [String: Any] = [:]
    for key in keys { values[key] = UserDefaults.standard.object(forKey: key) }
    values["hubWidgets"] = try? JSONEncoder().encode(hub.layout)
    do {
      try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: url, options: .atomic)
      status = "Exported \(values.count) settings."
    } catch { status = "Couldn't export: \(error.localizedDescription)" }
  }
  private func importSettings() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.propertyList]
    guard panel.runModal() == .OK, let url = panel.url,
      let data = try? Data(contentsOf: url), data.count < 2_000_000,
      let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { status = "That isn't a Molt settings file."; return }
    var count = 0
    for (key, value) in values where Self.prefixes.contains(where: { key.hasPrefix($0) }) {
      UserDefaults.standard.set(value, forKey: key)
      count += 1
    }
    if let widgets = values["hubWidgets"] as? Data, let layout = try? JSONDecoder().decode([HubWidget].self, from: widgets) {
      hub.setLayout(HubLayout.sanitize(layout, known: Set(WidgetKind.catalog.map(\.id)), rows: HubLayout.maxRows))
    }
    status = "Imported \(count) settings. Restart Molt to apply them all."
  }
  private func reset() {
    let alert = NSAlert()
    alert.messageText = "Reset all of Molt's settings?"
    alert.informativeText = "Your pet, history, clipboard and widgets' contents stay. Molt restarts."
    alert.addButton(withTitle: "Reset and restart")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    hub.setLayout(HubLayout.defaults)
    UserDefaults.standard.set(true, forKey: "moltQuitByUser")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", Bundle.main.bundlePath]
    try? process.run()
    NSApp.terminate(nil)
  }
}

struct AboutSettings: View {
  @State private var update = ""
  @State private var download: URL?
  private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
  var body: some View {
    SettingsGroup {
      SettingsRow(title: "Molt \(version)", detail: "A little companion that lives in your notch.") {
        Button("Check for updates", action: check)
      }
      if !update.isEmpty {
        Divider().padding(.leading, 12)
        SettingsRow(title: update) {
          if let download { Button("Download") { NSWorkspace.shared.open(download) } }
        }
      }
      Divider().padding(.leading, 12)
      SettingsRow(title: "Source and release notes") { Link("GitHub", destination: URL(string: "https://github.com/vkn889/Molt")!) }
    }
  }
  private func check() {
    update = "Checking…"
    Task {
      var request = URLRequest(url: URL(string: "https://api.github.com/repos/vkn889/Molt/releases/latest")!)
      request.timeoutInterval = 10
      guard let (data, _) = try? await URLSession.shared.data(for: request),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = json["tag_name"] as? String
      else { update = "Couldn't reach GitHub."; return }
      let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
      if latest.compare(version, options: .numeric) == .orderedDescending {
        update = "Molt \(latest) is available."
        download = (json["html_url"] as? String).flatMap(URL.init(string:))
      } else {
        update = "You're up to date."
      }
    }
  }
}
