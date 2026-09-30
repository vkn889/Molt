import Foundation

/// One Claude Code or Codex conversation, summarized from its local JSONL transcript.
public struct AgentSession: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var tool: String
  public var path: String
  public var title: String
  public var project: String
  public var started: Date
  public var updated: Date
  public var messages: Int
  public var tokens: Int
  public init(
    id: String, tool: String, path: String, title: String, project: String, started: Date,
    updated: Date, messages: Int, tokens: Int
  ) {
    self.id = id; self.tool = tool; self.path = path; self.title = title; self.project = project
    self.started = started; self.updated = updated; self.messages = messages; self.tokens = tokens
  }
}

public struct AgentMessage: Equatable, Sendable {
  public var role: String
  public var text: String
  public var date: Date?
}

/// Reads conversation text from Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`)
/// transcripts. Tool calls, tool output and injected context are skipped; only what you and the
/// agent said to each other is kept.
public enum AgentSessionParser {
  public static func messages(lines: [String], tool: String) -> [AgentMessage] {
    var result: [AgentMessage] = []
    var codexEvents: [AgentMessage] = []
    var codexItems: [AgentMessage] = []
    for line in lines {
      guard let data = line.data(using: .utf8),
        let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      let date = (row["timestamp"] as? String).flatMap(parseDate)
      if tool == "Codex" {
        guard let payload = row["payload"] as? [String: Any] else { continue }
        let type = payload["type"] as? String
        if row["type"] as? String == "event_msg" {
          if type == "user_message", let text = payload["message"] as? String {
            append(&codexEvents, role: "user", text: text, date: date)
          } else if type == "agent_message", let text = payload["message"] as? String {
            append(&codexEvents, role: "assistant", text: text, date: date)
          }
        } else if row["type"] as? String == "response_item", type == "message",
          let role = payload["role"] as? String, role == "user" || role == "assistant"
        {
          append(&codexItems, role: role, text: joined(payload["content"]), date: date)
        }
      } else {
        guard row["isMeta"] as? Bool != true, row["isSidechain"] as? Bool != true,
          let kind = row["type"] as? String, kind == "user" || kind == "assistant",
          let message = row["message"] as? [String: Any]
        else { continue }
        append(&result, role: kind, text: joined(message["content"]), date: date)
      }
    }
    if tool == "Codex" { return codexEvents.isEmpty ? codexItems : codexEvents }
    return result
  }

  public static func summary(lines: [String], tool: String, path: String, modified: Date) -> AgentSession? {
    let conversation = messages(lines: lines, tool: tool)
    // Internal runs (such as Codex's approval reviewer) contain no message you wrote.
    guard conversation.contains(where: { $0.role == "user" }) else { return nil }
    var project = ""
    var named: String?
    for line in lines.prefix(400) {
      guard let data = line.data(using: .utf8),
        let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      if row["type"] as? String == "summary", let text = row["summary"] as? String, named == nil {
        named = text
      }
      if project.isEmpty {
        project = row["cwd"] as? String ?? (row["payload"] as? [String: Any])?["cwd"] as? String ?? ""
      }
    }
    let firstPrompt = conversation.first { $0.role == "user" }?.text ?? ""
    let title = (named ?? firstPrompt).components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Untitled"
    let tokens = LocalUsageParser.records(lines: lines, tool: tool, source: path)
      .reduce(0) { $0 + $1.input + $1.output + $1.cached }
    let dates = conversation.compactMap(\.date)
    return AgentSession(
      id: tool + ":" + path, tool: tool, path: path, title: String(title.prefix(160)),
      project: project.isEmpty ? "" : URL(fileURLWithPath: project).lastPathComponent,
      started: dates.min() ?? modified, updated: dates.max() ?? modified,
      messages: conversation.count, tokens: tokens)
  }

  private static func append(_ list: inout [AgentMessage], role: String, text: String, date: Date?) {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Codex wraps requests that mention files; keep only what was typed.
    if let marker = trimmed.range(of: "## My request"),
      let lineEnd = trimmed[marker.upperBound...].firstIndex(of: "\n")
    {
      trimmed = trimmed[trimmed.index(after: lineEnd)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // Injected context, slash-command plumbing and interruption markers are not conversation.
    let injected = ["<", "Caveat:", "[Request interrupted", "# AGENTS.md instructions", "The following is the Codex agent history"]
    guard !trimmed.isEmpty, !injected.contains(where: trimmed.hasPrefix) else { return }
    list.append(AgentMessage(role: role, text: trimmed, date: date))
  }
  private static func joined(_ content: Any?) -> String {
    if let text = content as? String { return text }
    guard let parts = content as? [[String: Any]] else { return "" }
    return parts.compactMap { part -> String? in
      let type = part["type"] as? String
      guard type == "text" || type == "input_text" || type == "output_text" else { return nil }
      return part["text"] as? String
    }.joined(separator: "\n")
  }
  private static func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
