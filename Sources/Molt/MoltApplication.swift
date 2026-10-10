import AppKit
import Darwin
import MoltCore
import SwiftUI

final class FloatingPanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var controller: PetController?
  private var island: IslandCoordinator?
  private var status: NSStatusItem?
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
      let controller = try PetController()
      self.controller = controller
      status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      status?.button?.image = MoltIcon.menuBarImage()
      controller.onChange = { [weak self] in self?.rebuildMenu() }
      controller.onGame = { [weak self] in self?.show("Play") }
      island = IslandCoordinator(controller: controller)
      rebuildMenu()
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
    add("Settings…", #selector(openSettings), to: menu, key: ",")
    menu.addItem(.separator())
    add(
      controller.organization.consent.paused ? "Resume app tracking" : "Pause app tracking",
      #selector(toggleTracking), to: menu)
    if controller.error != nil { add("Save needs attention…", #selector(openHome), to: menu) }
    add("Quit Molt", #selector(quit), to: menu, key: "q")
    status?.menu = menu
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
  @objc private func toggleTracking() {
    controller?.updateOrganization { $0.consent.paused.toggle() }
    controller?.configureContext()
    rebuildMenu()
  }
  @objc private func quit() { NSApp.terminate(nil) }
  func applicationWillTerminate(_ notification: Notification) {
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
    ] where CommandLine.arguments.contains(flag) { controller.tab = tab }
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
    let coordinator = IslandCoordinator(controller: controller, preview: true)
    if CommandLine.arguments.contains("--lens-permission") { coordinator.lens.needsPermission = true }
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
