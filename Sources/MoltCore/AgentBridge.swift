import Foundation

/// A coding agent Molt can recognize, by the name of its command-line process.
public struct AgentKind: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  /// Executable names, matched against the last path component of a running process.
  public var processes: [String]
  /// Molt's shell takes this hue (0 to 1) while the agent is working.
  public var hue: Double
  public static let all: [AgentKind] = [
    AgentKind(id: "claude", name: "Claude Code", processes: ["claude"], hue: 0.06),
    AgentKind(id: "codex", name: "Codex", processes: ["codex"], hue: 0.47),
    AgentKind(id: "gemini", name: "Gemini CLI", processes: ["gemini"], hue: 0.6),
    AgentKind(id: "cursor", name: "Cursor Agent", processes: ["cursor-agent"], hue: 0.0),
    AgentKind(id: "opencode", name: "OpenCode", processes: ["opencode"], hue: 0.33),
    AgentKind(id: "amp", name: "Amp", processes: ["amp"], hue: 0.1),
    AgentKind(id: "copilot", name: "Copilot CLI", processes: ["copilot"], hue: 0.75),
    AgentKind(id: "aider", name: "Aider", processes: ["aider"], hue: 0.15),
    AgentKind(id: "goose", name: "Goose", processes: ["goose"], hue: 0.55),
  ]
  public static func matching(process path: String) -> AgentKind? {
    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return all.first { $0.processes.contains(name) }
  }
  public static func find(_ id: String) -> AgentKind? { all.first { $0.id == id } }
}

/// One event an agent reported to Molt through a hook.
public struct AgentEvent: Equatable, Sendable {
  public enum Kind: String, Sendable { case permission, prompt, stop, notification, start, toolDone, end }
  public var kind: Kind
  public var agent: String
  public var session: String
  public var directory: String
  public var tool: String
  /// The command, file or query the tool would act on.
  public var target: String
  /// The agent's own explanation of the tool call, if it gave one.
  public var reason: String
  public var message: String
  public var raw: [String: String]
  public init(kind: Kind, agent: String, session: String, directory: String, tool: String, target: String, reason: String, message: String, raw: [String: String]) {
    self.kind = kind; self.agent = agent; self.session = session; self.directory = directory; self.tool = tool
    self.target = target; self.reason = reason; self.message = message; self.raw = raw
  }

  public var project: String { directory.isEmpty ? "" : URL(fileURLWithPath: directory).lastPathComponent }

  /// Parses a Claude Code hook payload (`hook_event_name` plus event fields).
  public static func claude(_ data: Data) -> AgentEvent? {
    guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let name = row["hook_event_name"] as? String
    else { return nil }
    let kind: Kind
    switch name {
    case "PermissionRequest": kind = .permission
    case "UserPromptSubmit": kind = .prompt
    case "Stop": kind = .stop
    case "Notification": kind = .notification
    case "SessionStart": kind = .start
    case "PostToolUse": kind = .toolDone
    case "SessionEnd": kind = .end
    default: return nil
    }
    let input = row["tool_input"] as? [String: Any] ?? [:]
    let tool = row["tool_name"] as? String ?? ""
    return AgentEvent(
      kind: kind, agent: "claude", session: row["session_id"] as? String ?? "",
      directory: row["cwd"] as? String ?? "", tool: tool, target: target(tool: tool, input: input),
      reason: String((input["description"] as? String ?? "").prefix(300)),
      message: String((row["last_assistant_message"] as? String ?? row["message"] as? String ?? row["prompt"] as? String ?? "").prefix(600)),
      raw: ["tool_use_id": row["tool_use_id"] as? String ?? "", "notification_type": row["notification_type"] as? String ?? ""])
  }

  /// Parses Codex's `notify` payload, which arrives when a turn completes.
  public static func codex(_ data: Data) -> AgentEvent? {
    guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      row["type"] as? String == "agent-turn-complete"
    else { return nil }
    return AgentEvent(
      kind: .stop, agent: "codex", session: row["thread-id"] as? String ?? row["turn-id"] as? String ?? "",
      directory: row["cwd"] as? String ?? "", tool: "", target: "", reason: "",
      message: String((row["last-assistant-message"] as? String ?? "").prefix(600)), raw: [:])
  }

