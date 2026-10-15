import AVFoundation
import AppKit
import Charts
import CoreLocation
import EventKit
import MoltCore
import SwiftUI
import UniformTypeIdentifiers

// The utility widgets: clipboard, timers, countdowns, breaks, habits, Reminders, batteries,
// network, a system graph, world clocks, sound output, screenshots, recent files, a calculator,
// a camera mirror, mic and camera in use, a daily brief, focus stats, hourly weather, picked
// colors and quick toggles.

private let dim = Color.white.opacity(0.55)
private let faint = Color.white.opacity(0.3)
private let row = Color.white.opacity(0.05)

/// A row background, as in the mockups.
private struct RowStyle: ViewModifier {
  var hovered = false
  func body(content: Content) -> some View {
    content.padding(.horizontal, 8).frame(height: 26)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hovered ? 0.1 : 0.05)))
  }
}

/// A short line in place of content: what to do to fill the widget.
private struct Hint: View {
  var text: String
  var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(dim).fixedSize(horizontal: false, vertical: true) }
}

/// A small field for typing into a widget.
private struct TileField: View {
  var placeholder: String
  @Binding var text: String
  var submit: () -> Void = {}
  var body: some View {
    TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 11.5))
      .padding(.horizontal, 8).frame(height: 24)
      .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
      .onSubmit(submit)
  }
}

/// A line chart of values from 0 to 1.
struct Sparkline: View {
  var values: [Double]
  var tint: Color
  var body: some View {
    GeometryReader { proxy in
      let top = max(0.0001, values.max() ?? 1)
      let scale = values.allSatisfy { $0 <= 1 } ? 1 : top
      let points = values.enumerated().map { index, value in
        CGPoint(x: proxy.size.width * CGFloat(index) / CGFloat(max(1, values.count - 1)), y: proxy.size.height * (1 - CGFloat(min(1, value / scale))))
      }
      ZStack {
        if points.count > 1 {
          Path { path in
            path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
            points.forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
          }
          .fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
          Path { path in path.addLines(points) }.stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
      }
    }
  }
}

// MARK: 5.1 Clipboard

struct ClipboardTile: View {
  @ObservedObject var clipboard: ClipboardHistory
  var span: Int
  @State private var search = ""
  @State private var hovered: UUID?
  @State private var copied: UUID?
  var body: some View {
    let items = clipboard.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
      .sorted { $0.pinned != $1.pinned ? $0.pinned : $0.date > $1.date }
    Tile(title: clipboard.paused ? "Clipboard · paused" : "Clipboard", icon: "doc.on.clipboard", tint: .accentColor) {
      if span == 2 { TileField(placeholder: "Search what you copied", text: $search) }
      if clipboard.items.isEmpty {
        Hint(text: "Copy something and it shows up here. Kept only on this Mac; passwords are never saved.")
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span), spacing: 6) {
          ForEach(Array(items.prefix(span == 2 ? 6 : 3))) { item in line(item) }
        }
      }
      Spacer(minLength: 0)
    }
  }
  private func line(_ item: ClipboardHistory.Item) -> some View {
    HStack(spacing: 7) {
      Group {
        switch item.kind {
        case .image:
          if let image = clipboard.image(item) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) } else { Image(systemName: "photo") }
        case .files: Image(systemName: "doc.fill").foregroundStyle(.blue)
        case .text: Image(systemName: item.pinned ? "pin.fill" : "text.alignleft").foregroundStyle(item.pinned ? .orange : dim)
        }
      }
      .font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3))
      Text(copied == item.id ? "Copied" : item.title.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11.5)).lineLimit(1)
        .foregroundStyle(copied == item.id ? Color.green : .white)
      Spacer(minLength: 0)
      if hovered == item.id {
        Button { clipboard.togglePin(item) } label: { Image(systemName: item.pinned ? "pin.slash" : "pin") }
          .help(item.pinned ? "Unpin" : "Pin")
        if item.kind == .text {
          Button { clipboard.copy(item, plain: true); flash(item) } label: { Image(systemName: "textformat") }.help("Copy as plain text")
        }
        Button { clipboard.remove(item) } label: { Image(systemName: "xmark") }.help("Remove")
      }
    }
    .buttonStyle(.plain).font(.system(size: 9.5, weight: .bold)).foregroundStyle(dim)
    .modifier(RowStyle(hovered: hovered == item.id))
    .contentShape(Rectangle())
    .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
    .onTapGesture { clipboard.copy(item); flash(item) }
    .help("Click to copy")
  }
  private func flash(_ item: ClipboardHistory.Item) {
    copied = item.id
    Task { try? await Task.sleep(nanoseconds: 900_000_000); if copied == item.id { copied = nil } }
  }
}

