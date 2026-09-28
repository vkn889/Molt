import Foundation

public struct Appearance: Codable, Equatable {
  public var palette = "sage"
  public var accessory = "none"
  public var eyes = "round"
  public var markings = "plain"
  public var fins = "leaf"
  public var tail = "curl"
  public var body = "round"
  public init() {}
}
public struct MemoryEvent: Codable, Identifiable {
  public var id = UUID()
  public var date: Date
  public var text: String
  public var kind: String
  public init(_ text: String, kind: String = "memory", at date: Date) {
    self.text = text
    self.kind = kind
    self.date = date
  }
}
public struct PetPreferences: Codable {
  public var reducedMotion = false, sound = false, clickThrough = false, fullScreen = true
  public var adaptivePersonality = true, vacation = false, highContrast = false
  public var size = 1.0, animationIntensity = 0.6
  public var mode = "quiet coworker", movement = "stationary", talkativeness = "gentle"
  public var sleepStart = 22, sleepEnd = 7, quietStart = 21, quietEnd = 8
  public var preferredDisplay = 0
  public init() {}
  public func sleeping(at date: Date, calendar: Calendar = .current) -> Bool {
    Self.within(calendar.component(.hour, from: date), start: sleepStart, end: sleepEnd)
  }
  public func quiet(at date: Date, calendar: Calendar = .current) -> Bool {
    Self.within(calendar.component(.hour, from: date), start: quietStart, end: quietEnd)
  }
  private static func within(_ hour: Int, start: Int, end: Int) -> Bool {
    start == end ? false : start < end ? hour >= start && hour < end : hour >= start || hour < end
  }
}
public struct ActivityInstance: Codable, Identifiable {
  public var id = UUID()
  public var kind: String
  public var title: String
  public var started: Date
  public var end: Date
  public var group: String
  public var cooldown: Double
  public var reward: Int
  public init(
    kind: String, title: String, now: Date, duration: Double, group: String, cooldown: Double,
    reward: Int = 8
  ) {
    self.kind = kind
    self.title = title
    started = now
    end = now.addingTimeInterval(duration)
    self.group = group
    self.cooldown = cooldown
    self.reward = reward
  }
}
public struct CompanionState: Codable {
  public var name = "Molt", nickname = "", profile = ""
  public var adopted: Date, birthday: Date
  public var appearance = Appearance(), preferences = PetPreferences()
  public var outfits: [String: Appearance] = [:]
  public var cooldowns: [String: Date] = [:]
  public var lastReliableClock: Date
  public var clockCorrected = false
  public var game: GameSession?
  public var active: ActivityInstance?
  public var lastRestApplied: Date?
  public var rewardedIDs: [UUID] = []
  public var dailyRewards: [String: Int] = [:], repetitions: [String: Int] = [:],
    skills: [String: Int] = [:]
  public var traits: [String: Double] = [
    "curiosity": 0.5, "energy": 0.5, "social": 0.5, "novelty": 0.5,
  ]
  public var interests: [String: Int] = [:]
  public var memories: [MemoryEvent] = []
  public var inventory = ["none", "scarf"]
  public var home = ["bed", "plant"]
  public var homePositions: [String: Int] = ["bed": 0, "plant": 1]
  public var experience = 0, familiarity = 0, pausedSeconds = 0.0
  public var unlockedForms: [String] = [], pendingEvolution: String?
  public var adoptionComplete = false
  public var dialogueHistory: [String] = []
  public init(now: Date) {
    adopted = now
    birthday = now
    lastReliableClock = now
  }
  public mutating func remember(_ text: String, kind: String = "memory", at now: Date) {
    memories.append(MemoryEvent(text, kind: kind, at: now))
    memories = Array(memories.suffix(250))
  }
}

