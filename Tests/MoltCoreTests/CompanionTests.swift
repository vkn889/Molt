import XCTest

@testable import MoltCore

final class CompanionTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_750_000_000)
  func fixture() throws -> (PetDefinition, PetState) {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let definition = try PetStore.definition(
      at: root.appendingPathComponent("Sources/Molt/Resources/molt.json"))
    var state = PetState(definition: definition, now: start)
    state.companion = CompanionState(now: start)
    return (definition, state)
  }
  func testCooldownSurvivesRoundTripAndUsesGroup() throws {
    let (d, initial) = try fixture()
    var s = initial
    let feed = d.interactions.first { $0.id == "feed" }!
    s.stats["hunger"] = 40
    XCTAssertTrue(ActivityEngine.perform(feed, state: &s, now: start))
    var restored = try JSONDecoder().decode(PetState.self, from: JSONEncoder().encode(s))
    var renamed = feed
    renamed.id = "renamed"
    renamed.name = "Different label"
    XCTAssertFalse(
      ActivityEngine.perform(renamed, state: &restored, now: start.addingTimeInterval(60)))
    XCTAssertNotNil(
      ActivityEngine.reason(feed, state: restored, at: start.addingTimeInterval(1799)))
    XCTAssertNil(ActivityEngine.reason(feed, state: restored, at: start.addingTimeInterval(1800)))
  }
  func testBasicCareBypassesCooldownAndExclusiveActivity() throws {
    let (d, initial) = try fixture()
    var s = initial
    s.stats["hunger"] = 0
    s.companion?.cooldowns["meal"] = start.addingTimeInterval(3600)
    XCTAssertNil(
      ActivityEngine.start(
        kind: "explore:garden", title: "Garden", seconds: 300, group: "explore", cooldown: 7200,
        energy: 5, state: &s, now: start))
    XCTAssertTrue(
      ActivityEngine.perform(d.interactions.first { $0.id == "basic-care" }!, state: &s, now: start)
    )
    XCTAssertEqual(s.stats["hunger"], 25)
    XCTAssertEqual(s.companion?.experience, 0)
  }
  func testCompletionExactlyOnceAndCancellation() throws {
    let (_, initial) = try fixture()
    var s = initial
    XCTAssertNil(
      ActivityEngine.start(
        kind: "explore:garden", title: "Garden", seconds: 300, group: "explore", cooldown: 7200,
        energy: 5, state: &s, now: start))
    let id = s.companion!.active!.id
    XCTAssertNotNil(
      ActivityEngine.start(
        kind: "creative", title: "Drawing", seconds: 120, group: "creative", cooldown: 100,
        energy: 2, state: &s, now: start))
    XCTAssertTrue(ActivityEngine.finish(id: id, state: &s, now: start.addingTimeInterval(300)))
    let xp = s.companion!.experience
    XCTAssertFalse(ActivityEngine.finish(id: id, state: &s, now: start.addingTimeInterval(400)))
    XCTAssertEqual(s.companion!.experience, xp)
    XCTAssertNil(
      ActivityEngine.start(
        kind: "creative", title: "Drawing", seconds: 120, group: "creative", cooldown: 100,
        energy: 2, state: &s, now: start.addingTimeInterval(301)))
    XCTAssertTrue(
      ActivityEngine.finish(
        id: s.companion!.active!.id, state: &s, now: start.addingTimeInterval(302), success: false))
    XCTAssertEqual(s.companion!.experience, xp)
  }
  func testRewardCapAndRestCannotInstantlyRefill() throws {
    let (d, initial) = try fixture()
    var s = initial
    s.stats["energy"] = 0
    XCTAssertTrue(
      ActivityEngine.perform(d.interactions.first { $0.id == "rest" }!, state: &s, now: start))
    ActivityEngine.reconcile(state: &s, now: start)
    XCTAssertEqual(s.stats["energy"], 0)
    ActivityEngine.reconcile(state: &s, now: start.addingTimeInterval(120))
    XCTAssertEqual(s.stats["energy"], 1)
    var c = s.companion!
    for _ in 0..<100 { ActivityEngine.reward(&c, amount: 10, id: UUID(), now: start) }
    XCTAssertEqual(c.experience, 60)
  }
  func testConservativeMonotonicClockRollback() {
    let clock = CompanionClock(wall: start, uptime: 100)
    XCTAssertEqual(
      clock.now(wall: start.addingTimeInterval(-3600), uptime: 130, floor: start),
      start.addingTimeInterval(30))
    let restarted = CompanionClock(wall: start.addingTimeInterval(-5000), uptime: 1)
    XCTAssertGreaterThanOrEqual(
      restarted.now(wall: start.addingTimeInterval(-5000), uptime: 2, floor: start), start)
  }
  func testVacationDoesNotCreateCareEvidence() throws {
    let (d, initial) = try fixture()
    var s = initial
    s.companion?.preferences.vacation = true
    Simulation.advance(&s, definition: d, to: start.addingTimeInterval(86400 * 20))
    XCTAssertEqual(s.stats, initial.stats)
    XCTAssertEqual(s.companion?.pausedSeconds, 86400 * 20)
    XCTAssertTrue(s.careLog.isEmpty)
  }
  func testLegacyMigrationPreservesOriginalAndIdentity() throws {
    let (_, state) = try fixture()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var old = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoder.encode(state)) as? [String: Any])
    old.removeValue(forKey: "schemaVersion")
    old.removeValue(forKey: "companion")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try JSONSerialization.data(withJSONObject: old)
    try data.write(to: directory.appendingPathComponent("pet-state.json"))
    let migrated = try XCTUnwrap(PetStore(directory: directory).load())
    XCTAssertEqual(migrated.id, state.id)
    XCTAssertEqual(migrated.stats, state.stats)
    XCTAssertEqual(migrated.schemaVersion, 2)
    XCTAssertEqual(
      try Data(contentsOf: directory.appendingPathComponent("pet-state.before-v2.json")), data)
    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("pet-state.json")), data)
  }
  func testGameCompletionWithoutPrecisionOrAudio() {
    var memory = MemoryGame(pairs: 4, seed: 42)
    for value in Set(memory.cards) {
      for index in memory.cards.indices where memory.cards[index] == value { memory.choose(index) }
    }
    XCTAssertTrue(memory.complete)
    var rhythm = RhythmGame(seed: 9)
    for direction in rhythm.sequence { rhythm.choose(direction) }
    XCTAssertTrue(rhythm.complete)
    var fetch = FetchGame()
    for _ in 0..<4 { fetch.move(1) }
    for _ in 0..<4 { fetch.move(2) }
    XCTAssertTrue(fetch.complete)
  }
  func testOrganizationRoundTripAndDSTRecurrence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try OrganizationStore(url: directory.appendingPathComponent("organization.sqlite"))
    var o = Organization()
    o.tasks = [WorkTask("Read")]
    o.notes = [Note("Private note", body: "Local only")]
    try store.save(o)
    let restored = try store.load()
    XCTAssertEqual(restored.tasks.first?.title, "Read")
    XCTAssertEqual(restored.notes.first?.body, "Local only")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!
    let next = try XCTUnwrap(
      Recurrence.next(after: before, rule: "daily", zone: calendar.timeZone.identifier))
    XCTAssertEqual(calendar.component(.hour, from: next), 9)
    XCTAssertEqual(next.timeIntervalSince(before), 23 * 3600)
  }
  func testFocusPauseExcludesGapAndUndoTask() {
    var focus = FocusSession(now: start, minutes: 25)
    focus.pause(at: start.addingTimeInterval(60))
    XCTAssertEqual(focus.duration(at: start.addingTimeInterval(3600)), 60)
    focus.lastResumed = start.addingTimeInterval(3600)
    focus.stop(at: start.addingTimeInterval(3660))
    XCTAssertEqual(focus.elapsed, 120)
    var o = Organization()
    o.tasks = [WorkTask("Test")]
    let id = o.tasks[0].id
    o.completeTask(id, now: start)
    XCTAssertNotNil(o.tasks[0].completed)
    o.completeTask(id, now: start)
    XCTAssertNil(o.tasks[0].completed)
    XCTAssertEqual(o.tasks[0].history.count, 2)
  }
}