// MARK: 5.2 Timer, stopwatch and alarm

struct TimerTile: View {
  @ObservedObject var timers: TimerController
  var span: Int
  @AppStorage("timerTileMode") private var mode = "Timer"
  @State private var alarmTime = Date()
  var body: some View {
    Tile(title: mode, icon: mode == "Alarm" ? "alarm.fill" : mode == "Stopwatch" ? "stopwatch.fill" : "timer", tint: .orange) {
      HStack(spacing: 4) {
        ForEach(["Timer", "Stopwatch", "Alarm"], id: \.self) { name in
          Button(name) { mode = name }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(mode == name ? Color.white : faint)
            .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(Color.white.opacity(mode == name ? 0.14 : 0)))
        }
      }
      TimelineView(.periodic(from: .now, by: 0.25)) { context in
        switch mode {
        case "Stopwatch": stopwatch(context.date)
        case "Alarm": alarms
        default: timer(context.date)
        }
      }
      Spacer(minLength: 0)
    }
  }
  @ViewBuilder private func timer(_ date: Date) -> some View {
    let left = timers.left(at: date)
    Text(Self.clock(left)).font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
      .foregroundStyle(timers.pausedLeft != nil ? dim : .white)
    if timers.timerRunning || timers.pausedLeft != nil {
      HStack(spacing: 6) {
        Button(timers.pausedLeft != nil ? "Resume" : "Pause") { timers.pauseOrResume() }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
        Button("Cancel") { timers.cancel() }.buttonStyle(PillButtonStyle(tint: .red.opacity(0.7)))
      }
    } else {
      HStack(spacing: 5) {
        ForEach([1, 5, 10, 25], id: \.self) { minutes in
          Button("\(minutes)m") { timers.start(minutes: Double(minutes)) }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.12)))
        }
      }
    }
  }
  @ViewBuilder private func stopwatch(_ date: Date) -> some View {
    Text(Self.clock(timers.stopwatch(at: date), tenths: true)).font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
    HStack(spacing: 6) {
      Button(timers.stopwatchRunning ? "Stop" : "Start") { timers.toggleStopwatch() }
        .buttonStyle(PillButtonStyle(tint: timers.stopwatchRunning ? .red.opacity(0.75) : .green))
      Button(timers.stopwatchRunning ? "Lap" : "Reset") { timers.stopwatchRunning ? timers.lap() : timers.resetStopwatch() }
        .buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
      if let lap = timers.laps.first { Text("Lap \(Self.clock(lap, tenths: true))").font(.system(size: 10).monospacedDigit()).foregroundStyle(dim) }
    }
  }
  @ViewBuilder private var alarms: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(timers.alarms.prefix(span == 2 ? 3 : 2)) { alarm in
        HStack {
          Text(alarm.time).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(alarm.on ? .white : faint)
          Text(alarm.label).font(.system(size: 10.5)).foregroundStyle(dim).lineLimit(1)
          Spacer()
          Toggle("", isOn: Binding(get: { alarm.on }, set: { value in
            if let index = timers.alarms.firstIndex(of: alarm) { timers.alarms[index].on = value }
          })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
      }
      HStack(spacing: 6) {
        DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute).labelsHidden().controlSize(.small).frame(width: 82)
        Button("Add") {
          let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
          timers.addAlarm(hour: parts.hour ?? 7, minute: parts.minute ?? 0, label: "")
        }.buttonStyle(PillButtonStyle(tint: .accentColor))
      }
    }
  }
  static func clock(_ seconds: Double, tenths: Bool = false) -> String {
    let whole = Int(seconds)
    let base = whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60) : String(format: "%02d:%02d", whole / 60, whole % 60)
    return tenths ? base + ".\(Int(seconds * 10) % 10)" : base
  }
}

// MARK: 5.3 Countdown

