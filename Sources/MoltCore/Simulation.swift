import Foundation

public enum Simulation {
  public static func advance(
    _ state: inout PetState, definition: PetDefinition, to now: Date, calendar: Calendar = .current
  ) {
    guard now > state.lastUpdated else { return }
    if state.companion?.preferences.vacation == true {
      state.companion?.pausedSeconds += now.timeIntervalSince(state.lastUpdated)
      state.lastUpdated = now
      return
    }
    // Only the last 30 days are retained. Fast-forward older decay in constant time.
    let cutoff = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now))!
    if state.lastUpdated < cutoff {
      decay(&state, definition, cutoff.timeIntervalSince(state.lastUpdated))
      state.lastUpdated = cutoff
    }
    while state.lastUpdated < now {
      let day = calendar.startOfDay(for: state.lastUpdated)
      let boundary = calendar.date(byAdding: .day, value: 1, to: day)!
      let end = min(now, boundary)
      let seconds = end.timeIntervalSince(state.lastUpdated)
      let hours = seconds / 3600
      var integral = 0.0
      for stat in definition.statDefinitions {
        let value = state.stats[stat.id] ?? stat.initialValue
        let active = stat.decayPerHour > 0 ? min(hours, value / stat.decayPerHour) : hours
        integral += (value * active - stat.decayPerHour * active * active / 2) * 3600
      }
      integral /= Double(definition.statDefinitions.count)
      if let index = state.careLog.firstIndex(where: { $0.day == day }) {
        state.careLog[index].weightedHealth += integral
        state.careLog[index].seconds += seconds
      } else {
        state.careLog.append(CareLogEntry(day: day, weightedHealth: integral, seconds: seconds))
      }
      decay(&state, definition, seconds)
      state.lastUpdated = end
    }
    state.careLog.removeAll { $0.day < cutoff }
  }
  private static func decay(_ state: inout PetState, _ definition: PetDefinition, _ seconds: Double)
  {
    for stat in definition.statDefinitions {
      state.stats[stat.id] = max(
        0,
        min(100, (state.stats[stat.id] ?? stat.initialValue) - stat.decayPerHour * seconds / 3600))
    }
  }
  public static func interact(_ state: inout PetState, interaction: Interaction) {
    for (key, delta) in interaction.effects {
      state.stats[key] = max(0, min(100, (state.stats[key] ?? 0) + delta))
    }
  }
  public static func applyHealth(
    _ snapshot: SystemHealthSnapshot, state: inout PetState, definition: PetDefinition, now: Date
  ) -> [String] {
    var events: [String] = []
    for (index, mapping) in (definition.systemHealthMappings ?? []).enumerated() {
      guard let value = snapshot.values[mapping.signal], value.isFinite else { continue }
      let thermal = ["nominal": 0.0, "fair": 1.0, "serious": 2.0, "critical": 3.0]
      let matches =
        mapping.belowThreshold.map { value < $0 } ?? mapping.aboveThreshold.map { value > $0 }
        ?? mapping.atLeast.flatMap { thermal[$0] }.map { value >= $0 } ?? false
      let key = String(index)
      guard matches,
        now.timeIntervalSince(state.mappingAppliedAt[key] ?? .distantPast)
          >= (mapping.cooldownMinutes ?? 60) * 60
      else { continue }
      state.mappingAppliedAt[key] = now
      if let stat = mapping.affectsStat, let delta = mapping.delta {
        state.stats[stat] = max(0, min(100, (state.stats[stat] ?? 0) + delta))
      }
      if let event = mapping.triggersEvent { events.append(event) }
    }
    return events
  }
}

public final class PetStore {
  public let directory: URL
  public init(directory: URL) { self.directory = directory }
  public var stateURL: URL { directory.appendingPathComponent("pet-state.json") }
  public func save(_ state: PetState) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(state)
    // Preserve the preceding valid save; never overwrite it with corrupt bytes.
    if let old = try? Data(contentsOf: stateURL),
      (try? decoder().decode(PetState.self, from: old)) != nil
    {
      try old.write(to: directory.appendingPathComponent("pet-state.backup.json"), options: .atomic)
    }
    try data.write(to: stateURL, options: .atomic)
  }
  public func load() throws -> PetState? {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
    let data = try Data(contentsOf: stateURL)
    var state = try decoder().decode(PetState.self, from: data)
    guard (state.schemaVersion ?? 1) <= 2 else {
      throw MoltError.invalid("This save needs a newer version of Molt.")
    }
    if state.companion == nil {
      let backup = directory.appendingPathComponent("pet-state.before-v2.json")
      if !FileManager.default.fileExists(atPath: backup.path) {
        try data.write(to: backup, options: .atomic)
      }
      state.companion = CompanionState(now: state.birthDate)
      state.companion?.unlockedForms = [state.stageID]
      state.companion?.remember(
        "A new chapter begins. Your original care history is safe.", kind: "upgrade",
        at: state.lastUpdated)
      state.schemaVersion = 2
    }
    return state
  }
  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }
  public static func definition(at url: URL) throws -> PetDefinition {
    let d = try JSONDecoder().decode(PetDefinition.self, from: Data(contentsOf: url))
    try d.validate()
    return d
  }
  public static func validate(_ state: PetState, definition: PetDefinition) throws {
    if let c = state.companion {
      let p = c.preferences
      guard (0.75...1.5).contains(p.size), (0...1).contains(p.animationIntensity),
        [p.sleepStart, p.sleepEnd, p.quietStart, p.quietEnd].allSatisfy({ (0...23).contains($0) }),
        c.pausedSeconds.isFinite, c.pausedSeconds >= 0, c.experience >= 0,
        c.skills.values.allSatisfy({ (0...100).contains($0) }),
        c.traits.values.allSatisfy({ (0...1).contains($0) }),
        c.memories.count <= 250, c.rewardedIDs.count <= 2000
      else {
        throw MoltError.invalid(
          "Companion preferences or progression contain invalid values. The original save is preserved."
        )
      }
      if let game = c.game {
        guard (4...16).contains(game.memory.cards.count),
          game.memory.cards.allSatisfy({ (0...7).contains($0) }),
          game.memory.matched.allSatisfy({ game.memory.cards.indices.contains($0) }),
          game.memory.revealed.count <= 2,
          game.memory.revealed.allSatisfy({ game.memory.cards.indices.contains($0) }),
          (1...20).contains(game.rhythm.sequence.count),
          game.rhythm.sequence.allSatisfy({ (0...3).contains($0) }),
          game.rhythm.entered.count <= game.rhythm.sequence.count,
          (0...24).contains(game.fetch.position)
        else { throw MoltError.invalid("Saved game contains invalid values.") }
      }
      if let active = c.active {
        guard active.end >= active.started else {
          throw MoltError.invalid("Invalid activity timing.")
        }
      }
    }
    guard state.definitionID == definition.id,
      definition.evolutionTree.contains(where: { $0.id == state.stageID }),
      Set(state.stats.keys) == Set(definition.statDefinitions.map(\.id)),
      state.stats.values.allSatisfy({ $0.isFinite && (0...100).contains($0) }),
      state.birthDate <= state.lastUpdated,
      state.careLog.allSatisfy({
        $0.seconds.isFinite && $0.seconds >= 0 && $0.weightedHealth.isFinite
          && $0.weightedHealth >= 0 && $0.weightedHealth <= $0.seconds * 100 + 0.001
      })
    else {
      throw MoltError.invalid(
        "Saved pet does not match its definition or contains invalid values. Your save has been preserved."
      )
    }
  }
}
