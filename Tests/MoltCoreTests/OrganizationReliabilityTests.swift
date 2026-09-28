import XCTest
import SQLite3
@testable import MoltCore

final class OrganizationReliabilityTests: XCTestCase {
  func testRepeatingCompletionDoesNotDuplicateNextTask() throws {
    var organization = Organization()
    var task = WorkTask("Water plants")
    task.due = Date(timeIntervalSince1970: 1_750_000_000)
    task.recurrence = "daily"
    task.checklist = [ChecklistItem("Kitchen")]
    organization.tasks = [task]
    organization.completeTask(task.id, now: task.due!)
    organization.tasks[1].title = "Keep my edits"
    organization = try JSONDecoder().decode(Organization.self, from: JSONEncoder().encode(organization))
    organization.completeTask(task.id, now: task.due!)
    organization.completeTask(task.id, now: task.due!)
    XCTAssertEqual(organization.tasks.count, 2)
    XCTAssertEqual(organization.tasks[1].title, "Keep my edits")
    XCTAssertEqual(organization.tasks[1].recurrenceParentID, task.id)
    XCTAssertNotEqual(organization.tasks[1].checklist[0].id, task.checklist[0].id)
    let following = organization.tasks[1]
    organization.completeTask(following.id, now: following.due!)
    XCTAssertEqual(organization.tasks.count, 3)
    XCTAssertEqual(organization.tasks[2].recurrenceParentID, following.id)
  }

  func testLegacyTaskWithoutParentStillDecodes() throws {
    let encoded = try JSONEncoder().encode(WorkTask("Legacy"))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "recurrenceParentID")
    let task = try JSONDecoder().decode(WorkTask.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(task.recurrenceParentID)
  }
  func testFutureDatabaseVersionIsPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("organization.sqlite")
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
    XCTAssertThrowsError(try OrganizationStore(url: url))
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    XCTAssertEqual(sqlite3_column_int(statement, 0), 99)
  }
}
