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
      status?.button?.image = NSImage(
        systemSymbolName: "leaf", accessibilityDescription: "Molt companion")
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
    add("Open Molt", #selector(openHome), to: menu, key: "o")
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
    for (flag, tab) in [("--hub", "Hub"), ("--play", "Play"), ("--sessions", "Sessions"), ("--chat", "Ask Molt"), ("--settings", "Settings")]
    where CommandLine.arguments.contains(flag) { controller.tab = tab }
    controller.healthEnabled = true
    controller.refreshHealth()
    Thread.sleep(forTimeInterval: 0.3)
    controller.refreshHealth()
    if controller.tab == "Sessions" {
      controller.hub.sessions.archive = false
      controller.hub.sessions.enabled = true
      let deadline = Date().addingTimeInterval(60)
      repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) } while controller.hub.sessions.busy && Date() < deadline
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
    let coordinator = IslandCoordinator(controller: controller, preview: true)
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
