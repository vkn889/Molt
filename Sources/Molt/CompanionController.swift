import AppKit
import MoltCore
import ServiceManagement
import SwiftUI

extension PetController {
  var companion: CompanionState { state.companion ?? CompanionState(now: state.birthDate) }
  var atlasURL: URL? {
    definition.spriteAtlas.map {
      store.directory.appendingPathComponent("Assets").appendingPathComponent(state.id.uuidString)
        .appendingPathComponent($0)
    }
  }
  var petName: String { companion.name }
  var now: Date { clock.now(floor: companion.lastReliableClock) }
  func changeCompanion(_ update: (inout CompanionState) -> Void) {
    var next = state
    var c = companion
    update(&c)
    next.companion = c
    commit(next)
  }
  @discardableResult func commit(_ next: PetState) -> Bool {
    do {
      try store.save(next)
      state = next
      error = nil
      onChange?()
      return true
    } catch {
      self.error = "Could not save changes: \(error.localizedDescription)"
      return false
    }
  }
  func blockReason(_ action: Interaction, at date: Date? = nil) -> String? {
    ActivityEngine.reason(action, state: state, at: date ?? now)
  }
  func cooldownLabel(_ action: Interaction, at date: Date) -> String {
    let seconds = max(
      0, companion.cooldowns[ActivityEngine.group(for: action)]?.timeIntervalSince(date) ?? 0)
    return seconds > 0
      ? (seconds < 60 ? "\(Int(ceil(seconds)))s wait" : "\(Int(ceil(seconds / 60)))m wait")
      : (blockReason(action, at: date) == nil ? "Ready" : "Unavailable")
  }
  func startActivity(
    kind: String, title: String, seconds: Double, group: String, cooldown: Double, energy: Double
  ) {
    tick()
    var next = state
    if let reason = ActivityEngine.start(
      kind: kind, title: title, seconds: seconds, group: group, cooldown: cooldown, energy: energy,
      state: &next, now: now)
    {
      error = reason
      return
    }
    if commit(next) {
      mood = kind.hasPrefix("explore") ? "walking" : "thinking"
      message = title
    }
  }
  func stopActivity() {
    var next = state
    ActivityEngine.reconcile(state: &next, now: now)
    if let id = next.companion?.active?.id {
      _ = ActivityEngine.finish(id: id, state: &next, now: now, success: false)
    }
    next.companion?.game = nil
    commit(next)
    mood = "idle"
  }
  func startGame(_ kind: String, practice: Bool, easy: Bool) {
    if let existing = companion.game, !existing.completed {
      game = existing
      onGame?()
      error = "Your previous round is saved. Finish or end it before starting another."
      return
    }
    tick()
    var next = state
    if !practice {
      let training = kind.hasPrefix("lesson:")
      let reason = ActivityEngine.start(
        kind: training ? kind : "game:\(kind)",
        title: training ? "Lesson: \(kind.dropFirst(7))" : "\(kind.capitalized) game", seconds: 0,
        group: training ? "training" : "game:\(kind)", cooldown: training ? 1200 : 900,
        energy: training ? 8 : 5, state: &next, now: now)
      if let reason {
        error = reason
        return
      }
    }
    let session = GameSession(
      kind: kind.hasPrefix("lesson:") ? "rhythm" : kind, practice: practice,
      activityID: practice ? nil : next.companion?.active?.id, easy: easy)
    next.companion?.game = session
    if commit(next) {
      game = session
      onGame?()
    }
  }
  func updateGame(_ session: GameSession) {
    var next = state
    var session = session
    if session.won && !session.completed {
      if let id = session.activityID { _ = ActivityEngine.finish(id: id, state: &next, now: now) }
      session.completed = true
      message = session.practice ? "A lovely practice round." : "A new little memory together."
      mood = "celebrating"
    }
    next.companion?.game = session
    if commit(next) { game = session }
  }
  func resumeGame() {
    game = companion.game
    if game != nil { onGame?() }
  }
  func evolve() {
    guard let id = companion.pendingEvolution else { return }
    var next = state
    next.stageID = id
    next.companion?.pendingEvolution = nil
    if next.companion?.unlockedForms.contains(id) == false {
      next.companion?.unlockedForms.append(id)
    }
    next.companion?.remember(
      "\(petName) grew into \(definition.evolutionTree.first { $0.id == id }?.displayName ?? id), after \(age) active days and a care average of \(Int(score)).",
      kind: "evolution", at: now)
    commit(next)
    mood = "celebrating"
  }
  func saveOrganization() {
    do {
      try organizationStore.save(organization)
      organizationError = nil
    } catch { organizationError = error.localizedDescription }
  }
  func updateOrganization(_ change: (inout Organization) -> Void) {
    var next = organization
    change(&next)
    do {
      try organizationStore.save(next)
      organization = next
      organizationError = nil
    } catch { organizationError = error.localizedDescription }
  }
  func configureContext() {
    contexts.configure(organization.consent)
    contexts.refreshCalendar(selected: organization.consent.selectedCalendars)
    contexts.schedule(
      organization.reminders, enabled: organization.consent.notifications,
      quiet: companion.preferences, name: petName)
  }
  func capture(_ text: String, kind: String) {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    updateOrganization { o in
      if kind == "note" {
        o.notes.append(Note(String(value.prefix(70)), body: value))
      } else {
        o.tasks.append(WorkTask(value))
      }
    }
  }
  func focus(minutes: Int, task: UUID? = nil) {
    guard !organization.sessions.contains(where: { $0.finished == nil }) else {
      error = "A focus session is already open."
      return
    }
    updateOrganization {
      $0.sessions.append(FocusSession(now: now, minutes: minutes, taskID: task))
    }
    mood = "thinking"
  }
  func changeFocus(_ action: String) {
    guard let index = organization.sessions.firstIndex(where: { $0.finished == nil }) else {
      return
    }
    let date = now
    updateOrganization { o in
      switch action {
      case "pause": o.sessions[index].pause(at: date)
      case "resume": o.sessions[index].lastResumed = date
      case "extend": o.sessions[index].target += 300
      default: o.sessions[index].stop(at: date)
      }
    }
    rewardFinishedFocus()
  }
  func rewardFinishedFocus() {
    var next = state
    let pending = organization.sessions.filter {
      $0.finished != nil && $0.petRewardDelivered != true
    }
    guard !pending.isEmpty else { return }
    for session in pending where !(next.companion?.rewardedIDs.contains(session.id) ?? false) {
      if var c = next.companion {
        let amount = min(20, Int(session.elapsed / 300))
        ActivityEngine.reward(&c, amount: amount, id: session.id, now: session.finished!)
        if amount > 0 {
          c.remember(
            "Shared \(Int(session.elapsed / 60)) minutes of focus.", kind: "focus",
            at: session.finished!)
        }
        next.companion = c
      }
    }
    // Pet credit is durable before acknowledging delivery in the utility database.
    // A crash between writes retries safely through the pet's reward ledger.
    guard commit(next) else { return }
    let ids = Set(pending.map(\.id))
    updateOrganization { o in
      for index in o.sessions.indices where ids.contains(o.sessions[index].id) {
        o.sessions[index].petRewardDelivered = true
      }
    }
  }
  func export(_ kind: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "molt-\(kind).json"
    panel.allowedContentTypes = [.json]
    panel.message =
      kind == "pet"
      ? "Includes your pet, profile, care history, memories, and cooldowns. No tasks, notes, calendar, or app activity."
      : kind == "outfit"
        ? "Includes cosmetic appearance only."
        : kind == "species"
          ? "Includes this species definition only. No private history."
          : kind == "journal"
            ? "Includes the pet memory journal only."
            : "Includes tasks, notes, reminders, routines and focus. Does not include calendar or app activity."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data: Data
      switch kind {
      case "pet":
        data = try encoder.encode(
          PetArchive(state: state, atlas: try atlasURL.map { try Data(contentsOf: $0) }))
      case "outfit": data = try encoder.encode(companion.appearance)
      case "species": data = try encoder.encode(definition)
      case "journal": data = try encoder.encode(companion.memories)
      default:
        var copy = organization
        copy.intervals = []
        copy.consent = ConsentPreferences()
        data = try encoder.encode(copy)
      }
      try data.write(to: url, options: .atomic)
    } catch { self.error = error.localizedDescription }
  }
  func importOutfit() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let outfit = try JSONDecoder().decode(Appearance.self, from: Data(contentsOf: url))
      guard ["sage", "ocean", "sunset", "violet"].contains(outfit.palette),
        companion.inventory.contains(outfit.accessory)
      else { throw MoltError.invalid("Unsupported palette or an accessory you have not unlocked.") }
      changeCompanion { $0.appearance = outfit }
    } catch { self.error = error.localizedDescription }
  }
  func restoreBackup() {
    let alert = NSAlert()
    alert.messageText = "Restore the previous pet save?"
    alert.informativeText =
      "The current file will be preserved as a recovery archive. Organization data is unaffected."
    alert.addButton(withTitle: "Restore")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      let data = try Data(
        contentsOf: store.directory.appendingPathComponent("pet-state.backup.json"))
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let saved = try decoder.decode(PetState.self, from: data)
      try PetStore.validate(saved, definition: definition)
      try Data(contentsOf: store.stateURL).write(
        to: store.directory.appendingPathComponent("recovery-\(UUID()).json"), options: .atomic)
      commit(saved)
    } catch { self.error = error.localizedDescription }
  }
  func setLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch { self.error = "Login setting: \(error.localizedDescription)" }
  }
}

