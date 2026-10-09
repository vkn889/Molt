import Foundation

/// Things Molt can wear. Molt wears at most one item per slot. Items are earned by looking after
/// Molt, spending time with friends, finishing agent work, keeping a GitHub streak, or simply
/// being around during a season; once earned they stay.
public struct WardrobeItem: Identifiable, Equatable, Sendable {
  public enum Slot: String, CaseIterable, Sendable { case head, face, neck, back }
  public enum Unlock: Equatable, Sendable {
    case start
    /// Already granted into the companion's inventory by care and activities.
    case care(String)
    case friends(Int)
    case agentTasks(Int)
    case streak(Int)
    /// Collectable during these months (1 to 12).
    case season([Int])
  }
  public var id: String
  public var name: String
  public var slot: Slot
  public var unlock: Unlock

  public static let all: [WardrobeItem] = [
    WardrobeItem(id: "scarf", name: "Scarf", slot: .neck, unlock: .start),
    WardrobeItem(id: "glasses", name: "Glasses", slot: .face, unlock: .care("Earn 20 care points")),
    WardrobeItem(id: "hat", name: "Top hat", slot: .head, unlock: .care("Earn 60 care points")),
    WardrobeItem(id: "star", name: "Star pin", slot: .head, unlock: .care("Earn 120 care points")),
    WardrobeItem(id: "backpack", name: "Backpack", slot: .back, unlock: .care("Go exploring")),
    WardrobeItem(id: "flower", name: "Flower", slot: .head, unlock: .care("Make something creative")),
    WardrobeItem(id: "bowtie", name: "Bow tie", slot: .neck, unlock: .friends(10)),
    WardrobeItem(id: "headphones", name: "Headphones", slot: .head, unlock: .friends(30)),
    WardrobeItem(id: "cape", name: "Cape", slot: .back, unlock: .friends(60)),
    WardrobeItem(id: "halo", name: "Halo", slot: .head, unlock: .friends(100)),
    WardrobeItem(id: "beanie", name: "Beanie", slot: .head, unlock: .agentTasks(5)),
    WardrobeItem(id: "hardhat", name: "Hard hat", slot: .head, unlock: .agentTasks(25)),
    WardrobeItem(id: "shades", name: "Shades", slot: .face, unlock: .streak(7)),
    WardrobeItem(id: "pumpkin", name: "Pumpkin", slot: .head, unlock: .season([10])),
    WardrobeItem(id: "santa", name: "Winter hat", slot: .head, unlock: .season([12])),
    WardrobeItem(id: "bunny", name: "Bunny ears", slot: .head, unlock: .season([4])),
  ]
  public static func find(_ id: String) -> WardrobeItem? { all.first { $0.id == id } }

  public var requirement: String {
    switch unlock {
    case .start: return "Molt's first scarf"
    case .care(let text): return text
    case .friends(let points): return "Reach \(points) friend points in Hangouts"
    case .agentTasks(let count): return "Finish \(count) agent tasks"
    case .streak(let days): return "Keep a \(days)-day GitHub streak"
    case .season(let months):
      let names = months.map { Calendar(identifier: .gregorian).monthSymbols[$0 - 1] }
      return "Collect in \(names.joined(separator: " or "))"
    }
  }
}

/// Everything that decides what Molt has earned.
public struct WardrobeProgress: Equatable, Sendable {
  public var inventory: [String]
  public var friendPoints: Int
  public var agentTasks: Int
  public var bestStreak: Int
  public var month: Int
  public init(inventory: [String], friendPoints: Int, agentTasks: Int, bestStreak: Int, month: Int) {
    self.inventory = inventory; self.friendPoints = friendPoints; self.agentTasks = agentTasks
    self.bestStreak = bestStreak; self.month = month
  }
  public func owns(_ item: WardrobeItem) -> Bool {
    if inventory.contains(item.id) { return true }
    switch item.unlock {
    case .start: return true
    case .care: return false
    case .friends(let points): return friendPoints >= points
    case .agentTasks(let count): return agentTasks >= count
    case .streak(let days): return bestStreak >= days
    case .season(let months): return months.contains(month)
    }
  }
  /// Items earned now that are not yet in the inventory, so seasonal finds are kept after the season.
  public var newlyEarned: [String] { WardrobeItem.all.filter { !inventory.contains($0.id) && owns($0) }.map(\.id) }
}

extension Appearance {
  /// What Molt is wearing, one item per slot. Older saves only have `accessory`.
  public var outfit: [String] {
    get {
      if let worn { return worn }
      return accessory == "none" ? [] : [accessory]
    }
    set {
      var bySlot: [WardrobeItem.Slot: String] = [:]
      for id in newValue { if let item = WardrobeItem.find(id) { bySlot[item.slot] = id } }
      let ordered = WardrobeItem.Slot.allCases.compactMap { bySlot[$0] }
      worn = ordered
      accessory = ordered.first ?? "none"
    }
  }
  /// Puts an item on, replacing whatever was in its slot, or takes it off if it was worn.
  public mutating func toggle(_ id: String) {
    guard let item = WardrobeItem.find(id) else { return }
    if outfit.contains(id) {
      outfit = outfit.filter { $0 != id }
    } else {
      outfit = outfit.filter { WardrobeItem.find($0)?.slot != item.slot } + [id]
    }
  }
}
