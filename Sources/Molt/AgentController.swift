import AppKit
import MoltCore
import Network
import SwiftUI

/// Molt's link to the coding agents on this Mac. Claude Code calls Molt through HTTP hooks and
/// Codex through its `notify` program, both on a loopback port guarded by a random token. Molt
/// shows what each agent is doing, lets you answer approvals from the notch, and counts finished
/// work. If Molt isn't running, the agents fall back to asking in the terminal as usual.
@MainActor final class AgentController: ObservableObject {
  enum Status: String { case idle, working, needsYou, done }
  struct Live: Identifiable, Equatable {
    var id: String
    var agent: String
    var directory: String
    var status: Status
    var since: Date
    var turnStarted: Date?
    var message: String
    var project: String { directory.isEmpty ? "" : URL(fileURLWithPath: directory).lastPathComponent }
  }
  struct Pending: Identifiable {
    var id = UUID()
    var event: AgentEvent
    var risk: ApprovalRisk
    var why: String
    var received: Date
    /// For edits: what would change, so you can read the diff before allowing it.
    var change: ProposedChange?
    fileprivate var connection: NWConnection
    var questions: [AgentQuestion] { event.tool == "AskUserQuestion" ? event.questions : [] }
    var isQuestion: Bool { !questions.isEmpty }
  }
  struct Finished: Identifiable, Equatable {
    var id = UUID()
    var agent: String
    var project: String
    var message: String
    var duration: TimeInterval
    var date: Date
  }
  struct Running: Identifiable, Equatable {
    var id: Int32 { pid }
    var pid: Int32
    var kind: AgentKind
    var cpu: Double
    var memory: Int
    var elapsed: TimeInterval
  }
  struct Saved: Codable {
    var rules: [ApprovalRule] = []
    var habits = ApprovalHabits()
    var tasksFinished = 0
    var terminalFirst = true
    var longTask: Double = 20
    /// Finished tasks per day (`yyyy-MM-dd`), for the weekly recap.
    var finishedDays: [String: Int]? = nil
  }
  /// Agent tasks finished in the last seven days.
  var finishedThisWeek: Int {
    let cutoff = ActivityEngine.day(Date().addingTimeInterval(-6 * 86400))
    return (saved.finishedDays ?? [:]).filter { $0.key >= cutoff }.reduce(0) { $0 + $1.value }
  }

  /// `MOLT_AGENT_PORT` moves the listener, for self-tests next to a running Molt.
  static let port: UInt16 = ProcessInfo.processInfo.environment["MOLT_AGENT_PORT"].flatMap(UInt16.init) ?? 43822
  static var base: String { "http://127.0.0.1:\(port)" }
  @Published private(set) var pending: [Pending] = []
  @Published private(set) var live: [String: Live] = [:]
  @Published private(set) var finished: [Finished] = []
  @Published private(set) var running: [Running] = []
  @Published private(set) var claudeHooks = false
  @Published private(set) var codexNotify = false
  @Published private(set) var listening = false
  @Published var suggestion: String?
  @Published var status = ""
  @Published var saved = Saved() { didSet { save() } }
  /// Called for things worth surfacing in the notch even when it's closed.
  var onBanner: (IslandBanner) -> Void = { _ in }
  var isTerminalFrontmost: () -> Bool = {
    let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm"]
    return terminals.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
  }

  private let url: URL
  private let token: String
  private var handedToTerminal: Set<String> = []
  private var listener: NWListener?
  private var sampler: Timer?

  init(directory: URL) {
    url = directory.appendingPathComponent("agents.json")
    if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Saved.self, from: data) { saved = value }
    if let stored = UserDefaults.standard.string(forKey: "agentToken"), stored.count >= 32 {
      token = stored
    } else {
      token = (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
      UserDefaults.standard.set(token, forKey: "agentToken")
    }
    // Session rules only matter for a day.
    saved.rules.removeAll { $0.session != nil && $0.created < Date().addingTimeInterval(-86400) }
    refreshInstallState()
  }
  private func save() {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
  }

  var working: [Live] { live.values.filter { $0.status == .working }.sorted { $0.since > $1.since } }
  var needsYou: Bool { !pending.isEmpty || live.values.contains { $0.status == .needsYou } }
  /// The agent whose color Molt wears right now, if any.
  var activeAgent: String? { pending.first?.event.agent ?? working.first?.agent }
  /// Molt's mood from what the agents are doing; nil when they're quiet.
  var mood: String? {
    if needsYou { return "alert" }
    if !working.isEmpty { return "working" }
    if let last = finished.first, Date().timeIntervalSince(last.date) < 6 { return "celebrating" }
    return nil
  }

