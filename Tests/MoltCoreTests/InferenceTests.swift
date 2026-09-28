import XCTest
@testable import MoltCore
final class InferenceTests: XCTestCase {
  func testRejectsRemoteAndEmbeddingModels() throws {
    XCTAssertThrowsError(try OllamaProvider.validateMetadata(Data("{\"remote_host\":\"https://example.org\",\"capabilities\":[\"completion\"]}".utf8), name: "innocent-name"))
    XCTAssertThrowsError(try OllamaProvider.validateMetadata(Data("{\"capabilities\":[\"embedding\"]}".utf8), name: "embed"))
    XCTAssertNoThrow(try OllamaProvider.validateMetadata(Data("{\"capabilities\":[\"completion\"]}".utf8), name: "local"))
  }
  func testStreamErrorsAndCompletion() throws {
    XCTAssertThrowsError(try OllamaProvider.decodeChunk(Data("{\"error\":\"model missing\"}".utf8)))
    XCTAssertThrowsError(try OllamaProvider.decodeChunk(Data("{}".utf8)))
    let chunk = try OllamaProvider.decodeChunk(Data("{\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"done\":true}".utf8))
    XCTAssertEqual(chunk.text, "Hello"); XCTAssertTrue(chunk.done)
  }
  func testToolsRejectInvalidScopeAndArguments() throws {
    XCTAssertThrowsError(try ToolProposal(tool: .startFocus, text: "Work", minutes: 999).validate())
    XCTAssertThrowsError(try ToolProposal.parse("{\"tool\":\"shell\",\"text\":\"rm -rf /\"}"))
    XCTAssertFalse(ApprovedFiles.contains(URL(fileURLWithPath: "/tmp/project-other/file"), in: URL(fileURLWithPath: "/tmp/project")))
    XCTAssertFalse(ApprovedFiles.contains(URL(fileURLWithPath: "/tmp/project/../secret"), in: URL(fileURLWithPath: "/tmp/project")))
  }
  func testInterruptedJobsNeverReplay() {
    var workspace = AssistantWorkspace()
    var job = AssistantJob(ToolProposal(tool: .createTask, text: "Review"))
    job.status = "running"; workspace.jobs = [job]; workspace.reconcile()
    XCTAssertEqual(workspace.jobs[0].status, "failed")
  }
  func testOllamaIntegrationWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["MOLT_TEST_OLLAMA"] == "1" else { throw XCTSkip("Opt-in local Ollama integration") }
    let provider = OllamaProvider()
    let models = try await provider.models()
    let model = try XCTUnwrap(models.first)
    var reply = ""
    for try await token in provider.stream(model: model.id, messages: [.init(role: "user", content: "Say hello in one short sentence.")]) { reply += token }
    XCTAssertFalse(reply.isEmpty)
    try await provider.unload(model: model.id)
  }
}
