import AppKit
import MoltCore
import SwiftUI

/// What the menu bar icon opens: Molt, what's going on right now, and four things to do.
/// Arrow keys move through the actions and Return runs one.
struct MenuBarPopup: View {
  @ObservedObject var controller: PetController
  @ObservedObject var agents: AgentController
  @ObservedObject var media: NowPlayingController
  @ObservedObject var actions: QuickActions
  var run: (String) -> Void
  @State private var selected = 0
  @FocusState private var focused: Bool
  init(controller: PetController, run: @escaping (String) -> Void) {
    self.controller = controller
    self.agents = controller.agents
    self.media = controller.hub.media
    self.actions = controller.hub.actions
    self.run = run
  }
  private var items: [(id: String, title: String, symbol: String, key: String)] {
    [
      ("home", "Open \(controller.petName)", "house.fill", "⌘⇧↩"), ("lens", "Ask about screen", "text.viewfinder", "⌘⇧L"),
      ("play", "Play with \(controller.petName)", "gamecontroller.fill", ""),
      ("tracking", controller.organization.consent.paused ? "Resume app tracking" : "Pause app tracking",
        controller.organization.consent.paused ? "play.circle" : "pause.circle", ""),
    ]
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      now
      VStack(spacing: 2) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          Button { run(item.id) } label: {
            HStack(spacing: 10) {
              Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                .foregroundStyle(index == selected ? Color.white : Color.white.opacity(0.6))
              Text(item.title).font(.system(size: 13))
              Spacer(minLength: 4)
              Text(item.key).font(.system(size: 11)).foregroundStyle(index == selected ? Color.white.opacity(0.8) : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(index == selected ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .onHover { if $0 { selected = index } }
        }
      }
      Divider().opacity(0.4)
      HStack {
        Button("Settings…") { run("settings") }
        Spacer()
        Button("Quit Molt") { run("quit") }
      }
      .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6)).padding(.horizontal, 10)
    }
    .padding(14)
    .frame(width: 300)
    .foregroundStyle(.white)
    .environment(\.colorScheme, .dark)
    .background(Button("") { run(items[selected].id) }.keyboardShortcut(.defaultAction).opacity(0).accessibilityHidden(true))
    .focusable()
    .focused($focused)
    .onAppear { focused = true }
    .onMoveCommand { direction in
      switch direction {
      case .down: selected = min(items.count - 1, selected + 1)
      case .up: selected = max(0, selected - 1)
      default: break
      }
    }
    .animation(.easeOut(duration: 0.12), value: selected)
  }
  private var header: some View {
    HStack(spacing: 12) {
      CreatureView(appearance: controller.companion.appearance, mood: controller.isResting ? "sleeping" : controller.displayMood, shell: controller.shellColor)
        .frame(width: 46, height: 43)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
          RadialGradient(colors: [MoltTheme.body(controller.companion.appearance.palette).opacity(0.25), Color.white.opacity(0.04)], center: .bottom, startRadius: 4, endRadius: 50)))
      VStack(alignment: .leading, spacing: 3) {
        Text(controller.petName).font(.system(size: 15, weight: .bold))
        Text("Day \(controller.age + 1) · \(feeling)").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
        HStack(spacing: 4) {
          bar("hunger", .orange); bar("energy", .yellow); bar("affection", .pink)
        }.padding(.top, 3)
      }
    }
  }
  private var feeling: String {
    if controller.lowBattery { return "Getting sleepy" }
    let score = controller.score
    return score >= 75 ? "Feeling great" : score >= 45 ? "Doing okay" : "Could use some care"
  }
  private func bar(_ key: String, _ tint: Color) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.12))
        Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, (controller.state.stats[key] ?? 0) / 100)))
      }
    }.frame(height: 4)
  }
  /// Agents, a recording, focus and music, whichever are going.
  @ViewBuilder private var now: some View {
    let rows = liveRows
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("RIGHT NOW").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(Color.white.opacity(0.35))
        VStack(spacing: 0) {
          ForEach(rows, id: \.title) { row in
            HStack(spacing: 9) {
              Circle().fill(row.tint).frame(width: 7, height: 7)
              VStack(alignment: .leading, spacing: 0) {
                Text(row.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(row.detail).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
              }
              Spacer(minLength: 4)
              Button(row.button, action: row.action)
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.75))
                .padding(.horizontal, 9).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 10).frame(height: 38)
          }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
      }
    }
  }
  private struct LiveRow { var tint: Color; var title: String; var detail: String; var button: String; var action: () -> Void }
  private var liveRows: [LiveRow] {
    var rows: [LiveRow] = []
    if agents.needsYou {
      rows.append(LiveRow(tint: .orange, title: AgentKind.find(agents.activeAgent ?? "")?.name ?? "An agent", detail: "Needs you", button: "Open") { run("agents") })
    } else if let first = agents.working.first {
      let name = AgentKind.find(first.agent)?.name ?? "Agent"
      let detail = [first.project, "working \(AgentsView.duration(Date().timeIntervalSince(first.since)))"].filter { !$0.isEmpty }.joined(separator: " · ")
      rows.append(LiveRow(tint: MoltTheme.agent(first.agent), title: agents.working.count > 1 ? "\(name) and \(agents.working.count - 1) more" : name, detail: detail, button: "Open") { run("agents") })
    }
    if let started = actions.recording {
      rows.append(LiveRow(tint: .red, title: "Recording", detail: HangoutView.clock(Date().timeIntervalSince(started)), button: "Stop") { actions.stopRecording() })
    }
    if let session = controller.openFocus {
      let left = controller.focusClock(session, at: Date())
      rows.append(LiveRow(tint: .green, title: "Focus", detail: session.lastResumed == nil ? "Paused" : "\(FocusTile.clock(left)) left",
        button: session.lastResumed == nil ? "Resume" : "Pause") { controller.changeFocus(session.lastResumed == nil ? "resume" : "pause") })
    }
    if let track = media.track {
      rows.append(LiveRow(tint: .pink, title: track.title, detail: track.artist, button: media.isPlaying ? "Pause" : "Play") { media.playPause() })
    }
    return rows
  }
}