struct CountdownTile: View {
  @ObservedObject var daily: DailyController
  var span: Int
  @State private var adding = false
  @State private var title = ""
  @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
  var body: some View {
    let upcoming = daily.countdowns.sorted { $0.date < $1.date }.filter { $0.days(from: Date()) >= 0 }
    Tile(title: "Countdown", icon: "calendar.badge.clock", tint: .orange) {
      if adding {
        TileField(placeholder: "What's happening?", text: $title) { save() }
        HStack {
          DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().controlSize(.small)
          Button("Save", action: save).buttonStyle(PillButtonStyle(tint: .accentColor)).disabled(title.isEmpty)
        }
      } else if let first = upcoming.first {
        let days = first.days(from: Date())
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(days == 0 ? "Today" : "\(days)").font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
          if days > 0 { Text(days == 1 ? "day" : "days").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(dim) }
        }
        Text(first.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Text(first.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(dim)
        if span == 2 {
          ForEach(upcoming.dropFirst().prefix(2)) { item in
            HStack {
              Text(item.title).font(.system(size: 11)).lineLimit(1)
              Spacer()
              Text("\(item.days(from: Date()))d").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(dim)
            }.modifier(RowStyle())
          }
        }
      } else {
        Hint(text: "Count down to a launch, a trip or an exam.")
      }
      Spacer(minLength: 0)
      if !adding {
        HStack {
          Spacer()
          Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
            .buttonStyle(NotchIconButtonStyle(size: 22)).help("Add a date")
          if let first = upcoming.first {
            Button { daily.countdowns.removeAll { $0.id == first.id } } label: { Image(systemName: "trash").font(.system(size: 10)) }
              .buttonStyle(NotchIconButtonStyle(size: 22)).help("Remove \(first.title)")
          }
        }
      }
    }
  }
  private func save() {
    guard !title.isEmpty else { return }
    daily.countdowns.append(Countdown(title: String(title.prefix(60)), date: date))
    title = ""
    adding = false
  }
}

// MARK: 5.4 Breaks

struct BreaksTile: View {
  @ObservedObject var daily: DailyController
  var body: some View {
    Tile(title: "Breaks", icon: "drop.fill", tint: .cyan) {
      if !daily.breaksOn {
        Hint(text: "Water every \(daily.waterEvery) min and a stretch every \(daily.stretchEvery). Molt does them with you.")
        Spacer(minLength: 0)
        Button("Turn on") { daily.breaksOn = true }.buttonStyle(PillButtonStyle(tint: .accentColor))
      } else {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          VStack(alignment: .leading, spacing: 6) {
            line("drop.fill", .cyan, "Water", daily.nextWater(at: context.date), count: daily.waterToday) { daily.tookWater() }
            line("figure.walk", .green, "Stretch", daily.nextStretch(at: context.date), count: daily.stretchToday) { daily.stretched() }
          }
        }
        Spacer(minLength: 0)
        Button("Pause breaks") { daily.breaksOn = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(faint)
      }
    }
  }
  private func line(_ symbol: String, _ tint: Color, _ title: String, _ due: Date, count: Int, done: @escaping () -> Void) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint).frame(width: 14)
      VStack(alignment: .leading, spacing: 0) {
        Text(title).font(.system(size: 11.5, weight: .semibold))
        Text(due <= Date() ? "Now" : "in \(Int(ceil(due.timeIntervalSinceNow / 60))) min · \(count) today").font(.system(size: 10)).foregroundStyle(dim)
      }
      Spacer(minLength: 0)
      Button("Done", action: done).buttonStyle(PillButtonStyle(tint: .white.opacity(0.12)))
    }
  }
}

// MARK: 5.5 Habits

struct HabitsTile: View {
  @ObservedObject var daily: DailyController
  var span: Int
  @State private var draft = ""
  var body: some View {
    Tile(title: "Habits", icon: "checkmark.seal.fill", tint: Color(red: 0.36, green: 0.8, blue: 0.55)) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span), spacing: 6) {
        ForEach(daily.habits.prefix(span == 2 ? 6 : 3)) { habit in
          let done = habit.isDone(on: Date())
          Button { daily.toggle(habit) } label: {
            HStack(spacing: 7) {
              Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 13))
                .foregroundStyle(done ? Color(red: 0.36, green: 0.8, blue: 0.55) : faint)
              Text(habit.title).font(.system(size: 11.5)).lineLimit(1).strikethrough(done, color: faint)
              Spacer(minLength: 0)
              let streak = habit.streak(at: Date())
              if streak > 0 {
                Label("\(streak)", systemImage: "flame.fill").font(.system(size: 10, weight: .semibold).monospacedDigit())
                  .foregroundStyle(.orange).labelStyle(.titleAndIcon)
              }
            }.modifier(RowStyle()).contentShape(Rectangle())
          }.buttonStyle(.plain)
          .contextMenu { Button("Remove \(habit.title)") { daily.habits.removeAll { $0.id == habit.id } } }
        }
      }
      if daily.habits.count < 6 {
        TileField(placeholder: "Add a habit", text: $draft) {
          let title = draft.trimmingCharacters(in: .whitespaces)
          guard !title.isEmpty else { return }
          daily.habits.append(Habit(title: String(title.prefix(40))))
          draft = ""
        }
      }
      Spacer(minLength: 0)
    }
  }
}