extension CompanionTests {
  func testExcludedAppsNeverQualifyForPersistence() {
    var preferences = ConsentPreferences()
    XCTAssertFalse(ActivityPolicy.permits(app: "browser", preferences: preferences))
    preferences.tracking = true
    preferences.excludedApps = "browser, private.editor"
    XCTAssertFalse(ActivityPolicy.permits(app: "browser", preferences: preferences))
    XCTAssertTrue(ActivityPolicy.permits(app: "work.editor", preferences: preferences))
    preferences.paused = true
    XCTAssertFalse(ActivityPolicy.permits(app: "work.editor", preferences: preferences))
    let records = [
      ActivityInterval(
        app: "browser", name: "Browser", start: start, end: start.addingTimeInterval(60),
        category: "work"),
      ActivityInterval(
        app: "work.editor", name: "Editor", start: start.addingTimeInterval(-10 * 86400),
        end: start.addingTimeInterval(-9 * 86400), category: "work"),
    ]
    XCTAssertTrue(
      ActivityPolicy.retained(records, preferences: preferences, now: start.addingTimeInterval(100))
        .isEmpty)
  }
  func testMalformedPackAndUnsafeAssetsRejected() throws {
    var (d, _) = try fixture()
    d.spriteAtlas = "../outside.png"
    XCTAssertThrowsError(try d.validate())
    d.spriteAtlas = "https://example.com/a.png"
    XCTAssertThrowsError(try d.validate())
    d.spriteAtlas = nil
    d.schemaVersion = 99
    XCTAssertThrowsError(try d.validate())
    XCTAssertThrowsError(try SpeciesPack.validateAtlas(Data("not a png".utf8)))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let (valid, _) = try fixture()
    try JSONEncoder().encode(valid).write(to: folder.appendingPathComponent("definition.json"))
    let pack = try SpeciesPack.load(at: folder)
    XCTAssertEqual(pack.definition.id, valid.id)
    try FileManager.default.createSymbolicLink(
      at: folder.appendingPathComponent("link.json"),
      withDestinationURL: folder.appendingPathComponent("definition.json"))
    XCTAssertThrowsError(try SpeciesPack.load(at: folder.appendingPathComponent("link.json")))
  }
  func testTimedActivityCannotCompleteEarly() throws {
    let (_, initial) = try fixture()
    var s = initial
    XCTAssertNil(
      ActivityEngine.start(
        kind: "creative", title: "Garden", seconds: 120, group: "creative", cooldown: 1800,
        energy: 1, state: &s, now: start))
    XCTAssertFalse(
      ActivityEngine.finish(
        id: s.companion!.active!.id, state: &s, now: start.addingTimeInterval(1)))
    ActivityEngine.reconcile(state: &s, now: start.addingTimeInterval(3600))
    XCTAssertNil(s.companion?.active)
    XCTAssertEqual(s.companion?.cooldowns["creative"], start.addingTimeInterval(1920))
  }
  func testTraitAndTrainingEvolutionRequirements() throws {
    var (d, s) = try fixture()
    s.stageID = "sprout"
    d.evolutionTree[1].nextStages = ["radiant", "wild"]
    d.evolutionTree[2].minCareScore = nil
    d.evolutionTree[2].minTraits = ["curiosity": 0.8]
    d.evolutionTree[2].requiredSkills = ["sit": 100]
    let brain = RuleBasedBrain()
    let now = start.addingTimeInterval(10 * 86400)
    XCTAssertEqual(
      brain.decideAction(state: s, definition: d, event: nil, snapshot: nil, now: now),
      .evolve("wild"))
    s.companion?.traits["curiosity"] = 0.9
    s.companion?.skills["sit"] = 100
    XCTAssertEqual(
      brain.decideAction(state: s, definition: d, event: nil, snapshot: nil, now: now),
      .evolve("radiant"))
  }
  func testInvalidPreferencesFailValidationAndPortableExportRoundTrip() throws {
    let (d, original) = try fixture()
    var s = original
    s.companion?.preferences.size = -100
    XCTAssertThrowsError(try PetStore.validate(s, definition: d))
    let archive = PetArchive(state: original, atlas: nil)
    let restored = try JSONDecoder().decode(PetArchive.self, from: JSONEncoder().encode(archive))
    XCTAssertEqual(restored.state.id, original.id)
    XCTAssertEqual(restored.state.definitionSnapshot?.id, d.id)
  }
  func testEightHoursOfMinuteTicksRemainBounded() throws {
    let (d, initial) = try fixture()
    var s = initial
    for minute in 1...480 {
      let now = start.addingTimeInterval(Double(minute) * 60)
      Simulation.advance(&s, definition: d, to: now)
      ActivityEngine.reconcile(state: &s, now: now)
    }
    XCTAssertLessThanOrEqual(s.careLog.count, 2)
    XCTAssertTrue(s.stats.values.allSatisfy { (0...100).contains($0) })
    XCTAssertLessThan(try JSONEncoder().encode(s).count, 20_000)
  }
}
