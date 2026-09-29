import XCTest

@testable import MoltCore

final class ProjectSearchTests: XCTestCase {
  func testContentsRequireOptInAndProvideSourceExcerpt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("notes.md")
    try Data("A plan for the copper garden and a little rest.".utf8).write(to: file)
    XCTAssertTrue(ApprovedFiles.search("copper", folder: root).isEmpty)
    let hits = ApprovedFiles.searchHits("copper", folder: root, includeContents: true)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits[0].url.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
    XCTAssertTrue(hits[0].excerpt?.contains("copper garden") == true)
  }
  func testSearchSkipsHiddenDependenciesLargeFilesAndSymlinkEscapes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in [".secret.txt", "node_modules/private.txt"] {
      try Data("needle".utf8).write(to: root.appendingPathComponent(name))
    }
    try Data(("needle" + String(repeating: "x", count: 65_000)).utf8).write(
      to: root.appendingPathComponent("large.txt"))
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".txt")
    defer { try? FileManager.default.removeItem(at: outside) }
    try Data("needle".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("link.txt"), withDestinationURL: outside)
    XCTAssertTrue(ApprovedFiles.searchHits("needle", folder: root, includeContents: true).isEmpty)
  }
  func testSearchResultLimit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<60 { try Data().write(to: root.appendingPathComponent("match-\(index).txt")) }
    XCTAssertEqual(ApprovedFiles.search("match", folder: root).count, 40)
  }
}