// MARK: 5.6 Apple Reminders

struct RemindersTile: View {
  @ObservedObject var reminders: RemindersController
  var span: Int
  @State private var draft = ""
  var body: some View {
    Tile(title: reminders.lists.first { $0.calendarIdentifier == reminders.list }?.title ?? "Reminders", icon: "list.bullet.circle.fill", tint: .orange) {
      if !reminders.allowed {
        Hint(text: "Tick off your Reminders from the notch.")
        Spacer(minLength: 0)
        Button("Show my Reminders") { reminders.requestAccess() }.buttonStyle(PillButtonStyle(tint: .accentColor))
      } else {
        if reminders.reminders.isEmpty { Hint(text: "All done.") }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span), spacing: 5) {
          ForEach(Array(reminders.reminders.prefix(span == 2 ? 6 : 3)), id: \.calendarItemIdentifier) { reminder in
            HStack(spacing: 7) {
              Button { reminders.complete(reminder) } label: {
                Image(systemName: "circle").font(.system(size: 12)).foregroundStyle(Color(cgColor: reminder.calendar.cgColor))
              }.buttonStyle(.plain).help("Mark done")
              Text(reminder.title ?? "").font(.system(size: 11.5)).lineLimit(1)
              Spacer(minLength: 0)
              if let due = reminder.dueDateComponents?.date {
                Text(due, format: .dateTime.month(.abbreviated).day()).font(.system(size: 9.5)).foregroundStyle(due < Date() ? .red : faint)
              }
            }.modifier(RowStyle())
          }
        }
        Spacer(minLength: 0)
        TileField(placeholder: "New reminder", text: $draft) {
          guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
          reminders.add(draft)
          draft = ""
        }
      }
    }
    .onAppear(perform: reminders.refresh)
  }
}

// MARK: 5.7 Device batteries

struct BatteriesTile: View {
  @ObservedObject var devices: DeviceBatteries
  @ObservedObject var controller: PetController
  var span: Int
  var body: some View {
    let mac = controller.health.values["batteryLevel"].map { DeviceBatteries.Device(id: "mac", name: "This Mac", percent: Int(($0 * 100).rounded()), symbol: "laptopcomputer") }
    let all = (mac.map { [$0] } ?? []) + devices.devices
    Tile(title: "Batteries", icon: "battery.75", tint: .white) {
      if all.isEmpty { Hint(text: devices.loading ? "Looking…" : "Connect a Magic Keyboard, Mouse, Trackpad or AirPods.") }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: span), spacing: 7) {
        ForEach(all.prefix(span == 2 ? 6 : 3)) { device in
          HStack(spacing: 8) {
            Image(systemName: device.symbol).font(.system(size: 12)).frame(width: 18).foregroundStyle(dim)
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(device.name).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(device.percent)%").font(.system(size: 11, weight: .semibold).monospacedDigit())
              }
              GeometryReader { proxy in
                ZStack(alignment: .leading) {
                  Capsule().fill(Color.white.opacity(0.12))
                  Capsule().fill(device.percent <= 20 ? Color.red : Color.green).frame(width: proxy.size.width * CGFloat(device.percent) / 100)
                }
              }.frame(height: 3)
            }
          }
        }
      }
      Spacer(minLength: 0)
      if !Bluetooth.allowed && Bluetooth.askable {
        Button("Show AirPods") { Bluetooth.request() }.buttonStyle(.plain)
          .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
          .help("Allow Bluetooth so Molt can show your AirPods' battery")
      }
    }
    .onAppear { devices.refresh() }
  }
}

// MARK: 5.8 Network

struct NetworkTile: View {
  @ObservedObject var network: NetworkMonitor
  var span: Int
  var body: some View {
    Tile(title: network.wifi ?? "Network", icon: "wifi", tint: Color(red: 0.39, green: 0.82, blue: 1)) {
      HStack(spacing: 14) {
        rate("arrow.down", network.down, .green)
        rate("arrow.up", network.up, .orange)
      }
      Sparkline(values: network.history, tint: .green).frame(height: span == 2 ? 40 : 28)
      HStack(spacing: 8) {
        Text(network.localIP ?? "Offline").font(.system(size: 10).monospacedDigit()).foregroundStyle(dim)
        Spacer()
        if let ip = network.publicIP {
          Text(ip).font(.system(size: 10).monospacedDigit()).foregroundStyle(dim).textSelection(.enabled)
        } else {
          Button("Public IP") { network.lookUpPublicIP() }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
            .help("Asks api.ipify.org for your address on the internet")
        }
      }
    }
    .onAppear { network.active = true }
    .onDisappear { network.active = false }
  }
  private func rate(_ symbol: String, _ bytes: Double, _ tint: Color) -> some View {
    HStack(spacing: 3) {
      Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
      Text(NetworkMonitor.rate(bytes)).font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
    }
  }
}