  static func target(tool: String, input: [String: Any]) -> String {
    let keys = ["command", "file_path", "notebook_path", "path", "url", "pattern", "query", "prompt"]
    for key in keys { if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(2000)) } }
    if let questions = input["questions"] as? [[String: Any]], let first = questions.first?["question"] as? String { return first }
    return ""
  }
}

/// How much an approval could hurt, judged from the tool and its command.
public enum ApprovalRisk: Int, Comparable, Sendable {
  case low, medium, high
  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
  public var label: String { ["Low risk", "Changes files", "Careful"][rawValue] }

  public static func assess(tool: String, target: String) -> (risk: ApprovalRisk, why: String) {
    let command = target.lowercased()
    switch tool {
    case "Read", "Glob", "Grep", "LS", "WebSearch", "TodoWrite":
      return (.low, "Only reads")
    case "WebFetch":
      return (.low, "Reads a web page")
    case "Edit", "MultiEdit", "Write", "NotebookEdit":
      let outside = target.hasPrefix("/etc") || target.hasPrefix("/System") || target.hasPrefix("/usr") || target.contains("/.ssh/")
      return outside ? (.high, "Writes outside your project") : (.medium, "Edits a file")
    case "Bash":
      let dangers: [(String, String)] = [
        ("rm -rf", "Deletes files recursively"), ("rm -fr", "Deletes files recursively"), ("sudo ", "Runs as administrator"),
        ("push --force", "Rewrites remote history"), ("push -f", "Rewrites remote history"), ("reset --hard", "Discards your changes"),
        ("clean -fd", "Deletes untracked files"), ("| sh", "Runs a downloaded script"), ("| bash", "Runs a downloaded script"),
        ("chmod -r", "Changes permissions recursively"), ("mkfs", "Formats a disk"), ("dd if=", "Writes raw disk data"),
        ("drop table", "Deletes a database table"), ("drop database", "Deletes a database"), ("> /dev/", "Writes to a device"),
        ("launchctl", "Changes system services"), ("defaults write", "Changes system settings"), ("security ", "Touches the keychain"),
        ("curl ", "Talks to the network"), ("wget ", "Downloads from the network"),
      ]
      if let hit = dangers.first(where: { command.contains($0.0) }) {
        let network = hit.0 == "curl " || hit.0 == "wget "
        return (network ? .medium : .high, hit.1)
      }
      let readOnly = ["ls", "cat", "head", "tail", "pwd", "echo", "grep", "rg", "find", "wc", "which", "git status", "git diff", "git log", "git show", "git branch"]
      if let first = command.split(separator: "|").first?.trimmingCharacters(in: .whitespaces),
        readOnly.contains(where: { first == $0 || first.hasPrefix($0 + " ") })
      {
        return (.low, "Only reads")
      }
      if command.hasPrefix("git commit") || command.hasPrefix("git push") { return (.medium, "Changes your repository") }
      if ["test", "lint", "build", "check"].contains(where: { command.contains($0) }) { return (.low, "Builds or tests") }
      return (.medium, "Runs a command")
    default:
      return tool.hasPrefix("mcp__") ? (.medium, "Uses a connected tool") : (.medium, "Uses \(tool)")
    }
  }
}

/// A rule that answers approvals automatically. Scope is one session, or every session.
public struct ApprovalRule: Codable, Identifiable, Equatable, Sendable {
  public var id = UUID()
  public var signature: String
  public var session: String?
  public var created: Date
  public init(signature: String, session: String?, created: Date) {
    self.signature = signature; self.session = session; self.created = created
  }

