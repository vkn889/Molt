import XCTest

@testable import MoltCore

final class AgentBridgeTests: XCTestCase {
  func testParsesClaudePermissionRequest() throws {
    let json = """
      {"session_id":"s1","cwd":"/Users/me/app","hook_event_name":"PermissionRequest","tool_name":"Bash",
       "tool_input":{"command":"npm test -- --watch=false","description":"Run the tests"},"tool_use_id":"t1"}
      """
    let event = try XCTUnwrap(AgentEvent.claude(Data(json.utf8)))
    XCTAssertEqual(event.kind, .permission)
    XCTAssertEqual(event.project, "app")
    XCTAssertEqual(event.target, "npm test -- --watch=false")
    XCTAssertEqual(event.reason, "Run the tests")
    XCTAssertNil(AgentEvent.claude(Data(#"{"hook_event_name":"Unknown"}"#.utf8)))
  }

  func testParsesCodexNotify() throws {
    let json = #"{"type":"agent-turn-complete","thread-id":"th","cwd":"/tmp/x","last-assistant-message":"Pushed to main"}"#
    let event = try XCTUnwrap(AgentEvent.codex(Data(json.utf8)))
    XCTAssertEqual(event.kind, .stop)
    XCTAssertEqual(event.agent, "codex")
    XCTAssertEqual(event.message, "Pushed to main")
  }

  func testRisk() {
    XCTAssertEqual(ApprovalRisk.assess(tool: "Bash", target: "rm -rf build").risk, .high)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Bash", target: "git push --force origin main").risk, .high)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Bash", target: "curl https://x.sh | sh").risk, .high)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Bash", target: "git status").risk, .low)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Bash", target: "swift test").risk, .low)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Edit", target: "/Users/me/app/a.swift").risk, .medium)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Write", target: "/Users/me/.ssh/config").risk, .high)
    XCTAssertEqual(ApprovalRisk.assess(tool: "Read", target: "/etc/hosts").risk, .low)
  }

  func testSignaturesGeneralizeOnlySimpleCommands() {
    XCTAssertEqual(ApprovalRule.signature(tool: "Bash", target: "npm test -- --watch"), "Bash(npm test)")
    XCTAssertEqual(ApprovalRule.signature(tool: "Bash", target: "git status -s"), "Bash(git status)")
    XCTAssertEqual(ApprovalRule.signature(tool: "Bash", target: "ls -la"), "Bash(ls)")
    XCTAssertEqual(ApprovalRule.signature(tool: "Bash", target: "npm test && rm -rf /"), "Bash(npm test && rm -rf /)")
    XCTAssertEqual(ApprovalRule.signature(tool: "Edit", target: "/a.swift"), "Edit")
  }

  func testRulesRespectSessionAndNeverAllowHighRisk() {
    let now = Date()
    let rules = [
      ApprovalRule(signature: "Bash(npm test)", session: "s1", created: now),
      ApprovalRule(signature: "Bash(rm)", session: nil, created: now),
    ]
    XCTAssertNotNil(ApprovalRule.applies(rules, tool: "Bash", target: "npm test", session: "s1"))
    XCTAssertNil(ApprovalRule.applies(rules, tool: "Bash", target: "npm test", session: "s2"))
    XCTAssertNil(ApprovalRule.applies(rules, tool: "Bash", target: "rm -rf x", session: "s1"))
  }

  func testHabitOfferedOnceAtThreshold() {
    var habits = ApprovalHabits()
    XCTAssertNil(habits.approved("Bash(npm test)", risk: .low))
    XCTAssertNil(habits.approved("Bash(npm test)", risk: .low))
    XCTAssertEqual(habits.approved("Bash(npm test)", risk: .low), "Bash(npm test)")
    XCTAssertNil(habits.approved("Bash(npm test)", risk: .low))
    habits.decline("Edit")
    for _ in 0..<5 { XCTAssertNil(habits.approved("Edit", risk: .medium)) }
    for _ in 0..<5 { XCTAssertNil(habits.approved("Bash(sudo)", risk: .high)) }
  }

  func testPermissionReplyShape() throws {
    let row = try XCTUnwrap(JSONSerialization.jsonObject(with: PermissionReply.deny("No")) as? [String: Any])
    let output = try XCTUnwrap(row["hookSpecificOutput"] as? [String: Any])
    XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
    XCTAssertEqual((output["decision"] as? [String: Any])?["behavior"] as? String, "deny")
  }

  func testHookInstallerKeepsOtherHooks() throws {
    let existing: [String: Any] = [
      "model": "opus",
      "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
    ]
    let installed = ClaudeHookInstaller.install(into: existing, url: "http://127.0.0.1:43822", token: "abc")
    XCTAssertTrue(ClaudeHookInstaller.installed(in: installed))
    XCTAssertEqual(installed["model"] as? String, "opus")
    let stop = try XCTUnwrap((installed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
    XCTAssertEqual(stop.count, 2)
    // Installing twice doesn't duplicate.
    let again = ClaudeHookInstaller.install(into: installed, url: "http://127.0.0.1:43822", token: "abc")
    XCTAssertEqual(((again["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count, 2)
    let removed = ClaudeHookInstaller.remove(from: again)
    XCTAssertFalse(ClaudeHookInstaller.installed(in: removed))
    let hooks = try XCTUnwrap(removed["hooks"] as? [String: Any])
    XCTAssertEqual(hooks.keys.sorted(), ["Stop"])
  }

  func testChangedFiles() {
    let claude = [
      #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/r/a.swift"}},{"type":"tool_use","name":"Read","input":{"file_path":"/r/b.swift"}}]}}"#,
      #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/r/a.swift"}}]}}"#,
    ]
    XCTAssertEqual(AgentChanges.files(lines: claude, tool: "Claude Code"), ["/r/a.swift"])
    let codex = [#"{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Update File: src/x.ts\n@@\n*** Add File: src/y.ts\n"}}"#]
    XCTAssertEqual(AgentChanges.files(lines: codex, tool: "Codex"), ["src/x.ts", "src/y.ts"])
    let stats = AgentChanges.numstat("3\t1\tsrc/x.ts\n-\t-\timg.png\n")
    XCTAssertEqual(stats["src/x.ts"]?.added, 3)
    XCTAssertEqual(stats["img.png"]?.added, 0)
  }

  func testAgentKindMatchesProcess() {
    XCTAssertEqual(AgentKind.matching(process: "/opt/homebrew/bin/codex")?.id, "codex")
    XCTAssertEqual(AgentKind.matching(process: "claude")?.name, "Claude Code")
    XCTAssertNil(AgentKind.matching(process: "/usr/bin/zsh"))
  }
}

final class PlanUsageTests: XCTestCase {
  func testCodexRateLimits() throws {
    let line = #"{"timestamp":"2026-10-09T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1791540000},"secondary":{"used_percent":62.0,"window_minutes":10080,"resets_at":1792000000},"plan_type":"plus"}}}"#
    let now = Date(timeIntervalSince1970: 1_791_530_000)
    let limits = try XCTUnwrap(PlanLimits.codex(lines: ["{}", line], now: now))
    XCTAssertEqual(limits.session?.used, 40)
    XCTAssertEqual(limits.week?.minutes, 10080)
    XCTAssertEqual(limits.plan, "plus")
    XCTAssertEqual(limits.headline, 62)
  }

  func testExpiredWindowResetsToZero() throws {
    let line = #"{"timestamp":"2026-10-09T10:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":99.0,"window_minutes":300,"resets_at":1000}}}}"#
    let limits = try XCTUnwrap(PlanLimits.codex(lines: [line], now: Date(timeIntervalSince1970: 5000)))
    XCTAssertEqual(limits.session?.used, 0)
  }

  func testClaudeUsageWithMicroseconds() throws {
    let json = #"{"five_hour":{"utilization":7.0,"resets_at":"2026-10-09T12:49:59.858680+00:00"},"seven_day":{"utilization":2.0,"resets_at":"2026-10-15T20:59:59.858706+00:00"},"seven_day_opus":null}"#
    let limits = try XCTUnwrap(PlanLimits.claude(Data(json.utf8)))
    XCTAssertEqual(limits.session?.used, 7)
    let expected = ISO8601DateFormatter().date(from: "2026-10-09T12:49:59Z")!.timeIntervalSince1970
    XCTAssertEqual(limits.session?.resets.timeIntervalSince1970 ?? 0, expected, accuracy: 1)
    XCTAssertEqual(limits.week?.used, 2)
  }

  func testForecast() {
    let resets = Date(timeIntervalSince1970: 18000)
    // Two hours in at 50%: hits 100% two hours later, before the reset at five hours.
    let window = LimitWindow(used: 50, minutes: 300, resets: resets)
    XCTAssertEqual(window.forecast(now: Date(timeIntervalSince1970: 7200))?.timeIntervalSince1970 ?? 0, 14400, accuracy: 1)
    // A slow pace stays under.
    XCTAssertNil(LimitWindow(used: 10, minutes: 300, resets: resets).forecast(now: Date(timeIntervalSince1970: 7200)))
    XCTAssertNil(LimitWindow(used: 30, minutes: 300, resets: resets).forecast(now: Date(timeIntervalSince1970: 60)))
  }
}

final class GitHubSummaryTests: XCTestCase {
  func testParseAndStreak() throws {
    let json = """
      {"data":{"viewer":{"login":"molt",
        "contributionsCollection":{"contributionCalendar":{"weeks":[{"contributionDays":[
          {"date":"2026-10-05","contributionCount":0},{"date":"2026-10-06","contributionCount":2},
          {"date":"2026-10-07","contributionCount":1},{"date":"2026-10-08","contributionCount":4},
          {"date":"2026-10-09","contributionCount":0}]}]}},
        "pullRequests":{"nodes":[{"number":7,"title":"Add notch","url":"https://github.com/a/b/pull/7","createdAt":"2026-10-01T00:00:00Z",
          "repository":{"nameWithOwner":"a/b"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}]}},
        "reviews":{"nodes":[{"number":3,"title":"Fix","url":"https://github.com/a/b/pull/3","createdAt":"2026-10-01T00:00:00Z","repository":{"nameWithOwner":"a/b"},"author":{"login":"pal"}},{}]},
        "repository":{"nameWithOwner":"a/b","defaultBranchRef":{"name":"main","target":{"statusCheckRollup":{"state":"SUCCESS"}}}}}}
      """
    let summary = try GitHubSummary.parse(Data(json.utf8), now: ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z")!)
    XCTAssertEqual(summary.login, "molt")
    XCTAssertEqual(summary.streak, 3)
    XCTAssertEqual(summary.total, 7)
    XCTAssertEqual(summary.mine.first?.checks, "FAILURE")
    XCTAssertEqual(summary.reviews.count, 1)
    XCTAssertEqual(summary.waiting(now: summary.fetched).count, 1)
    XCTAssertEqual(summary.ci, .passing)
    XCTAssertEqual(summary.branch, "main")
  }

  func testErrorsSurface() {
    XCTAssertThrowsError(try GitHubSummary.parse(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8)))
  }

  func testRemotes() {
    XCTAssertEqual(GitHubSummary.repository(fromRemote: "git@github.com:vkn889/Molt.git"), "vkn889/Molt")
    XCTAssertEqual(GitHubSummary.repository(fromRemote: "https://github.com/vkn889/Molt\n"), "vkn889/Molt")
    XCTAssertNil(GitHubSummary.repository(fromRemote: "https://gitlab.com/a/b"))
    XCTAssertNil(GitHubSummary.repository(fromRemote: "https://github.com/a/b c"))
  }
}

final class WardrobeTests: XCTestCase {
  func testUnlocks() {
    let progress = WardrobeProgress(inventory: ["none", "scarf", "hat"], friendPoints: 35, agentTasks: 4, bestStreak: 8, month: 10)
    let owned = Set(WardrobeItem.all.filter(progress.owns).map(\.id))
    XCTAssertTrue(owned.isSuperset(of: ["scarf", "hat", "bowtie", "headphones", "shades", "pumpkin"]))
    XCTAssertFalse(owned.contains("beanie"))
    XCTAssertFalse(owned.contains("santa"))
    XCTAssertFalse(owned.contains("glasses"))
    XCTAssertTrue(progress.newlyEarned.contains("pumpkin"))
    XCTAssertFalse(progress.newlyEarned.contains("hat"))
  }

  func testOneItemPerSlot() {
    var look = Appearance()
    look.accessory = "scarf"
    XCTAssertEqual(look.outfit, ["scarf"])
    look.toggle("hat")
    look.toggle("glasses")
    XCTAssertEqual(Set(look.outfit), ["scarf", "hat", "glasses"])
    look.toggle("beanie")
    XCTAssertEqual(Set(look.outfit), ["scarf", "beanie", "glasses"])
    look.toggle("beanie")
    XCTAssertEqual(Set(look.outfit), ["scarf", "glasses"])
    XCTAssertEqual(look.accessory, "glasses")
  }

  func testOldSavesDecode() throws {
    let json = #"{"palette":"ocean","accessory":"hat","eyes":"round","markings":"plain","fins":"leaf","tail":"curl","body":"round"}"#
    let look = try JSONDecoder().decode(Appearance.self, from: Data(json.utf8))
    XCTAssertEqual(look.outfit, ["hat"])
  }
}

final class ChatProviderTests: XCTestCase {
  func testOpenAIStreamLines() throws {
    XCTAssertEqual(try OpenAICompatibleProvider.decode(#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#)?.text, "Hi")
    XCTAssertEqual(try OpenAICompatibleProvider.decode("data: [DONE]")?.done, true)
    XCTAssertNil(try OpenAICompatibleProvider.decode(": keep-alive"))
    XCTAssertThrowsError(try OpenAICompatibleProvider.decode(#"data: {"error":{"message":"bad"}}"#))
  }

  func testAnthropicStreamLines() throws {
    XCTAssertEqual(try AnthropicProvider.decode(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#)?.text, "Hello")
    XCTAssertEqual(try AnthropicProvider.decode(#"data: {"type":"message_stop"}"#)?.done, true)
    XCTAssertNil(try AnthropicProvider.decode("event: ping"))
    XCTAssertThrowsError(try AnthropicProvider.decode(#"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#))
  }

  func testAnthropicBodyMergesTurnsAndLiftsSystem() {
    let body = AnthropicProvider.body(model: "claude-opus-5-5", messages: [
      InferenceMessage(role: "system", content: "Be brief."), InferenceMessage(role: "user", content: "a"),
      InferenceMessage(role: "user", content: "b"), InferenceMessage(role: "assistant", content: "c"),
    ])
    XCTAssertEqual(body["system"] as? String, "Be brief.")
    let turns = body["messages"] as? [[String: Any]] ?? []
    XCTAssertEqual(turns.count, 2)
    XCTAssertEqual(turns.first?["content"] as? String, "a\n\nb")
    XCTAssertEqual(body["fallbacks"] as? String, "default")
    XCTAssertNil(AnthropicProvider.body(model: "claude-haiku-4-5", messages: [])["fallbacks"])
  }

  func testModelListFilters() {
    let data = Data(#"{"data":[{"id":"gpt-5"},{"id":"text-embedding-3"},{"id":"models/gemini-2.5-pro"}]}"#.utf8)
    XCTAssertEqual(OpenAICompatibleProvider.parseModels(data, service: "google").map(\.id), ["gpt-5", "gemini-2.5-pro"])
  }
}

final class CodexNotifyTests: XCTestCase {
  func testInstallChainsExistingNotify() throws {
    let config = "notify = [\"/Apps/Sky Client\", \"turn-ended\"]\nmodel = \"o4\"\n\n[desktop]\nx = 1"
    let result = try CodexNotifyInstaller.install(into: config, script: "/m/codex-notify.sh")
    XCTAssertEqual(result.previous, ["/Apps/Sky Client", "turn-ended"])
    let lines = result.config.components(separatedBy: "\n")
    XCTAssertEqual(lines.first, "notify = [\"/bin/sh\", \"/m/codex-notify.sh\"]")
    XCTAssertEqual(lines.filter(CodexNotifyInstaller.isNotify).count, 1)
    XCTAssertTrue(result.config.contains("[desktop]\nx = 1"))
    // Running again changes nothing.
    let again = try CodexNotifyInstaller.install(into: result.config, script: "/m/codex-notify.sh")
    XCTAssertEqual(again.config, result.config)
  }

  func testEmptyConfigAndMultiline() throws {
    XCTAssertEqual(try CodexNotifyInstaller.install(into: "", script: "/s").config, "notify = [\"/bin/sh\", \"/s\"]\n")
    XCTAssertThrowsError(try CodexNotifyInstaller.install(into: "notify = [\n  \"a\",\n]", script: "/s"))
    XCTAssertFalse(CodexNotifyInstaller.isNotify("notifications = true"))
    XCTAssertEqual(CodexNotifyInstaller.tomlStrings(#"notify = ["a \"q\"", "b"]"#), [#"a "q""#, "b"])
    XCTAssertEqual(CodexNotifyInstaller.shellQuote("it's"), #"'it'\''s'"#)
  }
}

final class QuestionAndDiffTests: XCTestCase {
  let questionInput = Data(#"{"questions":[{"question":"Pick a color","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"Warm"},{"label":"Blue"}]},{"question":"Toppings?","multiSelect":true,"options":[{"label":"A"},{"label":"B"}]}]}"#.utf8)

  func testParsesQuestions() {
    let questions = AgentQuestion.parse(questionInput)
    XCTAssertEqual(questions.count, 2)
    XCTAssertEqual(questions[0].header, "Color")
    XCTAssertEqual(questions[0].options.map(\.label), ["Red", "Blue"])
    XCTAssertEqual(questions[0].options[0].detail, "Warm")
    XCTAssertTrue(questions[1].multiSelect)
    XCTAssertTrue(AgentQuestion.parse(Data("{}".utf8)).isEmpty)
  }

  func testPreToolUseHookBecomesQuestion() throws {
    let json = #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"AskUserQuestion","tool_use_id":"t9","tool_input":{"questions":[{"question":"Q?","options":[{"label":"Yes"}]}]}}"#
    let event = try XCTUnwrap(AgentEvent.claude(Data(json.utf8)))
    XCTAssertEqual(event.kind, .question)
    XCTAssertEqual(event.toolUseID, "t9")
    XCTAssertEqual(event.questions.first?.question, "Q?")
    // Other tools' PreToolUse events are not Molt's business.
    XCTAssertNil(AgentEvent.claude(Data(#"{"hook_event_name":"PreToolUse","tool_name":"Bash"}"#.utf8)))
  }

  func testAnswersEchoQuestions() throws {
    let body = QuestionReply.preToolUse(input: questionInput, choices: ["Pick a color": ["Blue"], "Toppings?": ["A", "B"]])
    let row = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let output = try XCTUnwrap(row["hookSpecificOutput"] as? [String: Any])
    XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
    XCTAssertEqual(output["permissionDecision"] as? String, "allow")
    let input = try XCTUnwrap(output["updatedInput"] as? [String: Any])
    XCTAssertEqual((input["questions"] as? [Any])?.count, 2)
    XCTAssertEqual(input["answers"] as? [String: String], ["Pick a color": "Blue", "Toppings?": "A, B"])
    let permission = try XCTUnwrap(JSONSerialization.jsonObject(with: QuestionReply.permission(input: questionInput, choices: ["Pick a color": ["Red"]])) as? [String: Any])
    let decision = (permission["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    XCTAssertEqual(decision?["behavior"] as? String, "allow")
    XCTAssertNotNil(decision?["updatedInput"])
  }

  func testLineDiff() {
    let diff = LineDiff.diff("a\nb\nc\nd\ne\nf\ng", "a\nb\nc\nD\ne\nf\ng", context: 1)
    XCTAssertEqual(diff, [DiffLine(.same, "c"), DiffLine(.removed, "d"), DiffLine(.added, "D"), DiffLine(.same, "e")])
    XCTAssertEqual(LineDiff.diff("same", "same"), [])
    let far = LineDiff.diff("1\n2\n3\n4\n5\n6\n7\n8\n9", "x\n2\n3\n4\n5\n6\n7\n8\ny", context: 1)
    XCTAssertTrue(far.contains(DiffLine(.gap, "")))
  }

  func testProposedChanges() throws {
    let edit = try XCTUnwrap(ProposedChange.from(tool: "Edit", input: Data(#"{"file_path":"/a.swift","old_string":"let x = 1","new_string":"let x = 2\nlet y = 3","replace_all":true}"#.utf8), current: nil))
    XCTAssertEqual(edit.added, 2)
    XCTAssertEqual(edit.removed, 1)
    XCTAssertFalse(edit.note.isEmpty)
    let created = try XCTUnwrap(ProposedChange.from(tool: "Write", input: Data(#"{"file_path":"/n.txt","content":"one\ntwo\n"}"#.utf8), current: nil))
    XCTAssertTrue(created.created)
    XCTAssertEqual(created.added, 2)
    let replaced = try XCTUnwrap(ProposedChange.from(tool: "Write", input: Data(#"{"file_path":"/n.txt","content":"one\nthree"}"#.utf8), current: "one\ntwo"))
    XCTAssertFalse(replaced.created)
    XCTAssertEqual(replaced.removed, 1)
    let multi = try XCTUnwrap(ProposedChange.from(tool: "MultiEdit", input: Data(#"{"file_path":"/m","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d"}]}"#.utf8), current: nil))
    XCTAssertEqual(multi.added, 2)
    XCTAssertTrue(multi.lines.contains(DiffLine(.gap, "")))
    XCTAssertNil(ProposedChange.from(tool: "Bash", input: Data(#"{"command":"ls"}"#.utf8), current: nil))
  }

  func testInstallerAddsQuestionHookAndUpgrades() throws {
    let installed = ClaudeHookInstaller.install(into: [:], url: "http://127.0.0.1:43822", token: "tok")
    let pre = try XCTUnwrap((installed["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
    XCTAssertEqual(pre.first?["matcher"] as? String, "AskUserQuestion")
    XCTAssertFalse(ClaudeHookInstaller.outdated(in: installed))
    XCTAssertEqual(ClaudeHookInstaller.token(in: installed), "tok")
    // A 0.9.0 install had no PreToolUse hook.
    var old = installed
    var hooks = old["hooks"] as! [String: Any]
    hooks["PreToolUse"] = nil
    old["hooks"] = hooks
    XCTAssertTrue(ClaudeHookInstaller.outdated(in: old))
    XCTAssertFalse(ClaudeHookInstaller.outdated(in: [:]))
    XCTAssertNil(ClaudeHookInstaller.token(in: [:]))
  }
}
