import AppKit
import MoltCore
import SwiftUI

/// Everything about your coding agents: who's working, your chats with them, plan limits,
/// GitHub, and how approvals are answered. Same footprint as Home.
struct AgentsView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var agents: AgentController
  @ObservedObject var plans: PlanController
  @ObservedObject var github: GitHubController
  @ObservedObject var sessions: SessionsController
  @ObservedObject var social: SocialController
  @AppStorage("agentsTab") private var tab = "Live"
  static let tabs: [(String, String)] = [
    ("Live", "bolt.fill"), ("Chats", "text.bubble.fill"), ("Usage", "gauge.with.dots.needle.67percent"),
    ("GitHub", "arrow.triangle.pull"), ("Setup", "slider.horizontal.3"),
  ]
  init(controller: PetController) {
    self.controller = controller
    agents = controller.agents
    plans = controller.plans
    github = controller.github
    sessions = controller.hub.sessions
    social = controller.social
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 4) {
        ForEach(Self.tabs, id: \.0) { item in
          Button { tab = item.0 } label: {
            Label(item.0, systemImage: item.1).font(.system(size: 10, weight: .semibold))
              .padding(.horizontal, 9).frame(height: 22)
              .foregroundStyle(tab == item.0 ? Color.white : Color.white.opacity(0.55))
              .background(Capsule().fill(Color.white.opacity(tab == item.0 ? 0.14 : 0.04)))
              .contentShape(Capsule())
          }.buttonStyle(.plain).accessibilityAddTraits(tab == item.0 ? .isSelected : [])
        }
        Spacer(minLength: 4)
        if !agents.status.isEmpty {
          Text(agents.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Group {
        switch tab {
        case "Chats": SessionsView(sessions: sessions, compact: true)
        case "Usage": usage
        case "GitHub": GitHubPanel(github: github)
        case "Setup": setup
        default: live
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 12)
    .onAppear { agents.sampling = true; plans.refresh(); github.refresh(); agents.refreshInstallState() }
    .onDisappear { agents.sampling = false }
  }

  // MARK: Live

  @State private var stopping: Int32?
  private var live: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        let entries = agents.live.values.sorted { order($0) < order($1) || (order($0) == order($1) && $0.since > $1.since) }
        if entries.isEmpty {
          if !agents.claudeHooks && !agents.codexNotify {
            connectPrompt
          } else {
            Text("No agent sessions yet. Start Claude Code or Codex in a terminal and Molt will follow along.")
              .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(8)
          }
        }
        ScrollView {
          VStack(spacing: 4) {
            ForEach(entries) { entry in liveRow(entry) }
          }
        }
      }
      .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Running on this Mac").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
          Spacer()
          Text("\(agents.saved.tasksFinished) done").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
            .help("Agent tasks finished while Molt was watching")
        }
        if agents.running.isEmpty {
          Text("No agents running.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        ForEach(agents.running.prefix(4)) { item in
          HStack(spacing: 6) {
            Circle().fill(MoltTheme.agent(item.kind.id)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
              Text(item.kind.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
              Text("\(HealthDetailController.bytes(Int64(item.memory))) · \(Int(item.cpu))% CPU · \(Self.duration(item.elapsed))")
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(item.memory > 4_000_000_000 ? .orange : Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            Button(stopping == item.pid ? "Stop?" : "Stop") {
              if stopping == item.pid { agents.stop(item); stopping = nil } else { stopping = item.pid }
            }
            .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(stopping == item.pid ? .red : Color.secondary)
            .help("Ask \(item.kind.name) to quit")
          }
        }
        Spacer(minLength: 0)
      }
      .padding(10).frame(width: 236).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
    }
  }
  private func order(_ live: AgentController.Live) -> Int {
    switch live.status { case .needsYou: return 0; case .working: return 1; case .done: return 2; case .idle: return 3 }
  }
  private func liveRow(_ entry: AgentController.Live) -> some View {
    HStack(spacing: 8) {
      CreatureView(
        appearance: controller.companion.appearance,
        mood: entry.status == .working ? "working" : entry.status == .needsYou ? "alert" : entry.status == .done ? "happy" : "idle",
        moving: entry.status != .idle, shell: MoltTheme.agent(entry.agent), followsPointer: false
      ).frame(width: 28, height: 26)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text(AgentKind.find(entry.agent)?.name ?? entry.agent).font(.system(size: 11, weight: .semibold))
          if !entry.project.isEmpty { Text(entry.project).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
        }
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(statusText(entry, now: context.date)).font(.system(size: 10)).lineLimit(1)
            .foregroundStyle(entry.status == .needsYou ? .orange : entry.status == .working ? Color.accentColor : Color.secondary)
        }
      }
      Spacer(minLength: 4)
      if entry.status == .done || entry.status == .idle {
        Button { agents.dismiss(entry) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
          .buttonStyle(NotchIconButtonStyle(size: 20)).accessibilityLabel("Dismiss")
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
  }
  private func statusText(_ entry: AgentController.Live, now: Date) -> String {
    switch entry.status {
    case .needsYou: return "Needs you"
    case .working: return "Working · \(Self.duration(now.timeIntervalSince(entry.turnStarted ?? entry.since)))"
    case .done: return entry.message.isEmpty ? "Done \(entry.since.formatted(.relative(presentation: .named)))" : AgentController.firstLine(entry.message)
    case .idle: return "Waiting for you"
    }
  }
  private var connectPrompt: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Connect your agents").font(.system(size: 13, weight: .semibold))
      Text("Molt adds a hook so Claude Code asks you here, and tells you when Claude Code or Codex finishes. If Molt isn't running, they ask in the terminal as before.")
        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Connect Claude Code", action: agents.connectClaude)
        Button("Connect Codex", action: agents.connectCodex)
      }
    }.padding(4)
  }

  // MARK: Usage

  private var usage: some View {
    HStack(spacing: 10) {
      planCard("Claude", tint: .orange, limits: plans.claude, tokens: sessions.tokens(tool: "Claude Code", since: Calendar.current.startOfDay(for: Date()))) {
        if !plans.claudeEnabled && plans.claude == nil {
          VStack(alignment: .leading, spacing: 4) {
            Text("See your exact 5-hour and weekly limits, using Claude Code's sign-in. macOS asks before Molt can read it.")
              .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Show Claude limits") { plans.claudeEnabled = true }
          }
        } else if !plans.claudeStatus.isEmpty {
          Text(plans.claudeStatus).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
      }
      planCard("Codex", tint: .teal, limits: plans.codex, tokens: sessions.tokens(tool: "Codex", since: Calendar.current.startOfDay(for: Date()))) {
        if plans.codex == nil {
          Text("Limits appear after your next Codex session.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
    }
    .onAppear { plans.refresh(force: true); sessions.scan() }
  }
  private func planCard<Extra: View>(_ title: String, tint: Color, limits: PlanLimits?, tokens: Int, @ViewBuilder extra: () -> Extra) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Circle().fill(tint).frame(width: 7, height: 7)
        Text(title).font(.system(size: 12, weight: .semibold))
        if let plan = limits?.plan { Text(plan.capitalized).font(.system(size: 10)).foregroundStyle(.secondary) }
        Spacer()
        Text("\(SessionsView.compact(tokens)) tokens today").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
      }
      if let limits {
        if let window = limits.session { LimitBar(title: "5 hours", window: window, tint: tint) }
        if let window = limits.week { LimitBar(title: "Week", window: window, tint: tint) }
      }
      extra()
      Spacer(minLength: 0)
    }
    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
  }

  // MARK: Setup

  private var setup: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Connections").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        connection("Claude Code", detail: "Approvals and status", on: agents.claudeHooks, connect: agents.connectClaude, disconnect: agents.disconnectClaude)
        connection("Codex", detail: "Finished turns", on: agents.codexNotify, connect: agents.connectCodex, disconnect: agents.disconnectCodex)
        toggle("Read Claude Code & Codex chats", $sessions.enabled)
        toggle("Keep private copies of chats", $sessions.archive).disabled(!sessions.enabled)
        toggle("Ask in the terminal when it's in front", $agents.saved.terminalFirst)
        toggle("Show friends which agent I'm using", $social.shareActivity)
        HStack {
          Text("Tell me when a task took over").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8))
          Spacer()
          Picker("", selection: $agents.saved.longTask) {
            Text("10 s").tag(10.0); Text("20 s").tag(20.0); Text("1 min").tag(60.0); Text("3 min").tag(180.0)
          }.labelsHidden().controlSize(.small).frame(width: 74)
        }
      }
      .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text("Always allowed").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        if agents.saved.rules.isEmpty {
          Text("Nothing yet. Choose \"This session\" on an approval, or let Molt suggest habits. Risky commands always ask.")
            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        ScrollView {
          VStack(spacing: 3) {
            ForEach(agents.saved.rules) { rule in
              HStack(spacing: 6) {
                Text(rule.signature).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                Spacer(minLength: 4)
                Text(rule.session == nil ? "Always" : "This session").font(.system(size: 9)).foregroundStyle(.secondary)
                Button { agents.removeRule(rule) } label: { Image(systemName: "minus.circle.fill").font(.system(size: 11)) }
                  .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove rule")
              }
            }
          }
        }
      }
      .padding(12).frame(width: 260).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
    }
  }
  private func connection(_ title: String, detail: String, on: Bool, connect: @escaping () -> Void, disconnect: @escaping () -> Void) -> some View {
    HStack(spacing: 6) {
      Circle().fill(on ? Color.green : Color.white.opacity(0.25)).frame(width: 6, height: 6)
      Text(title).font(.system(size: 11, weight: .medium))
      Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
      Spacer(minLength: 4)
      Button(on ? "Disconnect" : "Connect", action: on ? disconnect : connect)
        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
    }
  }
  private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
    HStack {
      Text(title).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
      Spacer(minLength: 4)
      Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }
  }

  // MARK: Helpers

  static func duration(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    if s < 86400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
    return "\(s / 86400)d \(s % 86400 / 3600)h"
  }
  static let terminals = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "io.alacritty", "com.apple.Terminal"]
  /// Brings your terminal forward, whichever one you use.
  static func activateTerminal() {
    let running = NSWorkspace.shared.runningApplications
    for id in terminals { if let app = running.first(where: { $0.bundleIdentifier == id }) { app.activate(options: []); return } }
  }
}

