import Foundation

/// A small calculator for the notch: arithmetic with + − × ÷ ^ and brackets, percentages
/// ("12% of 80", "80 + 15%"), and unit conversions ("5 km in mi", "70 f to c"). It parses the
/// text itself; nothing is ever evaluated as code.
public enum Calculator {
  public struct Answer: Equatable, Sendable {
    public var value: Double
    public var unit: String?
    public var text: String {
      let number = Calculator.format(value)
      return unit.map { "\(number) \($0)" } ?? number
    }
  }
  public static func evaluate(_ input: String) -> Answer? {
    let text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 200 else { return nil }
    if let converted = convert(text) { return converted }
    // "12% of 80"
    if let range = text.range(of: "% of ") {
      guard let percent = arithmetic(String(text[..<range.lowerBound])), let base = arithmetic(String(text[range.upperBound...])) else { return nil }
      return Answer(value: percent / 100 * base)
    }
    return arithmetic(text).map { Answer(value: $0) }
  }
  public static func format(_ value: Double) -> String {
    guard value.isFinite else { return "∞" }
    if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 6
    formatter.minimumFractionDigits = 0
    formatter.usesGroupingSeparator = false
    formatter.decimalSeparator = "."
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  // MARK: Arithmetic

  /// Recursive descent over + − (lowest), × ÷ %, ^ (right-associative), unary minus, brackets.
  static func arithmetic(_ text: String) -> Double? {
    var parser = Parser(Array(text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
      .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "").filter { !$0.isWhitespace }))
    guard let value = parser.expression(), parser.done, value.isFinite else { return nil }
    return value
  }
  /// "15%" on its own is 0.15; after + or − ("80 + 15%") it means 15% of what came before.
  struct Parser {
    var characters: [Character]
    var index = 0
    var depth = 0
    init(_ characters: [Character]) { self.characters = characters }
    var done: Bool { index == characters.count }
    var peek: Character? { index < characters.count ? characters[index] : nil }
    func at(_ offset: Int) -> Character? { index + offset < characters.count ? characters[index + offset] : nil }
    mutating func expression() -> Double? {
      guard var value = term(right: false) else { return nil }
      while let op = peek, op == "+" || op == "-" {
        index += 1
        guard var right = term(right: true) else { return nil }
        if peek == "%" { index += 1; right = value * right / 100 }
        value = op == "+" ? value + right : value - right
      }
      return value
    }
    /// `right` is true for what follows + or −, which leaves a final % for `expression`.
    mutating func term(right: Bool) -> Double? {
      guard var value = factor(right: right) else { return nil }
      while let op = peek, op == "*" || op == "/" || op == "x" {
        index += 1
        guard let next = factor(right: right) else { return nil }
        if op == "/" { guard next != 0 else { return nil }; value /= next } else { value *= next }
      }
      return value
    }
    mutating func factor(right: Bool) -> Double? {
      guard let value = power() else { return nil }
      guard peek == "%" else { return value }
      let after = at(1)
      if right && (after == nil || after == "+" || after == "-" || after == ")") { return value }
      index += 1
      return value / 100
    }
    mutating func power() -> Double? {
      guard let base = unary() else { return nil }
      if peek == "^" {
        index += 1
        guard let exponent = power() else { return nil }
        return pow(base, exponent)
      }
      return base
    }
    mutating func unary() -> Double? {
      if peek == "-" { index += 1; return unary().map { -$0 } }
      if peek == "+" { index += 1; return unary() }
      return primary()
    }
    mutating func primary() -> Double? {
      if peek == "(" {
        depth += 1
        guard depth < 32 else { return nil }
        index += 1
        let value = expression()
        guard peek == ")" else { return nil }
        index += 1
        depth -= 1
        return value
      }
      var digits = ""
      while let c = peek, c.isNumber || c == "." { digits.append(c); index += 1 }
      return Double(digits)
    }
  }

  // MARK: Units

