import XCTest

@testable import MoltCore

final class WebReaderTests: XCTestCase {
  func testRejectsPrivateAndCredentialURLs() {
    for value in [
      "http://example.com", "https://127.0.0.1", "https://192.168.1.2", "https://169.254.169.254",
      "https://100.64.1.2", "https://[::1]", "https://user:pass@example.com",
      "https://example.com:8888", "file:///etc/passwd", "https://thing.local",
    ] {
      XCTAssertThrowsError(try WebAccessPolicy.validate(URL(string: value)!), value)
    }
    XCTAssertNoThrow(try WebAccessPolicy.validate(URL(string: "https://example.com/article")!))
  }
  func testRobotsRulesAndSpecificAllow() {
    let rules = "User-agent: *\nDisallow: /private\nAllow: /private/public\nDisallow: /*?secret=*\n"
    XCTAssertFalse(WebText.robotsAllows(rules, path: "/private/page"))
    XCTAssertTrue(WebText.robotsAllows(rules, path: "/private/public/page"))
    XCTAssertFalse(WebText.robotsAllows(rules, path: "/article?secret=yes"))
    XCTAssertTrue(WebText.robotsAllows(rules, path: "/article"))
    XCTAssertFalse(WebText.robotsAllows("User-agent: MoltReader\nDisallow: /", path: "/"))
  }
  func testExtractsTextWithoutScriptsAndBoundsOutput() {
    let html =
      "<html><style>secret CSS</style><script>run_bad_command()</script><body><h1>Hello &amp; welcome</h1><p>A useful source.</p></body></html>"
    let text = WebText.extract(html)
    XCTAssertTrue(text.contains("Hello & welcome"))
    XCTAssertFalse(text.contains("run_bad_command"))
    XCTAssertFalse(text.contains("secret CSS"))
    XCTAssertEqual(WebText.extract(String(repeating: "x", count: 20000)).count, 12000)
  }
  func testImagesRequireVisionCapability() throws {
    let text = Data("{\"capabilities\":[\"completion\"]}".utf8)
    XCTAssertThrowsError(
      try OllamaProvider.validateMetadata(text, name: "local", needsVision: true))
    let vision = Data("{\"capabilities\":[\"completion\",\"vision\"]}".utf8)
    XCTAssertNoThrow(try OllamaProvider.validateMetadata(vision, name: "local", needsVision: true))
    let message = InferenceMessage(role: "user", content: "Look", images: ["test-image"])
    XCTAssertEqual(
      try JSONDecoder().decode(InferenceMessage.self, from: JSONEncoder().encode(message)), message)
  }
  func testPublicReaderWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["MOLT_TEST_WEB"] == "1" else {
      throw XCTSkip("Opt-in live webpage read")
    }
    let result = try await WebReader().read(URL(string: "https://example.com")!)
    XCTAssertTrue(result.text.contains("Example Domain"))
  }
}