/// A plan window as a bar, with the pace forecast underneath.
struct LimitBar: View {
  var title: String
  var window: LimitWindow
  var tint: Color
  var compact = false
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
        Spacer()
        Text("\(Int(window.used.rounded()))%").font(.system(size: 11, weight: .semibold).monospacedDigit())
          .foregroundStyle(window.used >= 90 ? .red : window.used >= 70 ? .orange : .white)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.1))
          Capsule().fill(window.used >= 90 ? Color.red : tint).frame(width: proxy.size.width * window.used / 100)
          // Where you'd be if usage were spread evenly across the window.
          let elapsed = min(1, max(0, Date().timeIntervalSince(window.start) / (Double(window.minutes) * 60)))
          Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1.5, height: 8).offset(x: proxy.size.width * elapsed)
        }
      }.frame(height: 6)
      if !compact {
        Text(PlanController.pace(window)).font(.system(size: 9)).foregroundStyle(window.forecast(now: Date()) != nil ? .orange : Color.secondary)
      }
    }
    .accessibilityElement().accessibilityLabel("\(title): \(Int(window.used)) percent used. \(PlanController.pace(window))")
  }
}

/// Streak, contribution grid, your pull requests and the reviews waiting on you.
struct GitHubPanel: View {
  @ObservedObject var github: GitHubController
  @State private var list = "mine"
  @State private var token = ""
  @State private var editingRepo = false
  var body: some View {
    if github.summary == nil && (!github.enabled || (!github.busy && !github.status.isEmpty)) {
      HStack(spacing: 16) {
        Image(systemName: "arrow.triangle.pull").font(.system(size: 30)).foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 6) {
          Text("Pull requests, checks and your streak").font(.system(size: 14, weight: .semibold))
          Text(github.status.isEmpty ? "Molt uses the GitHub CLI's sign-in (`gh auth login`), or a token you paste. It only talks to api.github.com." : github.status)
            .font(.system(size: 10)).foregroundStyle(github.status.isEmpty ? Color.secondary : .orange).fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 6) {
            Button(github.enabled ? "Try again" : "Turn on") { if github.enabled { github.refresh(force: true) } else { github.enabled = true } }
            SecureField("or paste a token", text: $token).textFieldStyle(.plain).font(.system(size: 11))
              .padding(.horizontal, 8).frame(width: 170, height: 22)
              .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
              .onSubmit { github.setToken(token); token = "" }
          }
        }.frame(maxWidth: 460, alignment: .leading)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let summary = github.summary {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(summary.streak)").font(.system(size: 20, weight: .semibold).monospacedDigit())
            Text("day streak").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text("@\(summary.login)").font(.system(size: 10)).foregroundStyle(.secondary)
          }
          ContributionGrid(days: summary.days, weeks: 20)
          Spacer(minLength: 0)
          HStack(spacing: 5) {
            Circle().fill(Self.color(summary.ci)).frame(width: 7, height: 7)
            Text(summary.repository.map { "\($0) · \(summary.branch ?? "main")" } ?? "Pick a repository in the field below")
              .font(.system(size: 10)).lineLimit(1)
            Spacer(minLength: 2)
            Text(Self.label(summary.ci)).font(.system(size: 10, weight: .medium)).foregroundStyle(Self.color(summary.ci))
            Button { editingRepo.toggle() } label: { Image(systemName: "pencil").font(.system(size: 9, weight: .semibold)) }
              .buttonStyle(.plain).foregroundStyle(.secondary).help("Choose the repository to watch")
              .popover(isPresented: $editingRepo, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                  Text("Watch a repository's default branch").font(.system(size: 11, weight: .semibold))
                  TextField("owner/repo, or blank for where you last worked", text: $github.watched)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 260)
                    .onSubmit { editingRepo = false; github.refresh(force: true) }
                }.padding(12)
              }
          }
        }
        .padding(10).frame(width: 290).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 4) {
            chip("My PRs \(summary.mine.count)", "mine")
            chip("To review \(summary.reviews.count)", "review")
            Spacer()
            if github.busy { ProgressView().controlSize(.mini) }
            Button { github.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)) }
              .buttonStyle(NotchIconButtonStyle(size: 20)).accessibilityLabel("Refresh")
          }
          let items = list == "mine" ? summary.mine : summary.reviews
          if items.isEmpty {
            Text(list == "mine" ? "No open pull requests." : "Nothing waiting on you.").font(.system(size: 11)).foregroundStyle(.secondary)
          }
          ScrollView {
            VStack(spacing: 2) {
              ForEach(items) { pr in
                Button { github.open(pr.url) } label: {
                  HStack(spacing: 6) {
                    Circle().fill(pr.checks.map { Self.color(GitHubSummary.ci($0)) } ?? Color.white.opacity(0.3)).frame(width: 6, height: 6)
                    Text("#\(pr.number)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                    Text(pr.title).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 4)
                    if list == "review" && Date().timeIntervalSince(pr.created) > 86400 {
                      Text(pr.created.formatted(.relative(presentation: .numeric))).font(.system(size: 9)).foregroundStyle(.orange)
                    } else {
                      Text(pr.repository.split(separator: "/").last.map(String.init) ?? "").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                  }
                  .padding(.horizontal, 6).padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain)
              }
            }
          }
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
      }
    } else {
      ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  private func chip(_ title: String, _ value: String) -> some View {
    Button { list = value } label: {
      Text(title).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).frame(height: 20)
        .foregroundStyle(list == value ? Color.white : Color.white.opacity(0.55))
        .background(Capsule().fill(Color.white.opacity(list == value ? 0.14 : 0.04)))
    }.buttonStyle(.plain)
  }
  static func color(_ ci: GitHubSummary.CI) -> Color {
    switch ci { case .passing: return .green; case .failing: return .red; case .running: return .yellow; case .none: return .white.opacity(0.3) }
  }
  static func label(_ ci: GitHubSummary.CI) -> String {
    switch ci { case .passing: return "all green"; case .failing: return "failing"; case .running: return "running"; case .none: return "no checks" }
  }
}

/// The last few months of contributions, a column per week (GitHub's weeks start on Sunday).
struct ContributionGrid: View {
  var days: [GitHubSummary.Day]
  var weeks: Int
  var height: CGFloat = 52
  var body: some View {
    let columns = Array(stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }.suffix(weeks))
    let peak = max(1, columns.joined().map(\.count).max() ?? 1)
    GeometryReader { proxy in
      let size = max(2, min((proxy.size.width - CGFloat(weeks - 1) * 2) / CGFloat(weeks), (proxy.size.height - 12) / 7 + 1.5))
      HStack(alignment: .top, spacing: 2) {
        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
          VStack(spacing: 2) {
            ForEach(column, id: \.date) { day in
              RoundedRectangle(cornerRadius: 1.5)
                .fill(day.count == 0 ? Color.white.opacity(0.07) : Color.green.opacity(0.3 + 0.7 * Double(day.count) / Double(peak)))
                .frame(width: size, height: size)
                .help("\(day.date): \(day.count)")
            }
          }
        }
      }
    }
    .frame(height: height)
    .accessibilityElement().accessibilityLabel("\(columns.joined().reduce(0) { $0 + $1.count }) contributions in the last \(weeks) weeks")
  }
}