// MARK: 5.9 System graph

struct SystemGraphTile: View {
  @ObservedObject var system: SystemGraph
  var span: Int
  var body: some View {
    Tile(title: "System", icon: "waveform.path.ecg", tint: .white) {
      graph("CPU", system.cpu, Color(red: 0.36, green: 0.8, blue: 0.55))
      graph("Memory", system.memory, Color(red: 0.39, green: 0.82, blue: 1))
    }
    .onAppear { system.active = true }
    .onDisappear { system.active = false }
  }
  private func graph(_ title: String, _ values: [Double], _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.system(size: 10.5)).foregroundStyle(dim)
        Spacer()
        Text(values.last.map { "\(Int(($0 * 100).rounded()))%" } ?? "…").font(.system(size: 11, weight: .semibold).monospacedDigit())
      }
      Sparkline(values: values, tint: tint).frame(height: span == 2 ? 30 : 24)
    }
  }
}

// MARK: 5.10 World clocks

struct WorldClocksTile: View {
  var span: Int
  @AppStorage("worldClocks") private var saved = "America/New_York,Europe/London,Asia/Tokyo"
  static let choices = [
    "America/Los_Angeles", "America/Denver", "America/Chicago", "America/New_York", "America/Sao_Paulo", "Europe/London", "Europe/Paris",
    "Europe/Berlin", "Africa/Lagos", "Asia/Dubai", "Asia/Kolkata", "Asia/Singapore", "Asia/Shanghai", "Asia/Tokyo", "Australia/Sydney", "Pacific/Auckland",
  ]
  var body: some View {
    let zones = saved.split(separator: ",").compactMap { TimeZone(identifier: String($0)) }
    Tile(title: "World clocks", icon: "globe", tint: Color(red: 0.39, green: 0.82, blue: 1)) {
      TimelineView(.everyMinute) { context in
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: span), spacing: 6) {
          ForEach(zones.prefix(span == 2 ? 6 : 3), id: \.identifier) { zone in
            HStack {
              VStack(alignment: .leading, spacing: 0) {
                Text(Self.city(zone)).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(Self.offset(zone, at: context.date)).font(.system(size: 9.5)).foregroundStyle(faint)
              }
              Spacer(minLength: 2)
              Text(context.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .contextMenu { Button("Remove \(Self.city(zone))") { saved = zones.filter { $0 != zone }.map(\.identifier).joined(separator: ",") } }
          }
        }
      }
      Spacer(minLength: 0)
      Menu {
        ForEach(Self.choices.filter { id in !zones.contains { $0.identifier == id } }, id: \.self) { id in
          Button(Self.city(TimeZone(identifier: id)!)) { saved = (zones.map(\.identifier) + [id]).joined(separator: ",") }
        }
      } label: { Label("Add a city", systemImage: "plus").font(.system(size: 10, weight: .semibold)) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
  }
  static func city(_ zone: TimeZone) -> String { zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier }
  static func offset(_ zone: TimeZone, at date: Date) -> String {
    let hours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
    if hours == 0 { return "Same time" }
    let text = hours == hours.rounded() ? "\(Int(abs(hours)))h" : String(format: "%.1fh", abs(hours))
    return hours > 0 ? "\(text) ahead" : "\(text) behind"
  }
}

// MARK: 5.11 Sound output

struct SoundOutputTile: View {
  @ObservedObject var audio: AudioOutputs
  var body: some View {
    Tile(title: "Sound output", icon: "hifispeaker.fill", tint: Color(red: 1, green: 0.39, blue: 0.51)) {
      VStack(spacing: 4) {
        ForEach(audio.devices.prefix(3)) { device in
          Button { audio.choose(device) } label: {
            HStack(spacing: 7) {
              Image(systemName: device.name.localizedCaseInsensitiveContains("airpods") ? "airpods" : device.name.localizedCaseInsensitiveContains("headphone") ? "headphones" : "speaker.wave.2.fill")
                .font(.system(size: 10)).frame(width: 14)
              Text(device.name).font(.system(size: 11)).lineLimit(1)
              Spacer(minLength: 0)
              if device.id == audio.current { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.accentColor) }
            }.modifier(RowStyle(hovered: device.id == audio.current)).contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(dim)
        Slider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }), in: 0...1).controlSize(.mini)
      }
    }
    .onAppear(perform: audio.refresh)
  }
}

