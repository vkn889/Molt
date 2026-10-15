import XCTest
@testable import MoltCore

final class HubLayoutTests: XCTestCase {
  func testDefaultsFillTwoRows() {
    XCTAssertEqual(HubLayout.used(HubLayout.defaults), HubLayout.capacity * 2)
    XCTAssertEqual(HubLayout.rows(HubLayout.defaults).count, 2)
    XCTAssertTrue(HubLayout.fits(HubLayout.defaults))
  }
  func testAddResizeAndMove() {
    let a = HubWidget(kind: "focus"), b = HubWidget(kind: "tasks", span: 2)
    var layout = HubLayout.add(b, to: [a])!
    XCTAssertEqual(HubLayout.rows(layout).count, 1)
    // A wide widget that doesn't fit in what's left of the row starts the next one.
    let wide = HubLayout.add(HubWidget(kind: "clock", span: 2), to: layout)!
    XCTAssertEqual(HubLayout.rows(wide).map { $0.map(\.kind) }, [["focus", "tasks"], ["clock"]])
    XCTAssertNil(HubLayout.add(HubWidget(kind: "clock", span: 2), to: layout, rows: 1))
    layout = HubLayout.add(HubWidget(kind: "clock"), at: 0, to: layout)!
    XCTAssertEqual(layout.map(\.kind), ["clock", "focus", "tasks"])
    XCTAssertEqual(HubLayout.rows(layout).count, 2)
    layout = HubLayout.move(b.id, before: layout[0].id, in: layout)
    XCTAssertEqual(layout.map(\.kind), ["tasks", "clock", "focus"])
    layout = HubLayout.move(b.id, before: nil, in: layout)
    XCTAssertEqual(layout.last?.kind, "tasks")
    layout = HubLayout.remove(b.id, from: layout)
    XCTAssertNotNil(HubLayout.resize(a.id, to: 2, in: layout))
  }
  func testRowLimits() {
    let six = (0..<6).map { _ in HubWidget(kind: "clock") }
    XCTAssertEqual(HubLayout.room(six), 0)
    XCTAssertNil(HubLayout.add(HubWidget(kind: "x"), to: six))
    XCTAssertNotNil(HubLayout.add(HubWidget(kind: "x"), to: six, rows: 3))
    XCTAssertEqual(HubLayout.room(six, rows: 3), 2)
    XCTAssertFalse(HubLayout.fits(six, rows: 1))
    // Two left in the last row: a wide widget still fits there.
    let four = Array(six.prefix(4))
    XCTAssertEqual(HubLayout.room(four), 2)
    // Moving a widget where it would push past the limit is refused.
    let tight = [HubWidget(kind: "a"), HubWidget(kind: "b", span: 2), HubWidget(kind: "c"), HubWidget(kind: "d", span: 2)]
    XCTAssertTrue(HubLayout.fits(tight))
    XCTAssertEqual(HubLayout.move(tight[2].id, before: tight[1].id, in: tight).map(\.kind), tight.map(\.kind))
    XCTAssertEqual(HubLayout.move(tight[3].id, before: tight[2].id, in: tight).map(\.kind), ["a", "b", "d", "c"])
  }
  func testSanitizeDropsUnknownAndOverflow() {
    let layout = [HubWidget(kind: "gone"), HubWidget(kind: "focus", span: 5), HubWidget(kind: "tasks", span: 2), HubWidget(kind: "clock")]
    let clean = HubLayout.sanitize(layout, known: ["focus", "tasks", "clock"])
    XCTAssertEqual(clean.map(\.kind), ["focus", "tasks", "clock"])
    XCTAssertEqual(clean.map(\.span), [2, 2, 1])
    let crowded = (0..<9).map { _ in HubWidget(kind: "tasks", span: 2) }
    XCTAssertEqual(HubLayout.sanitize(crowded, known: ["tasks"]).count, 2)
    XCTAssertEqual(HubLayout.sanitize(crowded, known: ["tasks"], rows: 3).count, 3)
  }
}

final class ProcessTableTests: XCTestCase {
  func testGroupsHelpersUnderTheirApp() {
    let output = """
        101  12.5 204800 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
        102  30.0 102400 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
        200   1,5  2048 /usr/sbin/cfprefsd
        bad line
      """
    let samples = ProcessTable.parse(output)
    XCTAssertEqual(samples.count, 3)
    XCTAssertEqual(samples[2].cpu, 1.5)
    let groups = ProcessTable.group(samples).sorted { $0.cpu > $1.cpu }
    XCTAssertEqual(groups.first?.name, "Google Chrome")
    XCTAssertEqual(groups.first?.cpu, 42.5)
    XCTAssertEqual(groups.first?.memory, 300 * 1024 * 1024)
    XCTAssertEqual(groups.first?.pids.sorted(), [101, 102])
    XCTAssertEqual(groups.last?.name, "cfprefsd")
    XCTAssertNil(groups.last?.appPath)
  }
}

final class AccountRulesTests: XCTestCase {
  func testValidation() {
    XCTAssertNil(AccountRules.usernameProblem("molt_fan"))
    XCTAssertNotNil(AccountRules.usernameProblem("ab"))
    XCTAssertNotNil(AccountRules.usernameProblem("no spaces"))
    XCTAssertNotNil(AccountRules.usernameProblem("émile"))
    XCTAssertNil(AccountRules.passwordProblem("leafy2026"))
    XCTAssertNotNil(AccountRules.passwordProblem("short1"))
    XCTAssertNotNil(AccountRules.passwordProblem("lettersonly"))
    XCTAssertTrue(AccountRules.emailLooksValid("me@example.com"))
    XCTAssertFalse(AccountRules.emailLooksValid("me@example"))
    XCTAssertFalse(AccountRules.emailLooksValid("me example@x.com"))
  }
  func testReadsJWTClaims() {
    // {"sub":"abc","aal":"aal2"}
    let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhYmMiLCJhYWwiOiJhYWwyIn0.sig"
    XCTAssertEqual(AccountRules.claims(token)?["aal"] as? String, "aal2")
    XCTAssertNil(AccountRules.claims("not-a-token"))
  }
}
