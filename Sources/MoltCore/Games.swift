import Foundation

public struct MemoryGame: Codable {
  public var cards: [Int]
  public var matched: Set<Int> = []
  public var revealed: [Int] = []
  public var moves = 0
  public init(pairs: Int = 6, seed: UInt64) {
    var rng = SeededRandom(seed: seed)
    cards = Array((0..<max(2, min(8, pairs))).flatMap { [$0, $0] }).shuffled(using: &rng)
  }
  public var complete: Bool { matched.count == cards.count }
  public mutating func choose(_ index: Int) {
    guard cards.indices.contains(index), !matched.contains(index), !revealed.contains(index),
      !complete
    else { return }
    if revealed.count == 2 { revealed = [] }
    revealed.append(index)
    if revealed.count == 2 {
      moves += 1
      if cards[revealed[0]] == cards[revealed[1]] {
        matched.formUnion(revealed)
        revealed = []
      }
    }
  }
}
public struct RhythmGame: Codable {
  public var sequence: [Int]
  public var entered: [Int] = []
  public var mistakes = 0
  public init(length: Int = 5, seed: UInt64) {
    var rng = SeededRandom(seed: seed)
    sequence = (0..<length).map { _ in Int.random(in: 0...3, using: &rng) }
  }
  public var complete: Bool { entered == sequence }
  public mutating func choose(_ direction: Int) {
    guard !complete else { return }
    if sequence[entered.count] == direction {
      entered.append(direction)
    } else {
      entered = []
      mistakes += 1
    }
  }
}
public struct FetchGame: Codable {
  public var position = 0
  public var obstacles: Set<Int>
  public var moves = 0
  public init() { obstacles = [7, 8, 13, 17, 22] }
  public var complete: Bool { position == 24 }
  public mutating func move(_ direction: Int) {
    let row = position / 5
    let column = position % 5
    let next =
      direction == 0
      ? (row - 1, column)
      : direction == 1 ? (row, column + 1) : direction == 2 ? (row + 1, column) : (row, column - 1)
    guard (0..<5).contains(next.0), (0..<5).contains(next.1),
      !obstacles.contains(next.0 * 5 + next.1), !complete
    else { return }
    position = next.0 * 5 + next.1
    moves += 1
  }
}
public struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64
  public init(seed: UInt64) { state = seed == 0 ? 1 : seed }
  public mutating func next() -> UInt64 {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state
  }
}
public struct GameSession: Codable {
  public var id = UUID()
  public var kind: String
  public var practice: Bool
  public var activityID: UUID?
  public var memory: MemoryGame
  public var rhythm: RhythmGame
  public var fetch = FetchGame()
  public var completed = false
  public init(kind: String, practice: Bool, activityID: UUID?, easy: Bool) {
    self.kind = kind
    self.practice = practice
    self.activityID = activityID
    let seed = UInt64(Date().timeIntervalSince1970)
    memory = MemoryGame(pairs: easy ? 4 : 8, seed: seed)
    rhythm = RhythmGame(length: easy ? 4 : 7, seed: seed)
  }
  public var won: Bool {
    kind == "memory" ? memory.complete : kind == "fetch" ? fetch.complete : rhythm.complete
  }
}
