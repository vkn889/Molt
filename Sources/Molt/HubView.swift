import AppKit
import MoltCore
import SwiftUI

/// Four glanceable tiles, all the same size as Home.
struct HubView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  var body: some View {
    HStack(spacing: 12) {
      FocusTile(controller: controller)
      TasksTile(controller: controller)
      WeatherTile(hub: hub)
      TopAppsTile(controller: controller)
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
  }
}

private struct Tile<Content: View>: View {
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

private struct FocusTile: View {
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

private struct TasksTile: View {
  @ObservedObject var controller: PetController
  @State private var draft = ""
  private var tasks: [WorkTask] {
    let open = controller.organization.tasks.filter { $0.completed == nil }
    return Array((open.filter(\.today) + open.filter { !$0.today }.reversed()).prefix(3))
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

private struct WeatherTile: View {
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

private struct TopAppsTile: View {
  @ObservedObject var controller: PetController
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
    return totals.sorted { $0.value.1 > $1.value.1 }.prefix(3).map { id, value in
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