// MARK: 5.12 Screenshots and 5.13 Recent files

struct ScreenshotsTile: View {
  var span: Int
  @State private var shots: [URL] = []
  var body: some View {
    Tile(title: "Screenshots", icon: "camera.viewfinder", tint: .white) {
      if shots.isEmpty { Hint(text: "Your latest screenshots appear here, ready to drag into anything.") }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span == 2 ? 4 : 2), spacing: 6) {
        ForEach(shots.prefix(span == 2 ? 4 : 2), id: \.self) { url in
          Thumbnail(url: url).frame(height: span == 2 ? 82 : 70)
            .onTapGesture { NSWorkspace.shared.open(url) }
            .onDrag { NSItemProvider(object: url as NSURL) }
            .help("\(url.lastPathComponent). Click to open, or drag it somewhere.")
        }
      }
      Spacer(minLength: 0)
    }
    .task { shots = await RecentFiles.screenshots() }
  }
}

/// A file's preview, from Quick Look's thumbnails.
struct Thumbnail: View {
  var url: URL
  @State private var image: NSImage?
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06))
      if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
      else { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit).padding(10) }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .task(id: url) {
      image = await Task.detached(priority: .utility) { () -> NSImage? in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 300] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: .zero)
      }.value
    }
  }
}

struct RecentFilesTile: View {
  @ObservedObject var recent: RecentFiles
  var span: Int
  var body: some View {
    Tile(title: "Recent files", icon: "clock.arrow.circlepath", tint: .accentColor) {
      if recent.files.isEmpty { Hint(text: "Files you've opened in the last few days.") }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span), spacing: 5) {
        ForEach(recent.files.prefix(span == 2 ? 6 : 3), id: \.self) { url in
          HStack(spacing: 7) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
          }
          .modifier(RowStyle()).contentShape(Rectangle())
          .onTapGesture { NSWorkspace.shared.open(url) }
          .onDrag { NSItemProvider(object: url as NSURL) }
          .help(url.path)
        }
      }
      Spacer(minLength: 0)
    }
    .onAppear(perform: recent.refresh)
  }
}

// MARK: 5.14 Calculator

struct CalculatorTile: View {
  @State private var input = ""
  @State private var copied = false
  var body: some View {
    let answer = Calculator.evaluate(input)
    Tile(title: "Calculator", icon: "plus.forwardslash.minus", tint: .orange) {
      TileField(placeholder: "12% of 80, 5 km in mi", text: $input) {
        guard let answer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Calculator.format(answer.value), forType: .string)
        copied = true
      }
      Spacer(minLength: 0)
      Text(answer?.text ?? (input.isEmpty ? "0" : "…")).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
        .foregroundStyle(answer == nil ? faint : .white)
      Text(copied ? "Copied" : "Return copies the answer").font(.system(size: 10)).foregroundStyle(copied ? .green : faint)
    }
    .onChange(of: input) { _ in copied = false }
  }
}

// MARK: 5.15 Camera mirror

struct CameraTile: View {
  @StateObject private var camera = CameraMirror()
  var body: some View {
    ZStack(alignment: .topLeading) {
      if camera.allowed {
        CameraPreview(session: camera.session).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      } else {
        Tile(title: "Camera mirror", icon: "video.fill", tint: .green) {
          Hint(text: "Check how you look before a call. The picture stays on this Mac.")
          Spacer(minLength: 0)
          Button("Turn on camera") { camera.request() }.buttonStyle(PillButtonStyle(tint: .accentColor))
        }
      }
    }
    .onAppear { camera.start() }
    .onDisappear { camera.stop() }
  }
}

@MainActor final class CameraMirror: ObservableObject {
  let session = AVCaptureSession()
  @Published private(set) var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
  private var configured = false
  func request() {
    AVCaptureDevice.requestAccess(for: .video) { granted in
      Task { @MainActor in
        self.allowed = granted
        if granted { self.start() }
      }
    }
  }
  func start() {
    guard allowed else { return }
    if !configured, let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
      session.sessionPreset = .medium
      session.addInput(input)
      configured = true
    }
    let session = self.session
    DispatchQueue.global(qos: .userInitiated).async { if !session.isRunning { session.startRunning() } }
  }
  func stop() {
    let session = self.session
    DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
  }
}

