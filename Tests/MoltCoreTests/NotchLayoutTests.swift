import XCTest
@testable import MoltCore

final class NotchLayoutTests: XCTestCase {
  func testTabsKeepYourOrderAndHome() {
    XCTAssertEqual(NotchLayout.tabs(order: [], hidden: []), ["Notch", "Hub", "Play", "Molting"])
    XCTAssertEqual(NotchLayout.tabs(order: ["Play", "Gone", "Notch", "Play"], hidden: ["Molting", "Notch"]), ["Play", "Notch", "Hub"])
    XCTAssertEqual(NotchLayout.allTabs(order: ["Molting"]), ["Molting", "Notch", "Hub", "Play"])
  }
  func testPriorityFillsInAndFilters() {
    XCTAssertEqual(NotchLayout.priority(["music", "nope", "music", "focus"]), [.music, .focus, .agents, .recording, .battery])
    XCTAssertEqual(NotchLayout.live([.music, .agents], priority: NotchLayout.priority([])), [.agents, .music])
    XCTAssertEqual(NotchLayout.move(LiveKind.music, before: .agents, in: LiveKind.allCases), [.music, .agents, .recording, .focus, .battery])
    XCTAssertEqual(NotchLayout.move("a", before: nil, in: ["a", "b"]), ["b", "a"])
  }
}

final class JumpSearchTests: XCTestCase {
  let items = [
    JumpItem(id: "hub", title: "Hub", subtitle: "Page"),
    JumpItem(id: "focus", title: "Start a focus session", subtitle: "Focus", keywords: ["timer", "pomodoro"]),
    JumpItem(id: "focusWidget", title: "Focus widget", subtitle: "Hub"),
    JumpItem(id: "pause", title: "Pause app tracking", subtitle: "Action"),
    JumpItem(id: "settings", title: "Settings", subtitle: "Page"),
  ]
  func testRanksTitleStartsFirst() {
    XCTAssertEqual(JumpSearch.rank("foc", items).map(\.id), ["focusWidget", "focus"])
    XCTAssertEqual(JumpSearch.rank("timer", items).map(\.id), ["focus"])
    XCTAssertEqual(JumpSearch.rank("focus 50", items).map(\.id), ["focusWidget", "focus"])
    XCTAssertEqual(JumpSearch.rank("stg", items).map(\.id), ["settings", "pause"])
    XCTAssertTrue(JumpSearch.rank("   ", items).isEmpty)
    XCTAssertTrue(JumpSearch.rank("zzz", items).isEmpty)
  }
  func testMinutesAndHighlight() {
    XCTAssertEqual(JumpSearch.minutes(in: "focus 50"), 50)
    XCTAssertEqual(JumpSearch.minutes(in: "timer 10m"), 10)
    XCTAssertEqual(JumpSearch.minutes(in: "focus 999"), 180)
    XCTAssertNil(JumpSearch.minutes(in: "focus"))
    let title = "Start a focus session"
    XCTAssertEqual(JumpSearch.highlight("FOC", in: title).map { String(title[$0]) }, "foc")
  }
}

final class FocusMathTests: XCTestCase {
  func testRulerSnapsToFiveMinutes() {
    XCTAssertEqual(FocusMath.minutes(at: 0), 5)
    XCTAssertEqual(FocusMath.minutes(at: 1), 60)
    XCTAssertEqual(FocusMath.minutes(at: 0.42), 25)
    XCTAssertEqual(FocusMath.fraction(for: 30), 0.5)
    XCTAssertEqual(FocusMath.minutes(at: -3), 5)
    XCTAssertEqual(FocusMath.minutes(at: .nan), 5)
    XCTAssertEqual(FocusMath.minutes(at: FocusMath.fraction(for: 50)), 50)
  }
  func testRewardAndToday() {
    XCTAssertEqual(FocusMath.reward(seconds: 1500), 5)
    XCTAssertEqual(FocusMath.reward(seconds: 99_999), 20)
    let now = Date()
    var done = FocusSession(now: now.addingTimeInterval(-1800), minutes: 25)
    done.elapsed = 1500
    done.finished = now.addingTimeInterval(-300)
    var old = FocusSession(now: now.addingTimeInterval(-3 * 86400), minutes: 25)
    old.elapsed = 1500
    old.finished = now.addingTimeInterval(-3 * 86400)
    let open = FocusSession(now: now, minutes: 25)
    let today = FocusMath.today([done, old, open], now: now)
    XCTAssertEqual(today.count, 1)
    XCTAssertEqual(today.minutes, 25)
  }
}

final class TrayTests: XCTestCase {
  func testAddingMovesDuplicatesToTheFront() {
    let a = TrayItem(kind: .file, value: "/tmp/a.pdf"), b = TrayItem(kind: .link, value: "https://example.com/x")
    var tray = Tray.adding([a, b], to: [])
    XCTAssertEqual(tray.map(\.value), [a.value, b.value])
    tray = Tray.adding([TrayItem(kind: .link, value: b.value)], to: tray)
    XCTAssertEqual(tray.map(\.value), [b.value, a.value])
    tray = Tray.adding((0..<20).map { TrayItem(kind: .file, value: "/tmp/\($0)") }, to: tray)
    XCTAssertEqual(tray.count, Tray.limit)
    XCTAssertEqual(tray.first?.value, "/tmp/0")
    XCTAssertEqual(a.name, "a.pdf")
    XCTAssertEqual(b.name, "example.com/x")
  }
}
