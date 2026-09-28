import AppKit
import MoltCore
import SwiftUI

@MainActor final class PetController: ObservableObject {
  @Published var state: PetState
  @Published var definition: PetDefinition
  @Published var mood = "idle"
  @Published var message = "A little company, while you do your thing."
  @Published var error: String?
  @Published var healthEnabled: Bool {
    didSet {
      UserDefaults.standard.set(healthEnabled, forKey: "systemHealthEnabled")
      if !healthEnabled { monitor = nil } else { monitor = SystemHealthMonitor() }
    }
  }
  @Published var organization = Organization()
  @Published var organizationError: String?
  @Published var game: GameSession?
  @Published var health = SystemHealthSnapshot()
  @Published var tab = "Today"
  @Published var petVisible = true
  @Published var dashboardVisible = true
  let clock = CompanionClock()
  let contexts = ContextAdapters()
  let organizationStore: OrganizationStore
  var onGame: (() -> Void)?
  var onBringBack: (() -> Void)?
  var onCapture: (() -> Void)?
  var onRecoverPet: (() -> Void)?
  let store: PetStore
  private var monitor: SystemHealthMonitoring?
  private let brain: PetBrain = RuleBasedBrain()
  private var timer: Timer?
  private var reaction: Task<Void, Never>?
  var onChange: (() -> Void)?
  var stage: EvolutionStage { definition.evolutionTree.first { $0.id == state.stageID }! }
  var age: Int {
    max(
      0,
      Int(
        (Date().timeIntervalSince(state.birthDate) - (state.companion?.pausedSeconds ?? 0)) / 86400)
    )
  }
  var score: Double { state.careScore(at: Date()) }
  var definitionsDirectory: URL { store.directory.appendingPathComponent("Definitions") }
  init(directory supplied: URL? = nil) throws {
    let directory =
      try supplied
      ?? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Molt")
    store = PetStore(directory: directory)
    let bundled = try PetStore.definition(at: BundledDefinitions.url("molt"))
    organizationStore = try OrganizationStore(
      url: directory.appendingPathComponent("organization.sqlite"))
    let loadedOrganization = try organizationStore.load()
    let saved = try store.load()
    let resolved: PetDefinition
    if let saved {
      let custom = directory.appendingPathComponent("Definitions/\(saved.definitionID).json")
      let safeID =
        saved.definitionID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
      guard safeID else { throw MoltError.invalid("Invalid saved definition identifier.") }
      if let embedded = saved.definitionSnapshot {
        try embedded.validate()
        resolved = embedded
      } else if FileManager.default.fileExists(atPath: custom.path) {
        resolved = try PetStore.definition(at: custom)
      } else if let url = try? BundledDefinitions.url(saved.definitionID) {
        resolved = try PetStore.definition(at: url)
      } else {
        throw MoltError.invalid(
          "Missing definition \(saved.definitionID). Restore it in \(directory.path)/Definitions. Your pet has not been reset."
        )
      }
      try PetStore.validate(saved, definition: resolved)
      state = saved
    } else {
      resolved = bundled
      state = PetState(definition: bundled)
    }
    definition = resolved
    healthEnabled =
      supplied == nil
      ? (UserDefaults.standard.object(forKey: "systemHealthEnabled") as? Bool ?? true) : false
    if state.definitionSnapshot == nil { state.definitionSnapshot = resolved }
    organization = loadedOrganization
    if state.companion == nil {
      state.companion = CompanionState(now: state.birthDate)
      state.companion?.unlockedForms = [state.stageID]
    }
    game = state.companion?.game
    if healthEnabled { monitor = SystemHealthMonitor() }
    try FileManager.default.createDirectory(
      at: definitionsDirectory, withIntermediateDirectories: true)
    contexts.interval = { [weak self] interval in
      guard let self else { return }
      self.organization.intervals.append(interval)
      let cutoff = Date().addingTimeInterval(
        -Double(self.organization.consent.retentionDays) * 86400)
      self.organization.intervals.removeAll { $0.end < cutoff }
    }
    contexts.onSleep = { [weak self] in
      self?.changeFocus("pause")
      self?.saveOrganization()
    }
    contexts.onWake = { [weak self] in self?.tick() }
    if supplied == nil { configureContext() }
    // Never count an unknown offline gap as focused work.
    for index in organization.sessions.indices where organization.sessions[index].finished == nil {
      organization.sessions[index].lastResumed = nil
    }
    tick()
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
  }
  @objc private func woke() { tick() }
  func tick(event: String? = nil) {
    let now = self.now
    state.companion?.clockCorrected = Date() < (state.companion?.lastReliableClock ?? .distantPast)
    state.companion?.lastReliableClock = now
    Simulation.advance(&state, definition: definition, to: now)
    let snapshot = healthEnabled ? monitor?.currentSnapshot() : nil
    health = snapshot ?? SystemHealthSnapshot()
    let events =
      snapshot.map { Simulation.applyHealth($0, state: &state, definition: definition, now: now) }
      ?? []
    var evolved = false
    // Resolve every eligible stage on offline catch-up, without depending on another tick.
    for _ in definition.evolutionTree {
      let action = brain.decideAction(
        state: state, definition: definition, event: nil, snapshot: snapshot, now: now)
      if case .evolve(let id) = action {
        state.companion?.pendingEvolution = id
        evolved = true
        message = "A new form is ready. Visit the discovery book when you like."
        mood = "happy"
        break
      } else {
        if case .mood(let value) = action { mood = value }
        break
      }
    }
    if let event = event ?? events.first,
      case .speak(let line) = brain.decideAction(
        state: state, definition: definition, event: event, snapshot: snapshot, now: now)
    {
      message = line
    } else if events.isEmpty && !evolved {
      message =
        definition.personality.dialogue[mood]?.first ?? [
          "sleepy": "A little rest would be lovely.", "hungry": "Is it snack time yet?",
          "sweating": "Your Mac is warm. I’m taking it slow.",
        ][mood] ?? definition.personality.dialogue["idle"]?.first ?? "Happy to be here."
    }
    ActivityEngine.reconcile(state: &state, now: now)
    if let active = companion.active {
      mood =
        active.kind == "rest"
        ? "sleeping" : active.kind.hasPrefix("explore") ? "walking" : "thinking"
    } else if companion.preferences.sleeping(at: now) {
      mood = "sleeping"
    }
    contexts.refreshCalendar(selected: organization.consent.selectedCalendars)
    contexts.flush()
    organization.intervals = ActivityPolicy.retained(
      organization.intervals, preferences: organization.consent, now: Date())
    for index in organization.sessions.indices
    where organization.sessions[index].finished == nil && organization.sessions[index].target > 0
      && organization.sessions[index].duration(at: now) >= organization.sessions[index].target
    {
      organization.sessions[index].elapsed = organization.sessions[index].target
      organization.sessions[index].lastResumed = nil
      organization.sessions[index].finished = now
      message = "Your focus session is complete. Time for a gentle pause."
    }
    for index in organization.sessions.indices
    where organization.sessions[index].finished == nil
      && organization.sessions[index].lastResumed != nil
    {
      organization.sessions[index].elapsed = organization.sessions[index].duration(at: now)
      organization.sessions[index].lastResumed = now
    }
    saveOrganization()
    rewardFinishedFocus()
    save()
    onChange?()
  }
  func interact(_ interaction: Interaction) {
    tick()
    if let reason = blockReason(interaction) {
      error = reason
      return
    }
    var next = state
    guard ActivityEngine.perform(interaction, state: &next, now: now), commit(next) else { return }
    mood =
      interaction.id == "rest"
      ? "sleeping"
      : interaction.id == "feed" || interaction.id == "snack"
        ? "eating" : interaction.id == "water" ? "drinking" : "happy"
    let lines =
      definition.personality.dialogue[interaction.id] ?? [
        "A small moment, just for us.", "Happy to have you here.",
      ]
    let line =
      lines.first { !companion.dialogueHistory.suffix(3).contains($0) } ?? lines.first ?? "Hello."
    message = line
    state.companion?.dialogueHistory.append(line)
    state.companion?.dialogueHistory = Array(companion.dialogueHistory.suffix(8))
    save()
    if companion.preferences.sound && !companion.preferences.quiet(at: now) {
      NSSound(named: "Pop")?.play()
    }
  }
  func save() {
    do {
      try store.save(state)
      error = nil
    } catch { self.error = "Could not save your pet: \(error.localizedDescription)" }
  }
  func importDefinition() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let pack = try SpeciesPack.load(at: url)
      let definition = pack.definition
      guard definition.id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
        throw MoltError.invalid(
          "Use letters, numbers, hyphens or underscores for the definition ID.")
      }
      let alert = NSAlert()
      alert.messageText = "Start a new \(definition.name)?"
      alert.informativeText =
        "Your current pet will be archived in Application Support/Molt. A new companion starts at day zero. Author: \(definition.author ?? "Unspecified"). Schema: \(definition.schemaVersion ?? 1). Custom atlas: \(pack.atlas == nil ? "No" : "Yes")."
      alert.addButton(withTitle: "Start new companion")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(state).write(
        to: store.directory.appendingPathComponent(
          "archive-\(state.id)-\(Int(Date().timeIntervalSince1970)).json"), options: .atomic)
      var next = PetState(definition: definition)
      next.companion = CompanionState(now: Date())
      next.companion?.name = definition.name
      if let atlas = pack.atlas, let file = definition.spriteAtlas {
        let folder = store.directory.appendingPathComponent("Assets").appendingPathComponent(
          next.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try atlas.write(to: folder.appendingPathComponent(file), options: .atomic)
      }
      try pack.definitionData.write(
        to: definitionsDirectory.appendingPathComponent("\(definition.id).json"), options: .atomic)
      try store.save(next)
      self.definition = definition
      state = next
      tick()
    } catch { self.error = error.localizedDescription }
  }
}

enum BundledDefinitions {
  static func url(_ name: String) throws -> URL {
    let bundle: Bundle
    if Bundle.main.bundleURL.pathExtension == "app" {
      guard let resources = Bundle.main.resourceURL,
        let packaged = Bundle(url: resources.appendingPathComponent("Molt_Molt.bundle"))
      else {
        throw MoltError.invalid(
          "Molt’s bundled definitions are missing. Reinstall the application.")
      }
      bundle = packaged
    } else {
      bundle = .module
    }
    guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Resources")
    else {
      throw MoltError.invalid("Bundled definition \(name) is missing.")
    }
    return url
  }
}