struct CameraPreview: NSViewRepresentable {
  var session: AVCaptureSession
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    // A mirror, like Photo Booth.
    layer.connection?.automaticallyAdjustsVideoMirroring = false
    layer.connection?.isVideoMirrored = true
    layer.frame = view.bounds
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    view.layer = layer
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: 5.16 Mic and camera in use

struct InUseTile: View {
  @ObservedObject var inUse: MediaInUse
  var body: some View {
    Tile(title: "Mic & camera", icon: inUse.camera || inUse.microphone ? "record.circle" : "mic.fill", tint: inUse.camera || inUse.microphone ? .red : .white) {
      line("video.fill", "Camera", inUse.camera)
      line("mic.fill", "Microphone", inUse.microphone)
      Spacer(minLength: 0)
      Text(inUse.camera || inUse.microphone ? "You're live." : "Nothing's listening.").font(.system(size: 10.5)).foregroundStyle(dim)
    }
    .onAppear { inUse.active = true }
    .onDisappear { inUse.active = false }
  }
  private func line(_ symbol: String, _ title: String, _ on: Bool) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(on ? (symbol == "mic.fill" ? Color.orange : .green) : faint).frame(width: 16)
      Text(title).font(.system(size: 12))
      Spacer()
      Circle().fill(on ? (symbol == "mic.fill" ? Color.orange : .green) : Color.white.opacity(0.15)).frame(width: 8, height: 8)
      Text(on ? "In use" : "Off").font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? .white : faint)
    }.modifier(RowStyle())
  }
}

// MARK: 5.17 Daily brief

struct DailyBriefTile: View {
  @ObservedObject var controller: PetController
  @ObservedObject var assistant: AssistantController
  @AppStorage("dailyBriefDay") private var day = ""
  @AppStorage("dailyBriefText") private var text = ""
  @State private var writing = false
  @State private var draft = ""
  var body: some View {
    let today = Habit.day(Date())
    Tile(title: "Daily brief", icon: "sun.horizon.fill", tint: .purple) {
      ScrollView {
        Text(writing ? (draft.isEmpty ? "Thinking…" : draft) : day == today && !text.isEmpty ? text : "A morning summary of your day, from \(controller.petName).")
          .font(.system(size: 12)).foregroundStyle(day == today || writing ? .white : dim)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Spacer()
        Button(writing ? "Writing…" : day == today ? "Refresh" : "Write today's") { write() }
          .buttonStyle(PillButtonStyle(tint: .white.opacity(0.14))).disabled(writing)
      }
    }
    .onAppear { if day != today && assistant.ready { write() } }
  }
  /// Asks your chat model for three sentences about today: calendar, tasks, weather and focus.
  private func write() {
    let events = controller.contexts.events.filter { Calendar.current.isDateInToday($0.startDate) && !$0.isAllDay }
      .map { "\($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "event")" }
    let tasks = controller.organization.tasks.filter { $0.completed == nil }.prefix(6).map(\.title)
    let weather = controller.hub.weather.map { "\(Int($0.temperature))°C, \($0.summary.lowercased())" } ?? "unknown"
    let focus = FocusMath.today(controller.organization.sessions, now: Date()).minutes
    let facts = "Today's events: \(events.isEmpty ? "none" : events.joined(separator: "; ")). Open tasks: \(tasks.isEmpty ? "none" : tasks.joined(separator: "; ")). Weather: \(weather). Focus so far: \(focus) minutes."
    let messages = [InferenceMessage(role: "user", content: "You are \(controller.petName), a friendly pixel pet who lives in my Mac's notch. In three short sentences, brief me on my day. Be warm and specific; no lists, no greetings longer than two words. Facts: \(facts)")]
    guard let stream = assistant.answer(messages) else { draft = "Set up Chat first, and I'll write you a brief every morning."; return }
    writing = true
    draft = ""
    Task {
      do { for try await token in stream { draft += token } } catch { draft = "I couldn't write it just now." }
      writing = false
      text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      day = Habit.day(Date())
    }
  }
}

// MARK: 5.18 Focus stats

struct FocusStatsTile: View {
  @ObservedObject var controller: PetController
  var span: Int
  var body: some View {
    let days = (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    let totals = days.map { day in (day, FocusMath.today(controller.organization.sessions, now: day).minutes) }
    let week = totals.reduce(0) { $0 + $1.1 }
    Tile(title: "Focus this week", icon: "chart.bar.fill", tint: Color(red: 0.36, green: 0.8, blue: 0.55)) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(week >= 60 ? "\(week / 60)h \(week % 60)m" : "\(week) min").font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
        Text("this week").font(.system(size: 10)).foregroundStyle(dim)
      }
      Chart(totals, id: \.0) { entry in
        BarMark(x: .value("Day", entry.0, unit: .day), y: .value("Minutes", entry.1))
          .foregroundStyle(Calendar.current.isDateInToday(entry.0) ? Color(red: 0.36, green: 0.8, blue: 0.55) : Color.white.opacity(0.3))
          .cornerRadius(3)
      }
      .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(faint) } }
      .chartYAxis(.hidden)
    }
  }
}

