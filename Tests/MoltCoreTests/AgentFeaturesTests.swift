import XCTest
@testable import MoltCore

final class AgentFeaturesTests: XCTestCase {
  func testPlanIsValidatedAsAWhole() throws {
    let plan = try AgentPlan.parse("""
      [{"tool":"createTask","text":"Prepare outline"},{"tool":"startFocus","text":"Draft","minutes":25}]
      """)
    XCTAssertEqual(plan.count, 2)
    XCTAssertNotEqual(plan[0].id, plan[1].id)
    XCTAssertThrowsError(try AgentPlan.parse("[]"))
    XCTAssertThrowsError(try AgentPlan.parse("[{\"tool\":\"openWorkspace\",\"text\":\"/tmp\"}]"))
    XCTAssertThrowsError(try AgentPlan.parse("[{\"tool\":\"startFocus\",\"text\":\"Focus\",\"minutes\":999}]"))
    let tooMany = "[" + Array(repeating: "{\"tool\":\"createTask\",\"text\":\"Step\"}", count: 7).joined(separator: ",") + "]"
    XCTAssertThrowsError(try AgentPlan.parse(tooMany))
  }
  func testLegacyWorkspaceAndMemoryRoundTrip() throws {
    let legacy = try JSONDecoder().decode(AssistantWorkspace.self, from: Data("{\"projects\":[],\"jobs\":[]}".utf8))
    XCTAssertNil(legacy.memories)
    var workspace = legacy
    var memory = ApprovedMemory("Prefer concise answers")
    memory.enabled = false
    workspace.memories = [memory]
    let restored = try JSONDecoder().decode(AssistantWorkspace.self, from: JSONEncoder().encode(workspace))
    XCTAssertEqual(restored.memories?.first?.text, memory.text)
    XCTAssertEqual(restored.memories?.first?.enabled, false)
  }
}