  /// What two requests must share to count as "the same thing": the tool, and for commands the
  /// program plus its subcommand (`npm test`, `git status`), never the arguments after them.
  public static func signature(tool: String, target: String) -> String {
    guard tool == "Bash" else { return tool }
    let command = target.trimmingCharacters(in: .whitespacesAndNewlines)
    // Chains and substitutions are never generalized; the exact command must match.
    if command.contains("&&") || command.contains(";") || command.contains("|") || command.contains("$(") || command.contains("`") {
      return "Bash(\(command))"
    }
    let words = command.split(separator: " ").map(String.init)
    guard let program = words.first else { return "Bash()" }
    let takesSubcommand = ["git", "npm", "pnpm", "yarn", "bun", "swift", "cargo", "go", "make", "docker", "gh", "python", "python3", "uv", "pytest", "xcodebuild", "brew"]
    if takesSubcommand.contains(program), words.count > 1, !words[1].hasPrefix("-") {
      return "Bash(\(program) \(words[1]))"
    }
    return "Bash(\(program))"
  }
  public func matches(signature value: String, session: String) -> Bool {
    signature == value && (self.session == nil || self.session == session)
  }
  /// High-risk requests are never answered by a rule.
  public static func applies(_ rules: [ApprovalRule], tool: String, target: String, session: String) -> ApprovalRule? {
    guard ApprovalRisk.assess(tool: tool, target: target).risk != .high else { return nil }
    let value = signature(tool: tool, target: target)
    return rules.first { $0.matches(signature: value, session: session) }
  }
}

/// Counts what you approve, so Molt can offer to remember a habit after a few repeats.
public struct ApprovalHabits: Codable, Equatable, Sendable {
  public var counts: [String: Int] = [:]
  public var declined: Set<String> = []
  public static let threshold = 3
  public init() {}
  /// Records an approval and returns the signature when it has just become a habit worth offering.
  public mutating func approved(_ signature: String, risk: ApprovalRisk) -> String? {
    guard risk != .high, !declined.contains(signature) else { return nil }
    counts[signature, default: 0] += 1
    if counts.count > 400 { counts = counts.filter { $0.value > 1 } }
    return counts[signature] == Self.threshold ? signature : nil
  }
  public mutating func decline(_ signature: String) { declined.insert(signature) }
}

/// The body Claude Code expects back from a PermissionRequest hook.
public enum PermissionReply {
  public static func allow() -> Data { body(["behavior": "allow"]) }
  public static func deny(_ message: String) -> Data {
    body(["behavior": "deny", "message": String(message.prefix(500))])
  }
  private static func body(_ decision: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: [
      "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]
    ])) ?? Data()
  }
}

/// Adds or removes Molt's HTTP hooks in a Claude Code `settings.json`, leaving every other
/// setting and hook exactly as it was.
public enum ClaudeHookInstaller {
  public static let events = ["PermissionRequest", "UserPromptSubmit", "Stop", "Notification", "SessionStart", "SessionEnd"]
  public static let marker = "/molt/hook"

  public static func install(into settings: [String: Any], url: String, token: String) -> [String: Any] {
    var result = remove(from: settings)
    var hooks = result["hooks"] as? [String: Any] ?? [:]
    for event in events {
      var groups = hooks[event] as? [[String: Any]] ?? []
      let hook: [String: Any] = [
        "type": "http", "url": url + marker, "headers": ["X-Molt-Token": token],
        // Approvals wait for you; the other events return at once.
        "timeout": event == "PermissionRequest" ? 600 : 5,
      ]
      groups.append(["hooks": [hook]])
      hooks[event] = groups
    }
    result["hooks"] = hooks
    return result
  }
  public static func remove(from settings: [String: Any]) -> [String: Any] {
    var result = settings
    guard var hooks = result["hooks"] as? [String: Any] else { return result }
    for (event, value) in hooks {
      guard let groups = value as? [[String: Any]] else { continue }
      let kept = groups.compactMap { group -> [String: Any]? in
        guard let list = group["hooks"] as? [[String: Any]] else { return group }
        let remaining = list.filter { !(($0["url"] as? String)?.hasSuffix(marker) ?? false) }
        if remaining.isEmpty { return nil }
        var copy = group
        copy["hooks"] = remaining
        return copy
      }
      hooks[event] = kept.isEmpty ? nil : kept
    }
    result["hooks"] = hooks.isEmpty ? nil : hooks
    return result
  }
  public static func installed(in settings: [String: Any]) -> Bool {
    guard let hooks = settings["hooks"] as? [String: Any], let groups = hooks["PermissionRequest"] as? [[String: Any]] else { return false }
    return groups.contains { group in
      (group["hooks"] as? [[String: Any]])?.contains { ($0["url"] as? String)?.hasSuffix(marker) ?? false } ?? false
    }
  }
}