/// A process-local monotonic clock with a durable wall-clock lower bound.
public final class CompanionClock {
  private var anchor: Date
  private var uptime: TimeInterval
  public init(wall: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    anchor = wall
    self.uptime = uptime
  }
  public func now(
    wall: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime, floor: Date
  ) -> Date {
    let elapsed = max(0, uptime - self.uptime)
    let result = max(floor, max(wall, anchor.addingTimeInterval(elapsed)))
    anchor = result
    self.uptime = uptime
    return result
  }
}
public enum ActivityEngine {
  public static func group(for action: Interaction) -> String {
    action.cooldownGroup ?? ["feed": "meal", "play": "toy", "rest": "rest"][action.id] ?? action.id
  }
  public static func duration(for action: Interaction) -> Double {
    action.cooldownSeconds ?? [
      "feed": 1800.0, "snack": 600, "pet": 15, "play": 600, "groom": 600, "water": 300,
      "story": 600, "rest": 0, "basic-care": 0,
    ][action.id] ?? 600
  }
  public static func reason(_ action: Interaction, state: PetState, at now: Date) -> String? {
    guard let c = state.companion else { return nil }
    if action.id == "basic-care" {
      return (state.stats["hunger"] ?? 100) < 25
        ? nil : "Basic care is available when nourishment is below 25."
    }
    if c.preferences.vacation {
      return "Vacation mode is on. Resume care in Settings, or use your tools."
    }
    if let active = c.active { return "\(active.title) is in progress. Stop it or use your tools." }
    if let end = c.cooldowns[group(for: action)], end > now {
      return
        "Ready at \(end.formatted(date: .omitted, time: .shortened)). Try practice or quiet company."
    }
    if action.id == "feed" && (state.stats["hunger"] ?? 0) >= 90 {
      return "Already comfortably full. Try grooming or a game."
    }
    for (stat, effect) in action.effects where effect < 0 {
      if (state.stats[stat] ?? 0) < -effect {
        return "Needs more \(stat). Rest is always available."
      }
    }
    return nil
  }
  @discardableResult public static func perform(
    _ action: Interaction, state: inout PetState, now: Date
  ) -> Bool {
    guard reason(action, state: state, at: now) == nil, var c = state.companion else {
      return false
    }
    if action.id == "rest" {
      c.active = ActivityInstance(
        kind: "rest", title: "Resting", now: now, duration: 3600, group: "rest", cooldown: 0,
        reward: 0)
      c.lastRestApplied = now
      state.companion = c
      return true
    }
    let group = group(for: action)
    let key = day(now) + ":" + group
    let repeats = c.repetitions[key, default: 0]
    let scale = action.id == "basic-care" ? 1 : max(0.25, 1 / (1 + Double(repeats) * 0.2))
    for (stat, delta) in action.effects {
      state.stats[stat] = min(
        100, max(0, (state.stats[stat] ?? 0) + delta * (delta > 0 ? scale : 1)))
    }
    c.cooldowns[group] = now.addingTimeInterval(duration(for: action))
    c.repetitions[key] = repeats + 1
    if action.id != "basic-care" {
      reward(&c, amount: 2, id: UUID(), now: now)
      c.interests[group, default: 0] += 1
      if c.preferences.adaptivePersonality {
        let trait = group == "toy" ? "energy" : "social"
        c.traits[trait] = min(1, c.traits[trait, default: 0.5] + 0.005 * scale)
      }
      if c.interests[group] == 3 {
        c.remember(
          "\(c.name) is growing fond of \(action.name.lowercased()).", kind: "discovery", at: now)
      }
    }
    c.lastReliableClock = now
    prune(&c, now: now)
    state.companion = c
    return true
  }
  public static func start(
    kind: String, title: String, seconds: Double, group: String, cooldown: Double, energy: Double,
    state: inout PetState, now: Date
  ) -> String? {
    guard var c = state.companion else { return "Adopt a companion first." }
    if c.preferences.vacation {
      return "Resume care after vacation to start a rewarded activity. Practice remains available."
    }
    if c.active != nil { return "Another activity is in progress. Stop it first." }
    if let until = c.cooldowns[group], until > now {
      return
        "Ready at \(until.formatted(date: .omitted, time: .shortened)). Practice is available now."
    }
    if (state.stats["energy"] ?? 100) < energy { return "Not enough energy. Try rest or practice." }
    if state.stats["energy"] != nil {
      state.stats["energy"] = max(0, state.stats["energy"]! - energy)
    }
    c.active = ActivityInstance(
      kind: kind, title: title, now: now, duration: seconds, group: group, cooldown: cooldown)
    c.lastReliableClock = now
    state.companion = c
    return nil
  }
  public static func reconcile(state: inout PetState, now: Date) {
    guard var c = state.companion, let active = c.active else { return }
    if active.kind == "rest" {
      let last = c.lastRestApplied ?? active.started
      let seconds = max(0, min(now, active.end).timeIntervalSince(last))
      if let energy = state.stats["energy"] {
        state.stats["energy"] = min(100, energy + seconds / 120)
      }
      c.lastRestApplied = min(now, active.end)
      state.companion = c
    }
    if now >= active.end && !active.kind.hasPrefix("game:") && !active.kind.hasPrefix("lesson:") {
      _ = finish(id: active.id, state: &state, now: now)
    }
  }
  @discardableResult public static func finish(
    id: UUID, state: inout PetState, now: Date, success: Bool = true
  ) -> Bool {
    guard var c = state.companion, let active = c.active, active.id == id else { return false }
    let interactive = active.kind.hasPrefix("game:") || active.kind.hasPrefix("lesson:")
    guard !success || interactive || now >= active.end else { return false }
    c.active = nil
    c.cooldowns[active.group] = (success && !interactive ? active.end : now).addingTimeInterval(
      active.cooldown)
    if success {
      reward(&c, amount: active.reward, id: id, now: now)
      if active.kind.hasPrefix("lesson:") {
        let skill = String(active.kind.dropFirst(7))
        c.skills[skill] = min(100, c.skills[skill, default: 0] + 20)
      }
      if active.kind.hasPrefix("explore:") {
        let place = String(active.kind.dropFirst(8))
        c.interests[place, default: 0] += 1
        if c.preferences.adaptivePersonality {
          c.traits["curiosity"] = min(1, c.traits["curiosity", default: 0.5] + 0.03)
        }
        if !c.inventory.contains("backpack") { c.inventory.append("backpack") }
      }
      if active.kind == "creative" && !c.inventory.contains("flower") {
        c.inventory.append("flower")
      }
      c.remember("\(c.name) completed \(active.title.lowercased()).", kind: active.kind, at: now)
    } else {
      c.remember(
        "Stopped \(active.title.lowercased()). No completion reward was claimed.", kind: "activity",
        at: now)
    }
    state.companion = c
    return true
  }
  public static func reward(_ c: inout CompanionState, amount: Int, id: UUID, now: Date) {
    guard !c.rewardedIDs.contains(id) else { return }
    c.rewardedIDs.append(id)
    c.rewardedIDs = Array(c.rewardedIDs.suffix(2000))
    let key = day(now)
    let credited = min(max(0, amount), max(0, 60 - c.dailyRewards[key, default: 0]))
    c.dailyRewards[key, default: 0] += credited
    c.experience += credited
    c.familiarity += min(credited, 2)
    for (threshold, item) in [(20, "glasses"), (60, "hat"), (120, "star")]
    where c.experience >= threshold && !c.inventory.contains(item) { c.inventory.append(item) }
    prune(&c, now: now)
  }
  public static func day(_ date: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
  private static func prune(_ c: inout CompanionState, now: Date) {
    let cutoff = day(now.addingTimeInterval(-30 * 86400))
    c.dailyRewards = c.dailyRewards.filter { $0.key >= cutoff }
    c.repetitions = c.repetitions.filter { $0.key >= cutoff }
  }
}

public struct PetArchive: Codable {
  public var formatVersion = 1
  public var state: PetState
  public var atlas: Data?
  public init(state: PetState, atlas: Data?) {
    self.state = state
    self.atlas = atlas
  }
}