  // MARK: Server

  func start(upgradingHooks: Bool = true) {
    guard listener == nil else { return }
    if upgradingHooks { upgradeHooks() }
    do {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
      parameters.allowLocalEndpointReuse = true
      let listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in
        connection.start(queue: .main)
        Self.receive(connection, buffer: Data()) { request in
          MainActor.assumeIsolated { self?.handle(request, on: connection) }
        }
      }
      listener.stateUpdateHandler = { [weak self] state in
        MainActor.assumeIsolated {
          switch state {
          case .ready: self?.listening = true
          case .failed(let error):
            self?.listening = false
            self?.status = "Molt couldn't listen for agents: \(error.localizedDescription)"
            self?.listener = nil
          default: break
          }
        }
      }
      listener.start(queue: .main)
      self.listener = listener
    } catch { status = "Molt couldn't listen for agents: \(error.localizedDescription)" }
  }

  struct Request { var path: String; var token: String?; var body: Data }

  /// Reads one HTTP request: headers, then exactly `Content-Length` bytes of body (at most 2 MB).
  nonisolated private static func receive(_ connection: NWConnection, buffer: Data, done: @escaping (Request?) -> Void) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { data, _, complete, error in
      var buffer = buffer
      if let data { buffer.append(data) }
      guard buffer.count < 2_000_000 else { connection.cancel(); return }
      if let split = buffer.range(of: Data("\r\n\r\n".utf8)) {
        let head = String(decoding: buffer[..<split.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
          guard let colon = line.firstIndex(of: ":") else { continue }
          headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[split.upperBound...]
        if body.count >= length || complete {
          guard parts.count >= 2, parts[0] == "POST" else { done(nil); return }
          done(Request(path: String(parts[1]), token: headers["x-molt-token"], body: Data(body.prefix(length))))
          return
        }
      }
      if complete || error != nil { connection.cancel(); return }
      receive(connection, buffer: buffer, done: done)
    }
  }
  private func reply(_ connection: NWConnection, status: String = "200 OK", body: Data = Data("{}".utf8)) {
    var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
    response.append(body)
    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
  }

  private func handle(_ request: Request?, on connection: NWConnection) {
    guard let request else { reply(connection, status: "400 Bad Request"); return }
    guard let given = request.token, Self.same(given, token) else { reply(connection, status: "403 Forbidden"); return }
    let event: AgentEvent?
    switch request.path {
    case ClaudeHookInstaller.marker: event = AgentEvent.claude(request.body)
    case "/molt/codex": event = AgentEvent.codex(request.body)
    default: event = nil
    }
    guard let event else { reply(connection); return }
    if event.kind == .permission || event.kind == .question {
      ask(event, on: connection)
    } else {
      reply(connection)
      apply(event)
    }
  }
  /// Compares tokens without leaking how much matched through timing.
  nonisolated static func same(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }

  // MARK: Events

  private func apply(_ event: AgentEvent) {
    let key = event.agent + ":" + event.session
    var entry = live[key] ?? Live(id: key, agent: event.agent, directory: event.directory, status: .idle, since: Date(), turnStarted: nil, message: "")
    if !event.directory.isEmpty { entry.directory = event.directory }
    switch event.kind {
    case .start: entry.status = .idle
    case .prompt:
      entry.status = .working; entry.turnStarted = Date(); entry.message = event.message
    case .notification:
      if event.raw["notification_type"] == "permission_prompt" { entry.status = .needsYou }
    case .toolDone:
      if entry.status != .working { entry.status = .working; entry.turnStarted = entry.turnStarted ?? Date() }
    case .stop:
      let duration = entry.turnStarted.map { Date().timeIntervalSince($0) } ?? 0
      entry.status = .done
      entry.message = event.message
      entry.turnStarted = nil
      let item = Finished(agent: event.agent, project: entry.project, message: Self.firstLine(event.message), duration: duration, date: Date())
      finished.insert(item, at: 0)
      finished = Array(finished.prefix(30))
      // Codex reports only finished turns, so every one counts.
      if duration >= 10 || event.agent == "codex" {
        saved.tasksFinished += 1
        var days = saved.finishedDays ?? [:]
        days[ActivityEngine.day(Date()), default: 0] += 1
        let cutoff = ActivityEngine.day(Date().addingTimeInterval(-60 * 86400))
        saved.finishedDays = days.filter { $0.key >= cutoff }
      }
      if duration >= saved.longTask || event.agent == "codex" { onBanner(.finished(item)) }
    case .end:
      live[key] = nil
      return
    case .permission, .question: break
    }
    entry.since = Date()
    live[key] = entry
    // Forget sessions that went quiet hours ago.
    live = live.filter { $0.value.since > Date().addingTimeInterval(-6 * 3600) }
  }

  private func ask(_ event: AgentEvent, on connection: NWConnection) {
    let question = event.tool == "AskUserQuestion"
    // A question you chose to answer in the terminal can come back as a permission request.
    if question, handedToTerminal.contains(event.toolUseID) {
      reply(connection)
      return
    }
    if !question, let rule = ApprovalRule.applies(saved.rules, tool: event.tool, target: event.target, session: event.session) {
      reply(connection, body: PermissionReply.allow())
      status = "Allowed \(rule.signature) by your rule."
      return
    }
    // When you're already in the terminal, let it ask you there.
    if saved.terminalFirst && isTerminalFrontmost() {
      reply(connection)
      return
    }
    let assessment = ApprovalRisk.assess(tool: event.tool, target: event.target)
    var item = Pending(event: event, risk: assessment.risk, why: assessment.why, received: Date(), change: nil, connection: connection)
    if question, item.questions.isEmpty {
      // Nothing Molt can show; let the terminal handle it.
      reply(connection)
      return
    }
    item.change = Self.change(for: event)
    pending.append(item)
    var entry = live[event.agent + ":" + event.session] ?? Live(id: event.agent + ":" + event.session, agent: event.agent, directory: event.directory, status: .needsYou, since: Date(), turnStarted: Date(), message: "")
    entry.status = .needsYou
    entry.since = Date()
    live[entry.id] = entry
    onBanner(.approval(item.id))
    // If the agent gives up (you pressed Esc), the connection closes; drop the card.
    let id = item.id
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, complete, error in
      guard complete || error != nil else { return }
      Task { @MainActor [weak self] in
        guard let self, let index = self.pending.firstIndex(where: { $0.id == id }) else { return }
        _ = self.take(self.pending[index].id)
      }
    }
    // Claude Code gives the hook ten minutes; hand the question back to the terminal before that.
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 580_000_000_000)
      self?.answerInTerminal(id)
    }
  }

  func allow(_ id: UUID, remember: Bool = false) {
    // Questions need an answer, not just a yes.
    guard pending.first(where: { $0.id == id })?.isQuestion != true, let item = take(id) else { return }
    reply(item.connection, body: PermissionReply.allow())
    let signature = ApprovalRule.signature(tool: item.event.tool, target: item.event.target)
    if remember {
      saved.rules.append(ApprovalRule(signature: signature, session: item.event.session, created: Date()))
    } else if let habit = saved.habits.approved(signature, risk: item.risk) {
      suggestion = habit
    }
  }
  func deny(_ id: UUID, message: String = "The user declined this from Molt.") {
    if pending.first(where: { $0.id == id })?.isQuestion == true { answerInTerminal(id); return }
    guard let item = take(id) else { return }
    reply(item.connection, body: PermissionReply.deny(message))
  }
  /// Gives the question back to the agent's own prompt in the terminal.
  func answerInTerminal(_ id: UUID) {
    guard let item = take(id) else { return }
    if item.isQuestion {
      handedToTerminal.insert(item.event.toolUseID)
      if handedToTerminal.count > 50 { handedToTerminal.removeFirst() }
    }
    reply(item.connection)
  }
  /// Answers an agent's questions. `choices` maps each question to the labels you picked, or to
  /// what you typed.
  func answer(_ id: UUID, choices: [String: [String]]) {
    guard let item = take(id) else { return }
    let body = item.event.kind == .question
      ? QuestionReply.preToolUse(input: item.event.input, choices: choices)
      : QuestionReply.permission(input: item.event.input, choices: choices)
    reply(item.connection, body: body)
  }
  /// The diff for an edit request. Files over 512 KB or that aren't text get no "before".
  nonisolated static func change(for event: AgentEvent) -> ProposedChange? {
    guard ["Edit", "MultiEdit", "Write"].contains(event.tool) else { return nil }
    var current: String?
    if event.tool == "Write", let row = try? JSONSerialization.jsonObject(with: event.input) as? [String: Any],
      let path = row["file_path"] as? String,
      let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size <= 512_000,
      let data = FileManager.default.contents(atPath: path)
    {
      current = String(data: data, encoding: .utf8)
    }
    return ProposedChange.from(tool: event.tool, input: event.input, current: current)
  }
  private func take(_ id: UUID) -> Pending? {
    guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
    let item = pending.remove(at: index)
    let key = item.event.agent + ":" + item.event.session
    if var entry = live[key], entry.status == .needsYou, !pending.contains(where: { $0.event.session == item.event.session }) {
      entry.status = .working
      live[key] = entry
    }
    return item
  }
  func acceptSuggestion() {
    guard let signature = suggestion else { return }
    saved.rules.append(ApprovalRule(signature: signature, session: nil, created: Date()))
    suggestion = nil
  }
  func declineSuggestion() {
    guard let signature = suggestion else { return }
    saved.habits.decline(signature)
    suggestion = nil
  }
  func removeRule(_ rule: ApprovalRule) { saved.rules.removeAll { $0.id == rule.id } }
  func dismiss(_ live: Live) { self.live[live.id] = nil }

  static func firstLine(_ text: String) -> String {
    let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    return String(line.replacingOccurrences(of: "**", with: "").prefix(140))
  }

  // MARK: Install

  private var claudeSettings: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
  private var codexConfig: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml") }
  private var codexScript: URL { url.deletingLastPathComponent().appendingPathComponent("codex-notify.sh") }

  /// Hooks added by an older Molt are brought up to date, so questions reach the notch too.
  private func upgradeHooks() {
    guard let data = try? Data(contentsOf: claudeSettings),
      let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      ClaudeHookInstaller.outdated(in: settings),
      // Only hooks this copy of Molt installed; another build's hooks are left alone.
      ClaudeHookInstaller.token(in: settings).map({ Self.same($0, token) }) == true
    else { return }
    connectClaude()
    status = "Claude Code's questions now come to Molt too."
  }
  func refreshInstallState() {
    let settings = (try? Data(contentsOf: claudeSettings)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    claudeHooks = ClaudeHookInstaller.installed(in: settings)
    codexNotify = (try? String(contentsOf: codexConfig, encoding: .utf8))?.contains(codexScript.path) ?? false
  }

  /// Adds Molt's hooks to `~/.claude/settings.json`, keeping a one-time backup of the original.
  func connectClaude() {
    do {
      let fm = FileManager.default
      var settings: [String: Any] = [:]
      if fm.fileExists(atPath: claudeSettings.path) {
        let data = try Data(contentsOf: claudeSettings)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          throw MoltError.invalid("Claude Code's settings file isn't a JSON object, so Molt left it alone.")
        }
        settings = parsed
        let backup = claudeSettings.appendingPathExtension("before-molt")
        if !fm.fileExists(atPath: backup.path) { try data.write(to: backup) }
      } else {
        try fm.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
      }
      let next = ClaudeHookInstaller.install(into: settings, url: Self.base, token: token)
      try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: claudeSettings, options: .atomic)
      status = "Claude Code connected. New sessions report to Molt."
    } catch { status = error.localizedDescription }
    refreshInstallState()
  }
  func disconnectClaude() {
    do {
      let data = try Data(contentsOf: claudeSettings)
      guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
      let next = ClaudeHookInstaller.remove(from: settings)
      try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: claudeSettings, options: .atomic)
      status = "Claude Code disconnected."
    } catch { status = error.localizedDescription }
    refreshInstallState()
  }

  /// Points Codex's `notify` at a small script that tells Molt when a turn ends. An existing
  /// notify program keeps running: the script calls it first.
  func connectCodex() {
    do {
      let fm = FileManager.default
      let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
      let result = try CodexNotifyInstaller.install(into: text, script: codexScript.path)
      if !result.previous.isEmpty || !text.isEmpty {
        let backup = codexConfig.appendingPathExtension("before-molt")
        if !fm.fileExists(atPath: backup.path) { try text.write(to: backup, atomically: true, encoding: .utf8) }
      }
      let previous = result.previous.isEmpty ? existingChain() : result.previous
      let chained = previous.isEmpty ? "" : previous.map(CodexNotifyInstaller.shellQuote).joined(separator: " ") + " \"$1\" >/dev/null 2>&1\n"
      let script = """
        #!/bin/sh
        # Written by Molt. Tells Molt when a Codex turn ends.
        \(chained)/usr/bin/curl -s -m 2 -H 'Content-Type: application/json' -H 'X-Molt-Token: \(token)' --data-binary "$1" \(Self.base)/molt/codex >/dev/null 2>&1
        exit 0

        """
      try fm.createDirectory(at: codexScript.deletingLastPathComponent(), withIntermediateDirectories: true)
      try script.write(to: codexScript, atomically: true, encoding: .utf8)
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexScript.path)
      try fm.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
      try result.config.write(to: codexConfig, atomically: true, encoding: .utf8)
      status = previous.isEmpty ? "Codex connected." : "Codex connected. Your existing notify program still runs."
    } catch CodexNotifyInstaller.Failure.multiline {
      status = "Codex's notify setting spans several lines, so Molt left it alone."
    } catch { status = error.localizedDescription }
    refreshInstallState()
  }
  /// The program Molt's script already chains to, when reconnecting.
  private func existingChain() -> [String] {
    guard let text = try? String(contentsOf: codexConfig.appendingPathExtension("before-molt"), encoding: .utf8),
      let line = text.components(separatedBy: "\n").first(where: CodexNotifyInstaller.isNotify)
    else { return [] }
    return CodexNotifyInstaller.tomlStrings(line) ?? []
  }
  /// Removes Molt's notify line and puts back the one that was there before, if any. Anything
  /// else you changed in the file since stays as it is.
  func disconnectCodex() {
    guard let text = try? String(contentsOf: codexConfig, encoding: .utf8) else { return }
    var lines = text.components(separatedBy: "\n").filter { !$0.contains(codexScript.path) }
    let original = (try? String(contentsOf: codexConfig.appendingPathExtension("before-molt"), encoding: .utf8))?
      .components(separatedBy: "\n").first(where: CodexNotifyInstaller.isNotify)
    if let original, !lines.contains(where: CodexNotifyInstaller.isNotify) { lines.insert(original, at: 0) }
    try? lines.joined(separator: "\n").write(to: codexConfig, atomically: true, encoding: .utf8)
    status = "Codex disconnected."
    refreshInstallState()
  }
  /// Sample sessions for previews and screenshots.
  func loadDemo(approval: Bool, request: String = "command") {
    let now = Date()
    live = [
      "claude:a": Live(id: "claude:a", agent: "claude", directory: "/Users/me/molt", status: approval ? .needsYou : .working, since: now, turnStarted: now.addingTimeInterval(-194), message: ""),
      "codex:b": Live(id: "codex:b", agent: "codex", directory: "/Users/me/website", status: .working, since: now, turnStarted: now.addingTimeInterval(-61), message: ""),
      "claude:c": Live(id: "claude:c", agent: "claude", directory: "/Users/me/api", status: .done, since: now.addingTimeInterval(-300), turnStarted: nil, message: "All 48 tests pass and the branch is pushed."),
    ]
    finished = [Finished(agent: "codex", project: "website", message: "Pushed to main · 48 tests passed", duration: 252, date: now)]
    running = [
      Running(pid: 101, kind: AgentKind.find("claude")!, cpu: 12, memory: 612_000_000, elapsed: 3400),
      Running(pid: 102, kind: AgentKind.find("codex")!, cpu: 31, memory: 1_410_000_000, elapsed: 900),
      Running(pid: 103, kind: AgentKind.find("gemini")!, cpu: 2, memory: 280_000_000, elapsed: 120),
    ]
    saved.tasksFinished = 27
    saved.finishedDays = [ActivityEngine.day(now): 4, ActivityEngine.day(now.addingTimeInterval(-86400)): 7, ActivityEngine.day(now.addingTimeInterval(-3 * 86400)): 5]
    saved.rules = [
      ApprovalRule(signature: "Bash(npm test)", session: nil, created: now),
      ApprovalRule(signature: "Bash(git status)", session: nil, created: now),
      ApprovalRule(signature: "Edit", session: "a", created: now),
    ]
    claudeHooks = true
    codexNotify = true
    if approval {
      var event = AgentEvent(
        kind: .permission, agent: "claude", session: "a", directory: "/Users/me/molt", tool: "Bash",
        target: "git push origin feature/notch-approvals", reason: "Push the branch so CI can run", message: "", raw: [:])
      switch request {
      case "question":
        event.kind = .question
        event.tool = "AskUserQuestion"
        event.input = Data(#"{"questions":[{"question":"Where should Molt keep the approval history?","header":"Storage","multiSelect":false,"options":[{"label":"SQLite","description":"Alongside tasks, transactional"},{"label":"JSON file","description":"Simple, like hub.json"},{"label":"Keychain","description":"Encrypted, small values only"},{"label":"Don't keep it","description":"Forget after answering"}]}]}"#.utf8)
        event.target = "Where should Molt keep the approval history?"
      case "edit":
        event.tool = "Edit"
        event.target = "/Users/me/molt/Sources/Molt/CreatureView.swift"
        event.reason = ""
        event.input = Data(#"{"file_path":"/Users/me/molt/Sources/Molt/CreatureView.swift","old_string":"    case .happy: hop(period: 0.62, height: 2.2)\n    case .celebrate: hop(period: 0.5, height: 3)","new_string":"    case .happy: hop(period: 0.62, height: 2.2)\n    // Bigger jumps when an agent finishes.\n    case .celebrate: hop(period: 0.45, height: 3.6)"}"#.utf8)
      default: break
      }
      let assessment = ApprovalRisk.assess(tool: event.tool, target: event.target)
      pending = [Pending(event: event, risk: assessment.risk, why: assessment.why, received: now,
        change: Self.change(for: event), connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp))]
    }
  }

  // MARK: Running agents

  /// Samples the agent processes on this Mac while something is watching.
  var sampling = false {
    didSet {
      guard sampling != oldValue else { return }
      sampler?.invalidate()
      guard sampling else { return }
      sample()
      sampler = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in Task { @MainActor in self?.sample() } }
    }
  }
  func sample() {
    Task {
      let output = await QuickActions.output("/bin/ps", ["-axo", "pid=,pcpu=,rss=,etime=,args="])
      running = Self.parseRunning(output)
    }
  }
  nonisolated static func parseRunning(_ output: String) -> [Running] {
    var byKind: [String: Running] = [:]
    for line in output.split(separator: "\n") {
      let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
      guard fields.count == 5, let pid = Int32(fields[0]), let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")),
        let rss = Int(fields[2])
      else { continue }
      let args = fields[4].split(separator: " ").map(String.init)
      guard let first = args.first else { continue }
      var program = URL(fileURLWithPath: first).lastPathComponent
      if ["node", "bun", "deno", "python", "python3"].contains(program), args.count > 1 { program = URL(fileURLWithPath: args[1]).lastPathComponent }
      guard let kind = AgentKind.matching(process: program) else { continue }
      // Agents spawn helpers; report the oldest process with everyone's CPU and memory.
      let elapsed = parseElapsed(String(fields[3]))
      if var existing = byKind[kind.id] {
        existing.cpu += cpu
        existing.memory += rss * 1024
        if elapsed > existing.elapsed { existing.elapsed = elapsed; existing.pid = pid }
        byKind[kind.id] = existing
      } else {
        byKind[kind.id] = Running(pid: pid, kind: kind, cpu: cpu, memory: rss * 1024, elapsed: elapsed)
      }
    }
    return byKind.values.sorted { $0.memory > $1.memory }
  }
  /// `ps` elapsed time: `[[dd-]hh:]mm:ss`.
  nonisolated static func parseElapsed(_ text: String) -> TimeInterval {
    let dayParts = text.split(separator: "-")
    let days = dayParts.count == 2 ? Double(dayParts[0]) ?? 0 : 0
    let clock = (dayParts.last ?? "").split(separator: ":").compactMap { Double($0) }
    let seconds = clock.reversed().enumerated().reduce(0.0) { $0 + $1.element * pow(60, Double($1.offset)) }
    return days * 86400 + seconds
  }
  func stop(_ agent: Running) {
    kill(agent.pid, SIGTERM)
    status = "Asked \(agent.kind.name) to stop."
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sample() }
  }
}

/// Something the notch shows briefly beside the hardware notch while closed.
enum IslandBanner: Equatable {
  case approval(UUID)
  case finished(AgentController.Finished)
  case message(String, symbol: String)
  case habit(String)
  /// A short note from Molt, such as a low battery.
  case notice(String, symbol: String)
  var isApproval: Bool { if case .approval = self { return true } else { return false } }
}