// MARK: 5.19 Weather by hour

struct WeatherHourlyTile: View {
  @ObservedObject var hub: HubController
  var span: Int
  var body: some View {
    Tile(title: hub.saved.place.map { "\($0.name), next hours" } ?? "Weather by hour", icon: "cloud.sun.fill", tint: Color(red: 0.39, green: 0.82, blue: 1)) {
      if let hours = hub.weather?.hours, !hours.isEmpty {
        HStack(spacing: 0) {
          ForEach(Array(hours.prefix(span == 2 ? 12 : 6).enumerated()), id: \.offset) { index, hour in
            VStack(spacing: 6) {
              Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour())).font(.system(size: 9.5, weight: .medium)).foregroundStyle(dim).lineLimit(1)
              Image(systemName: hour.symbol).symbolRenderingMode(.multicolor).font(.system(size: 14))
              Text(WeatherTile.temperature(hour.temperature).dropLast()).font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .frame(maxWidth: .infinity)
          }
        }
        .padding(.top, 6)
      } else {
        Hint(text: hub.saved.place == nil ? "Choose a city in the Weather widget." : "Loading…")
      }
      Spacer(minLength: 0)
    }
    .onAppear { hub.refreshWeather() }
  }
}

// MARK: 5.20 Colors

struct ColorsTile: View {
  @ObservedObject var actions: QuickActions
  var span: Int
  var body: some View {
    Tile(title: "Colors", icon: "eyedropper", tint: .cyan) {
      if actions.colors.isEmpty { Hint(text: "Colors you pick appear here, ready to copy.") }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span == 2 ? 8 : 4), spacing: 6) {
        ForEach(actions.colors.prefix(span == 2 ? 16 : 8), id: \.self) { hex in
          let rgb = QuickActions.rgb(hex)
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
            .frame(height: 24)
            .onTapGesture { actions.copyColor(hex) }
            .contextMenu {
              Button("Copy \(hex)") { actions.copyColor(hex) }
              Button("Copy as RGB") { actions.copyColor(hex, as: "rgb") }
              Button("Copy as SwiftUI") { actions.copyColor(hex, as: "swiftui") }
            }
            .help("\(hex). Click to copy; right-click for RGB or SwiftUI.")
        }
      }
      Spacer(minLength: 0)
      HStack {
        Text(actions.status.hasPrefix("Copied") ? actions.status : "").font(.system(size: 10)).foregroundStyle(.green).lineLimit(1)
        Spacer()
        Button { actions.run("action:color") } label: { Label("Pick", systemImage: "eyedropper").font(.system(size: 10, weight: .semibold)) }
          .buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
      }
    }
  }
}

// MARK: 5.21 Quick toggles

struct QuickTogglesTile: View {
  @ObservedObject var actions: QuickActions
  var span: Int
  static let items: [(String, String, String)] = [
    ("awake", "Awake", "cup.and.saucer.fill"), ("dark", "Dark", "circle.lefthalf.filled"), ("desktop", "Icons", "menubar.dock.rectangle"),
    ("wifi", "Wi-Fi", "wifi"), ("bluetooth", "Bluetooth", "dot.radiowaves.left.and.right"), ("dnd", "Focus", "moon.fill"),
  ]
  var body: some View {
    Tile(title: "Quick toggles", icon: "switch.2", tint: .yellow) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: span == 2 ? 6 : 3), spacing: 6) {
        ForEach(Self.items.prefix(6), id: \.0) { id, title, symbol in
          let on = actions.isActive("action:\(id)")
          Button {
            actions.run("action:\(id)")
            Task { try? await Task.sleep(nanoseconds: 600_000_000); actions.refreshToggles() }
          } label: {
            VStack(spacing: 3) {
              Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? Color.black : .white)
              Text(title).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(on ? Color.black.opacity(0.75) : dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.07)))
          }
          .buttonStyle(BareButtonStyle()).help(title).accessibilityLabel(title).accessibilityValue(on ? "On" : "Off")
        }
      }
      Spacer(minLength: 0)
    }
    .onAppear(perform: actions.refreshToggles)
  }
}