/// Points Codex's `notify` at Molt's script, keeping any program that was already there.
public enum CodexNotifyInstaller {
  public enum Failure: Error, Equatable { case multiline }
  /// Returns the new config and the notify command that was there before, if any.
  public static func install(into config: String, script: String) throws -> (config: String, previous: [String]) {
    var lines = config.components(separatedBy: "\n")
    var previous: [String] = []
    if let index = lines.firstIndex(where: { isNotify($0) }) {
      guard let parsed = tomlStrings(lines[index]) else { throw Failure.multiline }
      // Already pointing at Molt: keep whatever Molt was chaining before.
      if parsed.last == script { return (config, []) }
      previous = parsed
      lines.remove(at: index)
    }
    // Top-level keys must come before the first [table].
    lines.insert("notify = [\"/bin/sh\", \"\(script)\"]", at: 0)
    return (lines.joined(separator: "\n"), previous)
  }
  public static func isNotify(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("notify") else { return false }
    return trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces).hasPrefix("=")
  }
  /// The strings in a one-line TOML array such as `notify = ["a", "b"]`.
  public static func tomlStrings(_ line: String) -> [String]? {
    guard let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]"), open < close else { return nil }
    var result: [String] = []
    var current = ""
    var inside = false
    var escaped = false
    for char in line[line.index(after: open)..<close] {
      if escaped { current.append(char); escaped = false; continue }
      if char == "\\" && inside { escaped = true; continue }
      if char == "\"" {
        if inside { result.append(current); current = "" }
        inside.toggle()
        continue
      }
      if inside { current.append(char) }
    }
    return inside ? nil : result
  }
  public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Files an agent changed during a conversation, read from its transcript.
public enum AgentChanges {
  public static func files(lines: [String], tool: String) -> [String] {
    var seen: [String] = []
    func add(_ path: String) {
      let trimmed = path.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !seen.contains(trimmed) else { return }
      seen.append(trimmed)
    }
    for line in lines {
      guard line.contains("file_path") || line.contains("apply_patch") || line.contains("*** ") || line.contains("notebook_path"),
        let data = line.data(using: .utf8),
        let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      if tool == "Codex" {
        guard let payload = row["payload"] as? [String: Any] else { continue }
        let text = (payload["input"] as? String) ?? (payload["arguments"] as? String) ?? ""
        for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
          for part in text.components(separatedBy: marker).dropFirst() {
            add(String(part.prefix { $0 != "\n" && $0 != "\\" && $0 != "\"" }))
          }
        }
      } else {
        guard let message = row["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { continue }
        for part in content where part["type"] as? String == "tool_use" {
          guard let name = part["name"] as? String, ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(name),
            let input = part["input"] as? [String: Any]
          else { continue }
          add(input["file_path"] as? String ?? input["notebook_path"] as? String ?? "")
        }
      }
    }
    return Array(seen.suffix(200))
  }

  /// Parses `git diff --numstat` into added and removed line counts per path.
  public static func numstat(_ output: String) -> [String: (added: Int, removed: Int)] {
    var result: [String: (added: Int, removed: Int)] = [:]
    for line in output.split(separator: "\n") {
      let fields = line.split(separator: "\t", maxSplits: 2)
      guard fields.count == 3 else { continue }
      result[String(fields[2])] = (Int(fields[0]) ?? 0, Int(fields[1]) ?? 0)
    }
    return result
  }
}
