import Foundation

public struct StatDefinition: Codable {
  public var id: String
  public var name: String
  public var initialValue: Double
  public var decayPerHour: Double
}
public struct EvolutionStage: Codable {
  public var minTraits: [String: Double]?
  public var requiredSkills: [String: Int]?
  public var requiredInterests: [String: Int]?
  public var id: String
  public var displayName: String
  public var sprite: String
  public var minAgeDays: Double
  public var requiredPreviousStage: String?
  public var minCareScore: Double?
  public var nextStages: [String]
}
public struct Personality: Codable {
  public var dialogue: [String: [String]]
  public var reactionSpeed: Double
}
public struct Interaction: Codable {
  public var cooldownGroup: String?
  public var cooldownSeconds: Double?
  public var id: String
  public var name: String
  public var symbol: String
  public var effects: [String: Double]
}
public struct HealthMapping: Codable {
  public var signal: String
  public var belowThreshold: Double?
  public var aboveThreshold: Double?
  public var atLeast: String?
  public var affectsStat: String?
  public var delta: Double?
  public var triggersEvent: String?
  public var cooldownMinutes: Double?
}
public struct PetDefinition: Codable {
  public var schemaVersion: Int?
  public var author: String?
  public var minimumAppVersion: String?
  public var spriteAtlas: String?

  public var id: String
  public var name: String
  public var statDefinitions: [StatDefinition]
  public var evolutionTree: [EvolutionStage]
  public var personality: Personality
  public var interactions: [Interaction]
  public var systemHealthMappings: [HealthMapping]?
  public func validate() throws {
    func require(_ test: Bool, _ message: String) throws {
      if !test { throw MoltError.invalid(message) }
    }
    try require(!id.isEmpty && !name.isEmpty, "Definition needs an ID and name.")
    try require(
      (schemaVersion ?? 1) <= 2 && (schemaVersion ?? 1) > 0, "Unsupported species schema version.")
    try require(
      id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
      "Use a simple species ID, up to 64 letters, numbers, hyphens or underscores.")
    try require(
      spriteAtlas == nil
        || spriteAtlas!.range(of: "^[A-Za-z0-9_-]+\\.png$", options: .regularExpression) != nil,
      "Atlas must be a local PNG filename, without paths or URLs.")
    if let version = minimumAppVersion {
      try require(
        version.compare("0.2.0", options: .numeric) != .orderedDescending,
        "This species needs Molt \(version) or later.")
    }
    try require(
      evolutionTree.count <= 100 && statDefinitions.count <= 10 && interactions.count <= 40,
      "Species exceeds supported size limits.")
    let stats = Set(statDefinitions.map(\.id))
    let stages = Set(evolutionTree.map(\.id))
    try require(
      !stats.isEmpty && stats.count == statDefinitions.count,
      "Stat IDs must be nonempty and unique.")
    try require(!stages.isEmpty && stages.count == evolutionTree.count, "Stage IDs must be unique.")
    for s in statDefinitions {
      try require(
        !s.id.isEmpty && s.initialValue.isFinite && (0...100).contains(s.initialValue)
          && s.decayPerHour.isFinite && s.decayPerHour >= 0, "Invalid stat \(s.id).")
    }
    for s in evolutionTree {
      try require(
        (s.minTraits ?? [:]).allSatisfy {
          ["curiosity", "energy", "social", "novelty"].contains($0.key)
            && (0...1).contains($0.value)
        }, "Invalid trait requirement.")
      try require(
        (s.requiredSkills ?? [:]).values.allSatisfy { (0...100).contains($0) }
          && (s.requiredInterests ?? [:]).values.allSatisfy { $0 >= 0 },
        "Invalid skill or interest requirement.")
      try require(
        s.minAgeDays.isFinite && s.minAgeDays >= 0
          && (s.minCareScore == nil || (0...100).contains(s.minCareScore!)),
        "Invalid stage thresholds.")
      try require(
        s.nextStages.allSatisfy { stages.contains($0) && $0 != s.id }
          && (s.requiredPreviousStage == nil || stages.contains(s.requiredPreviousStage!)),
        "Unknown stage reference.")
    }
    var visited = Set<String>()
    var visiting = Set<String>()
    func visit(_ id: String) throws {
      if visited.contains(id) { return }
      try require(!visiting.contains(id), "Evolution tree contains a cycle.")
      visiting.insert(id)
      for next in evolutionTree.first(where: { $0.id == id })!.nextStages { try visit(next) }
      visiting.remove(id)
      visited.insert(id)
    }
    for id in stages { try visit(id) }
    try require(
      personality.reactionSpeed.isFinite && personality.reactionSpeed > 0,
      "Reaction speed must be positive.")
    try require(
      Set(interactions.map(\.id)).count == interactions.count, "Interaction IDs must be unique.")
    for action in interactions {
      try require(
        action.cooldownSeconds == nil
          || (action.cooldownSeconds!.isFinite && action.cooldownSeconds! >= 0
            && action.cooldownSeconds! <= 604800),
        "Invalid cooldown.")
      try require(
        !action.id.isEmpty
          && action.effects.allSatisfy { stats.contains($0.key) && $0.value.isFinite },
        "Invalid interaction effects.")
    }
    for m in systemHealthMappings ?? [] {
      try require(
        [
          "batteryLevel", "isCharging", "cpuLoad", "memoryPressure", "diskFreeRatio",
          "thermalState", "uptimeHours",
        ].contains(m.signal), "Unknown health signal.")
      try require(
        [m.belowThreshold != nil, m.aboveThreshold != nil, m.atLeast != nil].filter { $0 }.count
          == 1, "Mapping needs exactly one condition.")
      try require(
        m.atLeast == nil
          || (m.signal == "thermalState"
            && ["nominal", "fair", "serious", "critical"].contains(m.atLeast!)),
        "Invalid thermal threshold.")
      try require(
        m.affectsStat == nil || (stats.contains(m.affectsStat!) && m.delta?.isFinite == true),
        "Invalid mapped stat.")
      try require(m.affectsStat != nil || m.triggersEvent != nil, "Mapping needs an effect.")
      try require(
        m.cooldownMinutes == nil || (m.cooldownMinutes!.isFinite && m.cooldownMinutes! >= 1),
        "Cooldown must be at least one minute.")
    }
  }
}
public enum MoltError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}
public struct CareLogEntry: Codable {
  public var day: Date
  public var weightedHealth: Double
  public var seconds: Double
  public var average: Double { seconds > 0 ? weightedHealth / seconds : 0 }
}
public struct PetState: Codable {
  public var schemaVersion: Int? = 2
  public var companion: CompanionState?
  public var definitionSnapshot: PetDefinition?

