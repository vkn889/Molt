import XCTest
@testable import MoltCore

final class CalculatorTests: XCTestCase {
  func value(_ text: String) -> Double? { Calculator.evaluate(text)?.value }
  func testArithmetic() {
    XCTAssertEqual(value("2 + 3 * 4"), 14)
    XCTAssertEqual(value("(2 + 3) * 4"), 20)
    XCTAssertEqual(value("2^3^2"), 512)
    XCTAssertEqual(value("-4 + 10"), 6)
    XCTAssertEqual(value("10 ÷ 4"), 2.5)
    XCTAssertEqual(value("1,000 × 3"), 3000)
    XCTAssertNil(value("1 / 0"))
    XCTAssertNil(value("2 +"))
    XCTAssertNil(value("hello"))
    XCTAssertNil(value(String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40)))
  }
  func testPercent() {
    XCTAssertEqual(value("12% of 80"), 9.6)
    XCTAssertEqual(value("80 + 15%"), 92)
    XCTAssertEqual(value("80 - 25%"), 60)
    XCTAssertEqual(value("15%"), 0.15)
    XCTAssertEqual(value("200 * 10%"), 20)
  }
  func testUnits() {
    XCTAssertEqual(value("5 km in mi")!, 3.106855, accuracy: 0.0001)
    XCTAssertEqual(Calculator.evaluate("5km to miles")?.unit, "mi")
    XCTAssertEqual(value("212 f in c")!, 100, accuracy: 0.0001)
    XCTAssertEqual(value("0 c to f")!, 32, accuracy: 0.0001)
    XCTAssertEqual(value("2 h in min"), 120)
    XCTAssertEqual(value("1.5 gb in mb"), 1500)
    XCTAssertNil(value("5 km in kg"))
    XCTAssertEqual(Calculator.evaluate("10 lb in kg")?.text, "4.535924 kg")
  }
}

final class HabitTests: XCTestCase {
  func testStreaks() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
    let day = { (offset: Int) in Habit.day(calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar) }
    var habit = Habit(title: "Water", done: [day(-1), day(-2), day(-4)])
    XCTAssertEqual(habit.streak(at: now, calendar: calendar), 2)
    habit.toggle(on: now, calendar: calendar)
    XCTAssertTrue(habit.isDone(on: now, calendar: calendar))
    XCTAssertEqual(habit.streak(at: now, calendar: calendar), 3)
    habit.toggle(on: now, calendar: calendar)
    XCTAssertEqual(habit.streak(at: now, calendar: calendar), 2)
    XCTAssertEqual(Habit(title: "x").streak(at: now, calendar: calendar), 0)
  }
  func testCountdownAndBreaks() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 22))!
    let launch = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9))!
    XCTAssertEqual(Countdown(title: "Launch", date: launch).days(from: now, calendar: calendar), 4)
    XCTAssertEqual(Countdown(title: "Past", date: now.addingTimeInterval(-3 * 86400)).days(from: now, calendar: calendar), -3)
    let start = now.addingTimeInterval(-3600)
    XCTAssertEqual(Breaks.next(every: 20, last: nil, start: start, now: start), start.addingTimeInterval(1200))
    let late = Breaks.next(every: 20, last: start, start: start, now: now)
    XCTAssertTrue(late > now.addingTimeInterval(-1200) && late <= now.addingTimeInterval(1200))
  }
}