  struct Unit { var names: [String]; var symbol: String; var dimension: String; var factor: Double; var offset: Double = 0 }
  /// Each unit's size in the dimension's base unit (metre, gram, litre, second, byte, metre per second).
  static let units: [Unit] = [
    Unit(names: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"], symbol: "mm", dimension: "length", factor: 0.001),
    Unit(names: ["cm", "centimeter", "centimeters", "centimetre", "centimetres"], symbol: "cm", dimension: "length", factor: 0.01),
    Unit(names: ["m", "meter", "meters", "metre", "metres"], symbol: "m", dimension: "length", factor: 1),
    Unit(names: ["km", "kilometer", "kilometers", "kilometre", "kilometres"], symbol: "km", dimension: "length", factor: 1000),
    Unit(names: ["in", "inch", "inches", "\""], symbol: "in", dimension: "length", factor: 0.0254),
    Unit(names: ["ft", "foot", "feet", "'"], symbol: "ft", dimension: "length", factor: 0.3048),
    Unit(names: ["yd", "yard", "yards"], symbol: "yd", dimension: "length", factor: 0.9144),
    Unit(names: ["mi", "mile", "miles"], symbol: "mi", dimension: "length", factor: 1609.344),
    Unit(names: ["mg", "milligram", "milligrams"], symbol: "mg", dimension: "mass", factor: 0.001),
    Unit(names: ["g", "gram", "grams"], symbol: "g", dimension: "mass", factor: 1),
    Unit(names: ["kg", "kilogram", "kilograms", "kilo", "kilos"], symbol: "kg", dimension: "mass", factor: 1000),
    Unit(names: ["oz", "ounce", "ounces"], symbol: "oz", dimension: "mass", factor: 28.349523125),
    Unit(names: ["lb", "lbs", "pound", "pounds"], symbol: "lb", dimension: "mass", factor: 453.59237),
    Unit(names: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"], symbol: "ml", dimension: "volume", factor: 0.001),
    Unit(names: ["l", "liter", "liters", "litre", "litres"], symbol: "l", dimension: "volume", factor: 1),
    Unit(names: ["cup", "cups"], symbol: "cups", dimension: "volume", factor: 0.2365882365),
    Unit(names: ["floz", "fl oz", "fluid ounce", "fluid ounces"], symbol: "fl oz", dimension: "volume", factor: 0.0295735295625),
    Unit(names: ["gal", "gallon", "gallons"], symbol: "gal", dimension: "volume", factor: 3.785411784),
    Unit(names: ["s", "sec", "secs", "second", "seconds"], symbol: "s", dimension: "time", factor: 1),
    Unit(names: ["min", "mins", "minute", "minutes"], symbol: "min", dimension: "time", factor: 60),
    Unit(names: ["h", "hr", "hrs", "hour", "hours"], symbol: "h", dimension: "time", factor: 3600),
    Unit(names: ["day", "days"], symbol: "days", dimension: "time", factor: 86400),
    Unit(names: ["week", "weeks"], symbol: "weeks", dimension: "time", factor: 604800),
    Unit(names: ["b", "byte", "bytes"], symbol: "B", dimension: "data", factor: 1),
    Unit(names: ["kb", "kilobyte", "kilobytes"], symbol: "KB", dimension: "data", factor: 1000),
    Unit(names: ["mb", "megabyte", "megabytes"], symbol: "MB", dimension: "data", factor: 1_000_000),
    Unit(names: ["gb", "gigabyte", "gigabytes"], symbol: "GB", dimension: "data", factor: 1_000_000_000),
    Unit(names: ["tb", "terabyte", "terabytes"], symbol: "TB", dimension: "data", factor: 1_000_000_000_000),
    Unit(names: ["kph", "km/h", "kmh"], symbol: "km/h", dimension: "speed", factor: 1 / 3.6),
    Unit(names: ["mph"], symbol: "mph", dimension: "speed", factor: 0.44704),
    Unit(names: ["m/s"], symbol: "m/s", dimension: "speed", factor: 1),
    Unit(names: ["c", "°c", "celsius"], symbol: "°C", dimension: "temperature", factor: 1),
    Unit(names: ["f", "°f", "fahrenheit"], symbol: "°F", dimension: "temperature", factor: 5.0 / 9.0, offset: -32),
    Unit(names: ["k", "kelvin"], symbol: "K", dimension: "temperature", factor: 1, offset: -273.15),
  ]
  static func unit(_ name: String) -> Unit? {
    let key = name.trimmingCharacters(in: .whitespaces)
    return units.first { $0.names.contains(key) }
  }
  /// "5 km in mi", "5km to miles", "70 f in c".
  static func convert(_ text: String) -> Answer? {
    for separator in [" in ", " to ", " as "] {
      guard let range = text.range(of: separator) else { continue }
      let left = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
      let right = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
      guard let target = unit(right) else { continue }
      // Split the number from its unit: "5km", "5 km", "-3.5 f".
      let numberPart = left.prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == " " || $0 == "+" || $0 == "*" || $0 == "/" || $0 == "(" || $0 == ")" }
      let unitPart = String(left.dropFirst(numberPart.count))
      guard let source = unit(unitPart), source.dimension == target.dimension, let amount = arithmetic(String(numberPart)) else { continue }
      let base = (amount + source.offset) * source.factor
      return Answer(value: base / target.factor - target.offset, unit: target.symbol)
    }
    return nil
  }
}

/// Something you want to do every day, with how many days in a row you've done it.
public struct Habit: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var symbol: String
  /// The days you did it, as "yyyy-MM-dd" in your time zone.
  public var done: [String]
  public init(id: UUID = UUID(), title: String, symbol: String = "checkmark", done: [String] = []) {
    self.id = id; self.title = title; self.symbol = symbol; self.done = done
  }
  public static func day(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
  public func isDone(on date: Date, calendar: Calendar = .current) -> Bool { done.contains(Self.day(date, calendar: calendar)) }
  /// Days in a row up to today; today not done yet doesn't break the streak.
  public func streak(at now: Date, calendar: Calendar = .current) -> Int {
    let set = Set(done)
    var day = calendar.startOfDay(for: now)
    if !set.contains(Self.day(day, calendar: calendar)) {
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
      day = yesterday
    }
    var count = 0
    while set.contains(Self.day(day, calendar: calendar)) {
      count += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
      day = previous
    }
    return count
  }
  /// Ticks today on or off. Only the last year is kept.
  public mutating func toggle(on date: Date, calendar: Calendar = .current) {
    let key = Self.day(date, calendar: calendar)
    if let index = done.firstIndex(of: key) { done.remove(at: index) } else { done.append(key) }
    done = Array(done.sorted().suffix(366))
  }
}

/// A date you're counting down to.
public struct Countdown: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var date: Date
  public init(id: UUID = UUID(), title: String, date: Date) { self.id = id; self.title = title; self.date = date }
  /// Whole days left (0 on the day itself, negative once it's passed).
  public func days(from now: Date, calendar: Calendar = .current) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
  }
}

/// When the next water or stretch break is due.
public enum Breaks {
  /// The next time a break every `minutes` is due after `last` (or after `start` if never taken),
  /// skipping ahead past `now` if it was missed.
  public static func next(every minutes: Int, last: Date?, start: Date, now: Date) -> Date {
    let interval = Double(max(1, minutes)) * 60
    var due = (last ?? start).addingTimeInterval(interval)
    if due < now.addingTimeInterval(-interval) {
      let missed = floor(now.timeIntervalSince(due) / interval)
      due = due.addingTimeInterval(missed * interval)
    }
    return due
  }
}
