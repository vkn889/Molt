import XCTest
@testable import MoltCore
final class FileMovesTests: XCTestCase {
  func fixture() throws -> (URL, URL, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("example.txt")
    try Data("original".utf8).write(to: source)
    return (root.resolvingSymlinksInPath(), source.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
  }
  func testReviewedMovePersistsAndUndoes() throws {
    let (root, source, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    var plan = try FileMovePlan.preview(files: [source], folder: folder)
    var states: [String] = []
    try plan.execute { states.append($0.moves[0].state) }
    XCTAssertEqual(states, ["running", "completed"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertThrowsError(try plan.execute { _ in })
    try plan.undo { _ in }
    XCTAssertEqual(try String(contentsOf: source), "original")
    XCTAssertEqual(plan.moves[0].state, "undone")
  }
  func testStalePreviewCollisionAndEditedUndoAreRejected() throws {
    let (root, source, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    var plan = try FileMovePlan.preview(files: [source], folder: folder)
    try Data("changed".utf8).write(to: source)
    XCTAssertThrowsError(try plan.execute { _ in })
    plan = try FileMovePlan.preview(files: [source], folder: folder)
    try plan.execute { _ in }
    let destination = folder.appendingPathComponent(source.lastPathComponent)
    try Data("later edit".utf8).write(to: destination)
    XCTAssertThrowsError(try plan.undo { _ in })
    XCTAssertEqual(try String(contentsOf: destination), "later edit")
    try Data("another".utf8).write(to: source)
    XCTAssertThrowsError(try FileMovePlan.preview(files: [source], folder: folder))
  }
  func testJournalFailurePreventsMutation() throws {
    let (root, source, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    var plan = try FileMovePlan.preview(files: [source], folder: folder)
    XCTAssertThrowsError(try plan.execute { _ in throw MoltError.invalid("Disk full") })
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testSymlinkEscapeRejected() throws {
    let (root, source, folder) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let link = root.appendingPathComponent("linked.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    XCTAssertThrowsError(try FileMovePlan.preview(files: [link], folder: folder))
  }
}
