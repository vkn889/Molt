import CoreGraphics
import XCTest

@testable import MoltCore

final class InferenceTests: XCTestCase {
  func testIslandStaysBelowNotchOnOffsetDisplay() {
    let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
    let visible = CGRect(x: -1512, y: 225, width: 1512, height: 925)
    for expanded in [true, false] {
      let frame = IslandGeometry.frame(
        screen: screen, visible: visible, safeTop: 32, expanded: expanded)
      XCTAssertTrue(visible.contains(frame))
      XCTAssertLessThanOrEqual(frame.maxY, screen.maxY - 32)
    }
    let small = CGRect(x: 100, y: 100, width: 600, height: 500)
    XCTAssertTrue(
      small.contains(
        IslandGeometry.frame(screen: small, visible: small, safeTop: 0, expanded: true)))
  }
  func testRejectsRemoteAndEmbeddingModels() throws {
    XCTAssertThrowsError(
      try OllamaProvider.validateMetadata(
        Data("{\"remote_host\":\"https://example.org\",\"capabilities\":[\"completion\"]}".utf8),
        name: "innocent-name"))
    XCTAssertThrowsError(
      try OllamaProvider.validateMetadata(
        Data("{\"capabilities\":[\"embedding\"]}".utf8), name: "embed"))
    XCTAssertNoThrow(
      try OllamaProvider.validateMetadata(
        Data("{\"capabilities\":[\"completion\"]}".utf8), name: "local"))
  }
  func testStreamErrorsAndCompletion() throws {
    XCTAssertThrowsError(try OllamaProvider.decodeChunk(Data("{\"error\":\"model missing\"}".utf8)))
    XCTAssertThrowsError(try OllamaProvider.decodeChunk(Data("{}".utf8)))
    let chunk = try OllamaProvider.decodeChunk(
      Data("{\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"done\":true}".utf8))
    XCTAssertEqual(chunk.text, "Hello")
    XCTAssertTrue(chunk.done)
  }
  func testToolsRejectInvalidScopeAndArguments() throws {
    XCTAssertThrowsError(try ToolProposal(tool: .startFocus, text: "Work", minutes: 999).validate())
    XCTAssertThrowsError(try ToolProposal.parse("{\"tool\":\"shell\",\"text\":\"rm -rf /\"}"))
    XCTAssertFalse(
      ApprovedFiles.contains(
        URL(fileURLWithPath: "/tmp/project-other/file"), in: URL(fileURLWithPath: "/tmp/project")))
    XCTAssertFalse(
      ApprovedFiles.contains(
        URL(fileURLWithPath: "/tmp/project/../secret"), in: URL(fileURLWithPath: "/tmp/project")))
  }
  func testInterruptedJobsNeverReplay() {
    var workspace = AssistantWorkspace()
    var job = AssistantJob(ToolProposal(tool: .createTask, text: "Review"))
    job.status = "running"
    workspace.jobs = [job]
    workspace.reconcile()
    XCTAssertEqual(workspace.jobs[0].status, "failed")
  }
  func testManagedWorkerWhenExplicitlyEnabled() async throws {
    guard let runtime = ProcessInfo.processInfo.environment["MOLT_TEST_RUNTIME"],
      let model = ProcessInfo.processInfo.environment["MOLT_TEST_MODEL"]
    else { throw XCTSkip("Opt-in managed worker integration") }
    let provider = ManagedLocalProvider(
      executable: URL(fileURLWithPath: runtime), modelURL: URL(fileURLWithPath: model))
    var result = ""
    for try await token in provider.stream(
      model: ManagedModel.id,
      messages: [.init(role: "user", content: "Say hello in one short sentence.")])
    { result += token }
    XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }
  func testRejectsCorruptManagedWeights() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("invalid".utf8).write(to: file)
    XCTAssertThrowsError(try ManagedModel.verify(file))
  }
  func testOllamaIntegrationWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["MOLT_TEST_OLLAMA"] == "1" else {
      throw XCTSkip("Opt-in local Ollama integration")
    }
    let provider = OllamaProvider()
    let models = try await provider.models()
    let model = try XCTUnwrap(models.first)
    var reply = ""
    for try await token in provider.stream(
      model: model.id, messages: [.init(role: "user", content: "Say hello in one short sentence.")])
    { reply += token }
    XCTAssertFalse(reply.isEmpty)
    try await provider.unload(model: model.id)
  }
}
