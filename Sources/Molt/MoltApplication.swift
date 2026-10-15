import AppKit
import Darwin
import MoltCore
import SwiftUI

final class FloatingPanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var controller: PetController?
  private var island: IslandCoordinator?
  private var tour: Onboarding?
  private var status: NSStatusItem?
  /// Left-click opens the popup; right-click or Control-click, the classic menu.
  private let popover = NSPopover()
  private var menu = NSMenu()
  private var lockDescriptor: Int32 = -1
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    do {
      let root = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Molt")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      lockDescriptor = Darwin.open(
        root.appendingPathComponent(".instance-lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
      guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
        NSApp.terminate(nil)
        return
      }
      // A new install has no pet yet; an update or a relaunch already has one.
      let existing = FileManager.default.fileExists(atPath: root.appendingPathComponent("pet-state.json").path)
      let controller = try PetController()
      self.controller = controller
      status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      status?.button?.image = MoltIcon.menuBarImage()
      status?.button?.target = self
      status?.button?.action = #selector(statusClicked)
      status?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      popover.behavior = .transient
      popover.animates = true
      let host = NSHostingController(rootView: MenuBarPopup(controller: controller) { [weak self] action in self?.popupAction(action) })
      host.sizingOptions = .preferredContentSize
      popover.contentViewController = host
      controller.onChange = { [weak self] in self?.rebuildMenu() }
      controller.onGame = { [weak self] in self?.show("Play") }
      let island = IslandCoordinator(controller: controller)
      self.island = island
      rebuildMenu()
      SettingsWindow.shared.controller = controller
      SettingsWindow.shared.coordinator = island
      SettingsWindow.shared.replayTour = { [weak self] in self?.replayTour() }
      NotificationCenter.default.addObserver(forName: .moltOpenSettings, object: nil, queue: .main) { note in
        let section = note.object as? String
        Task { @MainActor in SettingsWindow.shared.show(section) }
      }
      let tour = Onboarding(controller: controller, coordinator: island)
      tour.menuBarFrame = { [weak self] in self?.status?.button?.window?.frame }
      self.tour = tour
      // Molt wakes up when you open it after quitting, and on its very first launch. It doesn't
      // when it never quit, such as after a crash or when the Mac restarts it on login.
      let defaults = UserDefaults.standard
      let firstRun = !existing && !defaults.bool(forKey: "moltTourDone")
      // Updating means quitting the old version, so a new version's first launch counts too.
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
      let updated = defaults.string(forKey: "moltLastVersion") != version
      let afterQuit = defaults.bool(forKey: "moltQuitByUser") || updated
      defaults.set(false, forKey: "moltQuitByUser")
      defaults.set(version, forKey: "moltLastVersion")
      // What's new is marked for two weeks after each update.
      if updated { defaults.set(Date(), forKey: "moltNewSince") }
      if firstRun {
        island.boot { tour.start() }
      } else if afterQuit && island.prefs.wakeAnimation {
        island.boot()
      }
    } catch { showRecovery(error) }
  }
  private func showRecovery(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Molt could not open your companion"
    alert.informativeText =
      "\(error.localizedDescription)\n\nThe original files are preserved. You can open the data folder to restore a backup. No pet has been reset."
    alert.addButton(withTitle: "Open data folder")
    alert.addButton(withTitle: "Quit")
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
          "Library/Application Support/Molt"))
    }
    NSApp.terminate(nil)
  }
  func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }
  private func rebuildMenu() {
    guard let controller else { return }
    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    let title = NSMenuItem(
      title: "\(controller.petName) · Day \(controller.age + 1)", action: nil, keyEquivalent: "")
    title.isEnabled = false
    menu.addItem(title)
    if controller.hub.actions.recording != nil {
      add("Stop screen recording", #selector(stopRecording), to: menu)
      menu.addItem(.separator())
    }
    add("Open Molt", #selector(openHome), to: menu, key: "o")
    add("Ask about screen", #selector(openLens), to: menu, key: "l")
    add("Play with \(controller.petName)", #selector(openPlay), to: menu)
    add("Settings…", #selector(openSettingsWindow), to: menu, key: ",")
    menu.addItem(.separator())
    add(
      controller.organization.consent.paused ? "Resume app tracking" : "Pause app tracking",
      #selector(toggleTracking), to: menu)
    if controller.error != nil { add("Save needs attention…", #selector(openHome), to: menu) }
    add("Quit Molt", #selector(quit), to: menu, key: "q")
    self.menu = menu
  }
  @objc private func statusClicked() {
    guard let button = status?.button else { return }
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      popover.performClose(nil)
      rebuildMenu()
      status?.menu = menu
      button.performClick(nil)
      status?.menu = nil
    } else if popover.isShown {
      popover.performClose(nil)
    } else {
      NSApp.activate(ignoringOtherApps: true)
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }
  private func popupAction(_ action: String) {
    popover.performClose(nil)
    switch action {
    case "home": openHome()
    case "lens": openLens()
    case "play": openPlay()
    case "tracking": toggleTracking()
    case "settings": SettingsWindow.shared.show()
    case "agents": UserDefaults.standard.set("Live", forKey: "agentsTab"); show("Agents")
    case "quit": quit()
    default: break
    }
  }
  private func add(_ title: String, _ selector: Selector, to menu: NSMenu, key: String = "") {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
    item.target = self
    menu.addItem(item)
  }
  private func show(_ tab: String) {
    controller?.tab = tab
    island?.open()
  }
  @objc private func openHome() { show("Notch") }
  @objc private func openLens() { island?.startLens() }
  @objc private func stopRecording() { controller?.hub.actions.stopRecording() }
  @objc private func openPlay() { show("Play") }
  @objc private func openSettings() { show("Settings") }
  @objc private func openSettingsWindow() { SettingsWindow.shared.show() }
  @objc private func toggleTracking() {
    controller?.updateOrganization { $0.consent.paused.toggle() }
    controller?.configureContext()
    rebuildMenu()
  }
  @objc private func quit() {
    UserDefaults.standard.set(true, forKey: "moltQuitByUser")
    NSApp.terminate(nil)
  }
  /// From Settings: show the tour again.
  func replayTour() { island?.boot { [weak self] in self?.tour?.start() } }
  func applicationWillTerminate(_ notification: Notification) {
    if let clipboard = controller?.hub.clipboard, clipboard.clearOnQuit { clipboard.clear() }
    controller?.changeFocus("pause")
    controller?.tick()
    controller?.saveOrganization()
    if lockDescriptor >= 0 { close(lockDescriptor) }
  }
}
@main struct MoltApplication {
  @MainActor static func main() {
    let app = NSApplication.shared
    if CommandLine.arguments.contains("--verify-model-install") {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "molt-install-check-\(UUID())")
      let manager = ModelManager(directory: root)
      Task {
        defer { try? FileManager.default.removeItem(at: root) }
        manager.install()
        while manager.busy { try? await Task.sleep(nanoseconds: 250_000_000) }
        let ready = manager.ready
        print("Fresh model installation: \(manager.message)")
        try? FileManager.default.removeItem(at: root)
        exit(ready ? 0 : 1)
      }
      app.run()
      return
    }
    if let index = CommandLine.arguments.firstIndex(of: "--verify-local-ai"),
      CommandLine.arguments.count > index + 1
    {
      let model = URL(fileURLWithPath: CommandLine.arguments[index + 1])
      let manager = ModelManager(directory: FileManager.default.temporaryDirectory)
      Task {
        do {
          let provider = ManagedLocalProvider(executable: manager.executable, modelURL: model)
          var response = ""
          for try await token in provider.stream(
            model: ManagedModel.id,
            messages: [.init(role: "user", content: "Say hello in one short sentence.")])
          { response += token }
          guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InferenceError.malformed
          }
          print("Packaged local worker ready: \(response)")
          exit(0)
        } catch {
          fputs("Local worker failed: \(error)\n", stderr)
          exit(1)
        }
      }
      app.run()
      return
    }
    if let index = CommandLine.arguments.firstIndex(of: "--cloud-selftest"), CommandLine.arguments.count > index + 4 {
      // Development check of the realtime client against the live service, using two test accounts.
      let args = Array(CommandLine.arguments[(index + 1)...(index + 4)])
      Task { @MainActor in
        let ok = await CloudSelfTest.run(emailA: args[0], passwordA: args[1], emailB: args[2], passwordB: args[3])
        exit(ok ? 0 : 1)
      }
      app.run()
      return
    }
    if let index = CommandLine.arguments.firstIndex(of: "--render-iconset"),
      CommandLine.arguments.count > index + 1
    {
      do { try MoltIcon.writeIconset(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) } catch {
        fputs("Icon failed: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    if CommandLine.arguments.contains("--chat-selftest") {
      // Development check of Chat and Lens against the services on this Mac. Uses its own folder
      // and the debug build's own preferences.
      Task { @MainActor in
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("molt-chat-\(UUID())")
        let assistant = AssistantController(directory: root)
        // Like a fresh setup with a cloud service chosen and no key: Lens should still answer.
        assistant.service = "openrouter"
        print("openrouter ready: \(assistant.ready)")
        if let stream = assistant.answer([InferenceMessage(role: "user", content: "Reply with just: Lens works")]) {
          var text = ""
          do { for try await token in stream { text += token } } catch { text = "error: \(error.localizedDescription)" }
          print("lens fallback: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        } else {
          print("lens fallback: none")
        }
        assistant.service = "ollama"
        for _ in 0..<60 where !assistant.ready { try? await Task.sleep(nanoseconds: 250_000_000) }
        print("ollama ready: \(assistant.ready) model: \(assistant.selectedModel)")
        assistant.draft = "Reply with just: Chat works"
        assistant.send()
        for _ in 0..<240 {
          try? await Task.sleep(nanoseconds: 250_000_000)
          if !assistant.running, assistant.conversation.last?.role == "assistant" { break }
        }
        print("chat: \(assistant.conversation.last?.content ?? "(none)") | status: \(assistant.status)")
        exit(0)
      }
      app.run()
      return
    }
    if CommandLine.arguments.contains("--agents-selftest") {
      // Development check of the agent bridge: runs only the loopback server, prints its token,
      // and answers each approval after a second so the reply path can be exercised.
      Task { @MainActor in
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("molt-agents-\(UUID())")
        let agents = AgentController(directory: root)
        agents.saved.terminalFirst = false
        // Never touches your Claude Code settings.
        agents.start(upgradingHooks: false)
        print("TOKEN " + (UserDefaults.standard.string(forKey: "agentToken") ?? ""))
        fflush(stdout)
        for _ in 0..<200 {
          try? await Task.sleep(nanoseconds: 100_000_000)
          for item in agents.pending where Date().timeIntervalSince(item.received) > 0.8 {
            if item.isQuestion {
              // Picks the last option of each question, so the answer is clearly Molt's.
              agents.answer(item.id, choices: Dictionary(uniqueKeysWithValues: item.questions.map { ($0.question, [$0.options.last?.label ?? "yes"]) }))
            } else {
              agents.allow(item.id)
            }
          }
        }
        print("LIVE " + agents.live.values.map { "\($0.agent):\($0.status.rawValue):\($0.project)" }.sorted().joined(separator: ","))
        print("FINISHED \(agents.finished.count) TASKS \(agents.saved.tasksFinished)")
        exit(0)
      }
      app.run()
      return
    }
    if let index = CommandLine.arguments.firstIndex(of: "--render-creature"),
      CommandLine.arguments.count > index + 1
    {
      do { try renderCreature(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) } catch {
        fputs("Creature failed: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
      CommandLine.arguments.count > index + 1
    {
      do { try renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) } catch {
        fputs("Preview failed: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
  static func argument(_ flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.count > index + 1 else { return nil }
    return CommandLine.arguments[index + 1]
  }
  /// Renders Molt frame by frame as transparent PNGs, for videos: `--render-creature <folder>
  /// --mood happy --frames 60 --fps 30 --size 280 --outfit hat,scarf --shell claude --palette sage`.
  @MainActor static func renderCreature(to folder: URL) throws {
    NSApp.setActivationPolicy(.accessory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let mood = argument("--mood") ?? "idle"
    let frames = Int(argument("--frames") ?? "60") ?? 60
    let fps = Double(argument("--fps") ?? "30") ?? 30
    let side = CGFloat(Double(argument("--size") ?? "280") ?? 280)
    var appearance = Appearance()
    appearance.palette = argument("--palette") ?? "sage"
    if let outfit = argument("--outfit") { appearance.outfit = outfit.split(separator: ",").map(String.init) }
    let shell = argument("--shell").flatMap { AgentKind.find($0) == nil ? nil : MoltTheme.agent($0) }
    let pokeAt = argument("--poke").flatMap(Double.init)
    let walking = CommandLine.arguments.contains("--walking")
    // Molt fills the middle of a larger transparent square, leaving room for particles.
    let canvas = side * 2.2
    for frame in 0..<frames {
      let t = 1000 + Double(frame) / fps
      let poked = pokeAt.map { Date(timeIntervalSinceReferenceDate: 1000 + $0) }
      let view = CreatureView(appearance: appearance, mood: mood, walking: walking, shell: shell, poked: poked, followsPointer: false, clock: t)
        .frame(width: side, height: side * 13 / 14)
        .frame(width: canvas, height: canvas)
      let host = NSHostingView(rootView: view)
      host.frame = NSRect(x: 0, y: 0, width: canvas, height: canvas)
      let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.backgroundColor = .clear
      window.isOpaque = false
      window.contentView = host
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw MoltError.invalid("No bitmap.") }
      host.cacheDisplay(in: host.bounds, to: rep)
      guard let data = rep.representation(using: .png, properties: [:]) else { throw MoltError.invalid("No PNG.") }
      try data.write(to: folder.appendingPathComponent(String(format: "frame-%04d.png", frame)), options: .atomic)
    }
    print("Rendered \(frames) frames to \(folder.path)")
  }
  /// A terminal error to show off Lens in previews.
  static func demoLensImage() -> NSImage {
    NSImage(size: NSSize(width: 340, height: 300), flipped: true) { rect in
      NSColor(white: 0.11, alpha: 1).setFill()
      rect.fill()
      let mono = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
      "$ npm run dev".draw(at: NSPoint(x: 20, y: 22), withAttributes: [.font: mono, .foregroundColor: NSColor(white: 0.75, alpha: 1)])
      "TypeError: Cannot read\nproperties of undefined\n(reading 'map')".draw(
        in: NSRect(x: 20, y: 66, width: 300, height: 90), withAttributes: [.font: mono, .foregroundColor: NSColor(red: 1, green: 0.42, blue: 0.42, alpha: 1)])
      "  at TaskList\n  (TaskList.tsx:14)\n  at renderWithHooks".draw(
        in: NSRect(x: 20, y: 176, width: 300, height: 100), withAttributes: [.font: mono, .foregroundColor: NSColor(white: 0.55, alpha: 1)])
      return true
    }
  }
  @MainActor static func renderPreview(to url: URL) throws {
    NSApp.setActivationPolicy(.accessory)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "molt-preview-\(UUID())")
    let controller = try PetController(directory: root)
    controller.changeCompanion { $0.adoptionComplete = true }
    controller.organization.tasks = [
      WorkTask("Make room for one good idea"), WorkTask("A little walk outside"),
    ]
    controller.organization.tasks[0].today = true
    controller.organization.tasks[1].today = true
    controller.tab = "Notch"
    if let index = CommandLine.arguments.firstIndex(of: "--mood"), CommandLine.arguments.count > index + 1 {
      // Previews render at any hour; keep Molt awake to show the requested pose.
      controller.changeCompanion { $0.preferences.sleepStart = 0; $0.preferences.sleepEnd = 0 }
      controller.mood = CommandLine.arguments[index + 1]
    }
    for (flag, tab) in [
      ("--hub", "Hub"), ("--play", "Play"), ("--sessions", "Sessions"), ("--chat", "Ask Molt"), ("--settings", "Settings"),
      ("--molting", "Molting"), ("--lens", "Lens"), ("--health", "Health"), ("--agents", "Agents"), ("--wardrobe", "Wardrobe"),
      ("--focus", "Focus"), ("--drop", "Drop"), ("--notch-settings", "NotchSettings"), ("--add-widget", "AddWidget"),
    ] where CommandLine.arguments.contains(flag) { controller.tab = tab }
    if let value = argument("--focus-left").flatMap(Double.init) {
      // A session that started a while ago, with this many minutes left.
      controller.focus(minutes: 25)
      controller.updateOrganization { o in
        if let index = o.sessions.lastIndex(where: { $0.finished == nil }) { o.sessions[index].lastResumed = Date().addingTimeInterval(-(25 - value) * 60) }
      }
    }
    if let value = argument("--tray") {
      let folder = root.appendingPathComponent("Tray")
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      controller.hub.keep(value.split(separator: ",").map { name in
        name.hasPrefix("https") ? URL(string: String(name))! : {
          let url = folder.appendingPathComponent(String(name))
          FileManager.default.createFile(atPath: url.path, contents: Data())
          return url
        }()
      })
    }
    if let value = argument("--agents-tab") { UserDefaults.standard.set(value, forKey: "agentsTab") }
    if CommandLine.arguments.contains("--demo") {
      controller.agents.loadDemo(approval: CommandLine.arguments.contains("--approval"), request: argument("--request") ?? "command")
      controller.plans.loadDemo()
      controller.github.loadDemo()
    }
    if let value = argument("--outfit") {
      controller.changeCompanion { $0.appearance.outfit = value.split(separator: ",").map(String.init); $0.inventory += value.split(separator: ",").map(String.init) }
    }
    if let value = argument("--palette") { controller.changeCompanion { $0.appearance.palette = value } }
    if CommandLine.arguments.contains("--edit") { controller.hub.editing = true }
    if let me = controller.account.userID, CommandLine.arguments.contains("--demo-social") {
      controller.social.loadDemo(me: me, hangingOut: CommandLine.arguments.contains("--hangout"))
    }
    if CommandLine.arguments.contains("--demo-chat") {
      controller.assistant.conversation = [
        InferenceMessage(role: "user", content: "Give me a 3-step plan to study for my bio test tomorrow"),
        InferenceMessage(
          role: "assistant",
          content: "Pick your 5 shakiest topics, do a 25-minute focus round on each, then quiz yourself out loud. Sleep early!"),
      ]
      controller.assistant.status = ""
    }
    if CommandLine.arguments.contains("--signed-out") { controller.account.previewSignedOut() }
    if let index = CommandLine.arguments.firstIndex(of: "--widgets"), CommandLine.arguments.count > index + 1 {
      // For previews: a comma-separated list of kind:span, such as shortcuts:2,recorder:1,lens:1.
      controller.hub.setLayout(CommandLine.arguments[index + 1].split(separator: ",").map { entry in
        let parts = entry.split(separator: ":")
        return HubWidget(kind: String(parts[0]), span: parts.count > 1 ? Int(parts[1]) ?? 1 : 1,
          items: parts[0] == "shortcuts" ? QuickActions.defaults + ["action:dark", "action:mute", "action:lens", "action:downloads"] : [])
      })
    }
    controller.healthEnabled = true
    controller.refreshHealth()
    Thread.sleep(forTimeInterval: 0.3)
    controller.refreshHealth()
    if controller.tab == "Sessions" || (controller.tab == "Agents" && argument("--agents-tab") == "Chats") {
      controller.hub.sessions.archive = false
      controller.hub.sessions.enabled = true
      let deadline = Date().addingTimeInterval(60)
      repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) } while controller.hub.sessions.busy && Date() < deadline
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
    if let value = argument("--battery").flatMap(Double.init) {
      controller.health.values["batteryLevel"] = value
      controller.health.values["isCharging"] = 0
    }
    let coordinator = IslandCoordinator(controller: controller, preview: true)
    if let value = argument("--jump") { coordinator.jump = value }
    if let value = argument("--live") {
      coordinator.preview(live: value.split(separator: ",").compactMap { LiveKind(rawValue: String($0)) })
    }
    if CommandLine.arguments.contains("--lens-permission") { coordinator.lens.needsPermission = true }
    if CommandLine.arguments.contains("--demo-lens") {
      coordinator.lens.loadDemo(
        image: demoLensImage(),
        text: "TypeError: Cannot read properties of undefined (reading 'map') at TaskList (TaskList.tsx:14)",
        labels: ["Screenshot", "Text"],
        answer: "Your code calls .map on tasks before they've loaded, so tasks is still undefined on the first render. Start it as an empty list: useState([]), or write tasks?.map(...). Line 14 of TaskList.tsx.")
    }
    if let value = argument("--banner") {
      switch value {
      case "approval": coordinator.preview(banner: .approval(controller.agents.pending.first?.id ?? UUID()))
      case "finished": coordinator.preview(banner: .finished(controller.agents.finished.first ?? AgentController.Finished(agent: "codex", project: "website", message: "Pushed to main · 48 tests passed", duration: 252, date: Date())))
      case "habit": coordinator.preview(banner: .habit("Bash(npm test)"))
      case "wings": coordinator.preview(banner: nil)
      default: coordinator.preview(banner: .message("molt/molt · main checks failed", symbol: "xmark.octagon.fill"))
      }
    } else if CommandLine.arguments.contains("--approval") {
      coordinator.preview(banner: .approval(controller.agents.pending.first?.id ?? UUID()), expanded: true)
    }
    if let value = argument("--boot-at").flatMap(Double.init) { coordinator.preview(bootAt: value) }
    if let section = argument("--settings-window") {
      let model = SettingsModel()
      model.section = SettingsSection(rawValue: section) ?? .general
      let host = NSHostingView(rootView: SettingsRoot(model: model, controller: controller, coordinator: coordinator, prefs: coordinator.prefs, hub: controller.hub, replayTour: {})
        .frame(width: 820, height: 620).environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
      host.frame = NSRect(x: 0, y: 0, width: 820, height: 620)
      let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: .darkAqua)
      window.contentView = host
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw MoltError.invalid("No bitmap.") }
      host.cacheDisplay(in: host.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
      print("Rendered \(url.path)")
      return
    }
    if let step = argument("--tour-step").flatMap(Int.init) {
      // The tour over a plain desktop, with the open notch at the top.
      let tour = Onboarding(controller: controller, coordinator: coordinator)
      let size = coordinator.expandedSize
      let screen = CGSize(width: 1512, height: 982)
      let hole = CGRect(x: (screen.width - size.width) / 2 - 22, y: -6, width: size.width + 44, height: size.height + 12)
      tour.preview(step: step, hole: hole, molt: CGPoint(x: hole.midX - 200, y: hole.maxY + 70))
      let host = NSHostingView(rootView: ZStack(alignment: .top) {
        LinearGradient(colors: [Color(red: 0.35, green: 0.47, blue: 0.68), Color(red: 0.62, green: 0.55, blue: 0.5)], startPoint: .top, endPoint: .bottom)
        IslandView(controller: controller, coordinator: coordinator)
        OnboardingOverlay(tour: tour, controller: controller, prefs: coordinator.prefs)
      }.frame(width: screen.width, height: screen.height))
      host.frame = NSRect(origin: .zero, size: screen)
      let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = host
      host.layoutSubtreeIfNeeded()
      guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw MoltError.invalid("No bitmap.") }
      host.cacheDisplay(in: host.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
      print("Rendered \(url.path)")
      return
    }
    if CommandLine.arguments.contains("--popup") {
      let popup = NSHostingView(rootView: MenuBarPopup(controller: controller) { _ in }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.16)))
        .padding(20).background(Color(red: 0.62, green: 0.45, blue: 0.5)))
      popup.frame = NSRect(origin: .zero, size: popup.fittingSize)
      let window = NSWindow(contentRect: popup.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = popup
      popup.layoutSubtreeIfNeeded()
      guard let rep = popup.bitmapImageRepForCachingDisplay(in: popup.bounds) else { throw MoltError.invalid("No bitmap.") }
      popup.cacheDisplay(in: popup.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
      print("Rendered \(url.path)")
      return
    }
    let rootView =
      AnyView(
        ZStack(alignment: .top) {
          LinearGradient(
            colors: [Color(red: 0.35, green: 0.47, blue: 0.68), Color(red: 0.62, green: 0.55, blue: 0.5)],
            startPoint: .top, endPoint: .bottom)
          IslandView(controller: controller, coordinator: coordinator)
        })
    let view = NSHostingView(rootView: rootView)
    let size = coordinator.expandedSize
    let frame = NSRect(
      x: 0, y: 0, width: size.width + 2 * IslandCoordinator.flare + 80, height: size.height + 40)
    let window = NSWindow(
      contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.frame = frame
    view.layoutSubtreeIfNeeded()
    if CommandLine.arguments.contains("--demo-chat") {
      // Let Chat finish connecting so the snapshot shows the conversation, not "Connecting…".
      RunLoop.main.run(until: Date().addingTimeInterval(3))
      controller.assistant.status = ""
      controller.assistant.running = false
      view.layoutSubtreeIfNeeded()
    }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw MoltError.invalid("Could not allocate preview bitmap.")
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
      throw MoltError.invalid("Could not encode preview.")
    }
    try data.write(to: url, options: .atomic)
    print("Rendered \(url.path)")
  }
}