extension PetController {
  func importPet() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max < 20_000_000
      else { throw MoltError.invalid("Pet archive is too large.") }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let data = try Data(contentsOf: url)
      let archive = try? decoder.decode(PetArchive.self, from: data)
      if let archive, archive.formatVersion != 1 {
        throw MoltError.invalid("Unsupported pet archive version.")
      }
      var restored = try archive?.state ?? decoder.decode(PetState.self, from: data)
      let species =
        try restored.definitionSnapshot
        ?? PetStore.definition(at: BundledDefinitions.url(restored.definitionID))
      try species.validate()
      try PetStore.validate(restored, definition: species)
      if let atlas = archive?.atlas { try SpeciesPack.validateAtlas(atlas) }
      let alert = NSAlert()
      alert.messageText = "Restore \(restored.companion?.name ?? species.name)?"
      alert.informativeText =
        "Your current pet will be archived first. Tasks, notes, and activity history will not change."
      alert.addButton(withTitle: "Restore pet")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(state).write(
        to: store.directory.appendingPathComponent("archive-\(state.id)-\(UUID()).json"),
        options: .atomic)
      if restored.companion == nil { restored.companion = CompanionState(now: restored.birthDate) }
      restored.schemaVersion = 2
      restored.definitionSnapshot = species
      if let atlas = archive?.atlas, let name = species.spriteAtlas {
        let root = store.directory.appendingPathComponent("Assets").appendingPathComponent(
          restored.id.uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try atlas.write(to: root.appendingPathComponent(name), options: .atomic)
      }
      try store.save(restored)
      definition = species
      state = restored
      game = restored.companion?.game
      tick()
    } catch { self.error = error.localizedDescription }
  }
}
