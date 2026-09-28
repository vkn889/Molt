import XCTest

@testable import MoltCore

final class MoltCoreTests: XCTestCase {
  func definition() throws -> PetDefinition {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    return try PetStore.definition(
      at: root.appendingPathComponent("Sources/Molt/Resources/molt.json"))
  }
  var start: Date { Date(timeIntervalSince1970: 1_700_000_000) }
  var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
  }
  func testOfflineDecayAndClamp() throws {
    let d = try definition()
    var state = PetState(definition: d, now: start)
    Simulation.advance(&state, definition: d, to: start.addingTimeInterval(7200), calendar: utc)
    XCTAssertEqual(state.stats["hunger"]!, 79, accuracy: 0.001)
    Simulation.advance(
      &state, definition: d, to: start.addingTimeInterval(86400 * 1000), calendar: utc)
    XCTAssertTrue(state.stats.values.allSatisfy { $0 == 0 })
    XCTAssertLessThanOrEqual(state.careLog.count, 31)
  }
  func testHistoryIndependentOfTickFrequency() throws {
    let d = try definition()
    var coarse = PetState(definition: d, now: start)
    var fine = coarse
    Simulation.advance(
      &coarse, definition: d, to: start.addingTimeInterval(86400 * 3), calendar: utc)
    for hour in 1...72 {
      Simulation.advance(
        &fine, definition: d, to: start.addingTimeInterval(Double(hour) * 3600), calendar: utc)
    }
    XCTAssertEqual(coarse.careLog.count, fine.careLog.count)
    for (a, b) in zip(coarse.careLog, fine.careLog) {
      XCTAssertEqual(a.average, b.average, accuracy: 0.000001)
    }
    XCTAssertEqual(coarse.stats, fine.stats)
  }
  func testClockRollbackDoesNotIncreaseStats() throws {
    let d = try definition()
    var state = PetState(definition: d, now: start)
    Simulation.advance(&state, definition: d, to: start.addingTimeInterval(-3600))
    XCTAssertEqual(state.lastUpdated, start)
    XCTAssertEqual(state.stats["hunger"], 85)
  }
  func testEvolutionUsesHistoryAndCandidateOrder() throws {
    let d = try definition()
    var state = PetState(definition: d, now: start)
    let now = start.addingTimeInterval(8 * 86400)
    state.stageID = "sprout"
    state.stats = state.stats.mapValues { _ in 100 }
    state.careLog = [
      CareLogEntry(
        day: Calendar.current.startOfDay(for: now), weightedHealth: 20 * 3600, seconds: 3600)
    ]
    let brain = RuleBasedBrain()
    XCTAssertEqual(
      brain.decideAction(state: state, definition: d, event: nil, snapshot: nil, now: now),
      .evolve("wild"))
    state.careLog[0].weightedHealth = 90 * 3600
    state.stats = state.stats.mapValues { _ in 0 }
    XCTAssertEqual(
      brain.decideAction(state: state, definition: d, event: nil, snapshot: nil, now: now),
      .evolve("radiant"))
    XCTAssertEqual(
      brain.decideAction(state: state, definition: d, event: "feed", snapshot: nil, now: now),
      .speak(d.personality.dialogue["feed"]![0]))
  }
  func testHealthCooldownMissingReadingsAndRecovery() throws {
    let d = try definition()
    var state = PetState(definition: d, now: start)
    _ = Simulation.applyHealth(SystemHealthSnapshot(), state: &state, definition: d, now: start)
    XCTAssertEqual(state.stats["energy"], 90)
    let low = SystemHealthSnapshot(values: ["batteryLevel": 0.1])
    _ = Simulation.applyHealth(low, state: &state, definition: d, now: start)
    XCTAssertEqual(state.stats["energy"], 82)
    _ = Simulation.applyHealth(low, state: &state, definition: d, now: start.addingTimeInterval(60))
    XCTAssertEqual(state.stats["energy"], 82)
    _ = Simulation.applyHealth(
      low, state: &state, definition: d, now: start.addingTimeInterval(7200))
    XCTAssertEqual(state.stats["energy"], 74)
    _ = Simulation.applyHealth(
      SystemHealthSnapshot(values: ["isCharging": 1]), state: &state, definition: d,
      now: start.addingTimeInterval(7200))
    XCTAssertEqual(state.stats["energy"], 79)
  }
  func testSaveRoundTripBackupAndCorruptionFailsLoudly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PetStore(directory: directory)
    let d = try definition()
    var state = PetState(definition: d, now: start)
    try store.save(state)
    state.stats["energy"] = 20
    try store.save(state)
    XCTAssertEqual(try store.load()?.stats["energy"], 20)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("pet-state.backup.json").path))
    try Data("broken".utf8).write(to: store.stateURL)
    XCTAssertThrowsError(try store.load())
  }
  func testDefinitionRejectsCycleAndUnknownStats() throws {
    var d = try definition()
    d.evolutionTree[1].nextStages = ["seed"]
    XCTAssertThrowsError(try d.validate())
    d = try definition()
    d.interactions[0].effects = ["unknown": 3]
    XCTAssertThrowsError(try d.validate())
  }
  func testFeedDoesNotRewriteHistory() throws {
    let d = try definition()
    var state = PetState(definition: d, now: start)
    Simulation.advance(&state, definition: d, to: start.addingTimeInterval(86400))
    let score = state.careScore(at: state.lastUpdated)
    Simulation.interact(&state, interaction: d.interactions[0])
    XCTAssertEqual(score, state.careScore(at: state.lastUpdated))
  }
  func testBundledDefinitionsValidate() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    for name in ["molt", "fern", "orbit"] {
      XCTAssertNoThrow(
        try PetStore.definition(
          at: root.appendingPathComponent("Sources/Molt/Resources/\(name).json")))
    }
  }
}
