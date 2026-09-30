import XCTest
@testable import MoltCore

final class AgentSessionTests: XCTestCase {
  func testClaudeTranscriptKeepsConversationOnly() {
    let lines = [
      #"{"type":"summary","summary":"Fix the login flow"}"#,
      #"{"type":"user","cwd":"/Users/me/app","timestamp":"2026-09-29T10:00:00.000Z","message":{"role":"user","content":"Why does login fail?"}}"#,
      #"{"type":"user","isMeta":true,"timestamp":"2026-09-29T10:00:01.000Z","message":{"role":"user","content":"Caveat: ignore"}}"#,
      #"{"type":"assistant","timestamp":"2026-09-29T10:00:05.000Z","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"The token expires."},{"type":"tool_use","name":"Read"}],"usage":{"input_tokens":40,"output_tokens":12}}}"#,
      #"{"type":"user","timestamp":"2026-09-29T10:00:06.000Z","message":{"role":"user","content":[{"type":"tool_result","content":"file text"}]}}"#,
      #"{"type":"user","timestamp":"2026-09-29T10:00:07.000Z","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
      "not json",
    ]
    let messages = AgentSessionParser.messages(lines: lines, tool: "Claude Code")
    XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
    XCTAssertEqual(messages[1].text, "The token expires.")
    let session = AgentSessionParser.summary(lines: lines, tool: "Claude Code", path: "a.jsonl", modified: Date())
    XCTAssertEqual(session?.title, "Fix the login flow")
    XCTAssertEqual(session?.project, "app")
    XCTAssertEqual(session?.tokens, 52)
    XCTAssertEqual(session?.messages, 2)
  }
  func testCodexPrefersEventMessagesAndSkipsInjectedContext() {
    let lines = [
      #"{"timestamp":"2026-09-29T10:00:00Z","type":"session_meta","payload":{"cwd":"/tmp/site"}}"#,
      #"{"timestamp":"2026-09-29T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#,
      #"{"timestamp":"2026-09-29T10:00:02Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Add a footer"}]}}"#,
      ##"{"timestamp":"2026-09-29T10:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"# AGENTS.md instructions for /tmp/site"}}"##,
      #"{"timestamp":"2026-09-29T10:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"Add a footer"}}"#,
      #"{"timestamp":"2026-09-29T10:00:09Z","type":"event_msg","payload":{"type":"agent_message","message":"Footer added."}}"#,
    ]
    let messages = AgentSessionParser.messages(lines: lines, tool: "Codex")
    XCTAssertEqual(messages.map(\.text), ["Add a footer", "Footer added."])
    let session = AgentSessionParser.summary(lines: lines, tool: "Codex", path: "b.jsonl", modified: Date())
    XCTAssertEqual(session?.title, "Add a footer")
    XCTAssertEqual(session?.project, "site")
  }
  func testEmptyTranscriptHasNoSession() {
    XCTAssertNil(AgentSessionParser.summary(lines: ["{}"], tool: "Codex", path: "c", modified: Date()))
  }
  func testCodexReviewerRunsAreHiddenAndFileMentionsUnwrapped() {
    let reviewer = [
      #"{"type":"event_msg","payload":{"type":"user_message","message":"The following is the Codex agent history whose request action you are assessing."}}"#,
      #"{"type":"event_msg","payload":{"type":"agent_message","message":"{\"risk_level\":\"low\"}"}}"#,
    ]
    XCTAssertNil(AgentSessionParser.summary(lines: reviewer, tool: "Codex", path: "r", modified: Date()))
    let wrapped = [
      ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# Files mentioned by the user:\n\n## a.md: /tmp/a.md\n\n## My request for Codex:\nBuild the page"}]}}"##,
    ]
    XCTAssertEqual(AgentSessionParser.summary(lines: wrapped, tool: "Codex", path: "w", modified: Date())?.title, "Build the page")
  }
}