  public var id: UUID
  public var definitionID: String
  public var stageID: String
  public var birthDate: Date
  public var lastUpdated: Date
  public var stats: [String: Double]
  public var careLog: [CareLogEntry]
  public var mappingAppliedAt: [String: Date]
  public init(definition: PetDefinition, now: Date = Date()) {
    id = UUID()
    definitionSnapshot = definition
    definitionID = definition.id
    stageID = definition.evolutionTree[0].id
    birthDate = now
    lastUpdated = now
    stats = Dictionary(
      uniqueKeysWithValues: definition.statDefinitions.map { ($0.id, $0.initialValue) })
    careLog = []
    mappingAppliedAt = [:]
  }
  public func careScore(at now: Date, calendar: Calendar = .current) -> Double {
    let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
    let entries = careLog.filter { $0.day >= start && $0.day <= now }
    let seconds = entries.reduce(0) { $0 + $1.seconds }
    return seconds > 0 ? entries.reduce(0) { $0 + $1.weightedHealth } / seconds : 0
  }
}
public struct SystemHealthSnapshot {
  public var values: [String: Double]
  public init(values: [String: Double] = [:]) { self.values = values }
}
public protocol SystemHealthMonitoring { func currentSnapshot() -> SystemHealthSnapshot }
public enum PetAction: Equatable {
  case mood(String)
  case speak(String)
  case evolve(String)
}
public protocol PetBrain {
  func decideAction(
    state: PetState, definition: PetDefinition, event: String?, snapshot: SystemHealthSnapshot?,
    now: Date
  ) -> PetAction
}
public struct RuleBasedBrain: PetBrain {
  public init() {}
  public func decideAction(
    state: PetState, definition: PetDefinition, event: String?, snapshot: SystemHealthSnapshot?,
    now: Date
  ) -> PetAction {
    if let event {
      return .speak(definition.personality.dialogue[event]?.first ?? "Thanks for being here.")
    }
    if let stage = definition.evolutionTree.first(where: { $0.id == state.stageID }) {
      for id in stage.nextStages {
        guard let next = definition.evolutionTree.first(where: { $0.id == id }) else { continue }
        let traitsMatch = (next.minTraits ?? [:]).allSatisfy {
          (state.companion?.traits[$0.key] ?? 0) >= $0.value
        }
        let skillsMatch = (next.requiredSkills ?? [:]).allSatisfy {
          (state.companion?.skills[$0.key] ?? 0) >= $0.value
        }
        let interestsMatch = (next.requiredInterests ?? [:]).allSatisfy {
          (state.companion?.interests[$0.key] ?? 0) >= $0.value
        }
        if traitsMatch && skillsMatch && interestsMatch
          && (now.timeIntervalSince(state.birthDate) - (state.companion?.pausedSeconds ?? 0))
            / 86400 >= next.minAgeDays
          && (next.requiredPreviousStage == nil || next.requiredPreviousStage == state.stageID)
          && (next.minCareScore == nil || state.careScore(at: now) >= next.minCareScore!)
        {
          return .evolve(id)
        }
      }
    }
    if (snapshot?.values["thermalState"] ?? 0) >= 2 { return .mood("sweating") }
    if (state.stats["energy"] ?? 100) < 25 { return .mood("sleepy") }
    if (state.stats["hunger"] ?? 100) < 30 { return .mood("hungry") }
    return .mood(state.stats.values.min() ?? 0 > 65 ? "happy" : "idle")
  }
}
