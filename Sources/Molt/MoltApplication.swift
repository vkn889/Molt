import AppKit
import Darwin
import MoltCore
import SwiftUI

final class FloatingPanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
  private var controller: PetController?
  private var petWindow: NSPanel?
  private var detailWindow: NSWindow?
  private var gameWindow: NSWindow?
  private var captureWindow: NSWindow?
  private var status: NSStatusItem?
  private var lockDescriptor: Int32 = -1
  private var lastDisplay = -1
  private var wanderOrigin: NSPoint?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    MoltTheme.registerFont()
    do {
      let root = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Molt")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      lockDescriptor = open(
        root.appendingPathComponent(".instance-lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
      guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
        NSApp.terminate(nil)
        return
      }
      let controller = try PetController()
      self.controller = controller
      let panel = FloatingPanel(
        contentRect: NSRect(x: 100, y: 100, width: 250, height: 280),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.level = .floating
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.isMovableByWindowBackground = true
      panel.hidesOnDeactivate = false
      panel.contentView = NSHostingView(rootView: PetView(controller: controller))
      panel.delegate = self
      panel.setFrameAutosaveName("MoltPetPosition")
      petWindow = panel
      recoverPosition()
      panel.orderFrontRegardless()
      status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      status?.button?.image = NSImage(
        systemSymbolName: "leaf", accessibilityDescription: "Molt companion")
      controller.onChange = { [weak self] in
        self?.rebuildMenu()
        self?.applyPreferences()
      }
      controller.onGame = { [weak self] in self?.showGame() }
      controller.onBringBack = { [weak self] in self?.showCompanion() }
      controller.onCapture = { [weak self] in self?.showCapture() }
      controller.onRecoverPet = { [weak self] in self?.bringBack() }
      NotificationCenter.default.addObserver(
        self, selector: #selector(recoverPosition),
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
      rebuildMenu()
      applyPreferences()
      showCompanion()
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
    add("Open dashboard…", #selector(showCompanion), to: menu, key: "o")
    add("Quick capture…", #selector(showCapture), to: menu, key: "k")
    menu.addItem(.separator())
    for action in controller.definition.interactions.prefix(3) {
      let reason = controller.blockReason(action)
      let label =
        reason == nil
        ? action.name : "\(action.name) · \(controller.cooldownLabel(action, at: controller.now))"
      let item = NSMenuItem(title: label, action: #selector(interact(_:)), keyEquivalent: "")
      item.representedObject = action.id
      item.target = self
      item.isEnabled = reason == nil
      item.toolTip = reason
      menu.addItem(item)
    }
    menu.addItem(.separator())
    add("Show / hide pet", #selector(togglePet), to: menu)
    add("Bring Molt back", #selector(bringBack), to: menu)
    add(
      controller.companion.preferences.clickThrough
        ? "Restore pet interaction" : "Enable click-through", #selector(toggleClickThrough),
      to: menu)
    add(
      controller.organization.consent.paused ? "Resume app tracking" : "Pause app tracking",
      #selector(toggleTracking), to: menu)
    if controller.error != nil { add("Save needs attention…", #selector(showCompanion), to: menu) }
    add("Quit Molt", #selector(quit), to: menu, key: "q")
    status?.menu = menu
  }
  private func add(_ title: String, _ selector: Selector, to menu: NSMenu, key: String = "") {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
    item.target = self
    menu.addItem(item)
  }
  @objc private func interact(_ sender: NSMenuItem) {
    guard let controller,
      let action = controller.definition.interactions.first(where: {
        $0.id == sender.representedObject as? String
      })
    else { return }
    controller.interact(action)
  }
  @objc func showCompanion() {
    guard let controller else { return }
    if detailWindow == nil {
      detailWindow = window(
        title: "Molt: your desktop companion", size: NSSize(width: 1030, height: 780),
        content: CompanionView(controller: controller))
      detailWindow?.minSize = NSSize(width: 930, height: 720)
    }
    NSApp.activate(ignoringOtherApps: true)
    detailWindow?.makeKeyAndOrderFront(nil)
    controller.dashboardVisible = true
  }
  private func showGame() {
    guard let controller else { return }
    if gameWindow == nil {
      gameWindow = window(
        title: "Molt games", size: NSSize(width: 530, height: 540),
        content: GameView(controller: controller))
    }
    NSApp.activate(ignoringOtherApps: true)
    gameWindow?.makeKeyAndOrderFront(nil)
  }
  @objc func showCapture() {
    guard let controller else { return }
    if captureWindow == nil {
      captureWindow = window(
        title: "Quick capture", size: NSSize(width: 520, height: 310),
        content: QuickCaptureView(controller: controller))
    }
    NSApp.activate(ignoringOtherApps: true)
    captureWindow?.makeKeyAndOrderFront(nil)
  }
  private func window<V: View>(title: String, size: NSSize, content: V) -> NSWindow {
    let w = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    w.delegate = self
    w.title = title
    w.contentView = NSHostingView(rootView: content)
    w.isReleasedWhenClosed = false
    w.center()
    return w
  }
  private func applyPreferences() {
    guard let controller, let panel = petWindow else { return }
    let prefs = controller.companion.preferences
    panel.ignoresMouseEvents = prefs.clickThrough
    panel.collectionBehavior =
      prefs.fullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces]
    panel.setContentSize(NSSize(width: 250 * prefs.size, height: 280 * prefs.size))
    if prefs.movement == "hide" {
      panel.orderOut(nil)
      controller.petVisible = false
    }
    if lastDisplay != prefs.preferredDisplay {
      lastDisplay = prefs.preferredDisplay
      recoverPosition()
    }
    if prefs.movement == "bounded" && panel.isVisible && controller.companion.active == nil
      && !prefs.reducedMotion
    {
      if wanderOrigin == nil { wanderOrigin = panel.frame.origin }
      let base = wanderOrigin ?? panel.frame.origin
      let x = min(base.x + 80, max(base.x - 80, panel.frame.minX + CGFloat.random(in: -15...15)))
      panel.setFrameOrigin(NSPoint(x: x, y: base.y))
      recoverPosition()
    }
  }
  @objc private func togglePet() {
    if petWindow?.isVisible == true {
      petWindow?.orderOut(nil)
      controller?.petVisible = false
    } else {
      petWindow?.orderFrontRegardless()
      controller?.petVisible = true
    }
  }
  @objc private func bringBack() {
    controller?.changeCompanion {
      $0.preferences.clickThrough = false
      $0.preferences.movement = "stationary"
    }
    recoverPosition()
    petWindow?.orderFrontRegardless()
    controller?.petVisible = true
  }
  @objc private func toggleClickThrough() {
    controller?.changeCompanion { $0.preferences.clickThrough.toggle() }
  }
  @objc private func toggleTracking() {
    controller?.updateOrganization { $0.consent.paused.toggle() }
    controller?.configureContext()
    rebuildMenu()
  }
  @objc private func recoverPosition() {
    guard let panel = petWindow, !NSScreen.screens.isEmpty else { return }
    let index = min(
      NSScreen.screens.count - 1, max(0, controller?.companion.preferences.preferredDisplay ?? 0))
    let bounds = NSScreen.screens[index].visibleFrame
    let x = min(
      max(panel.frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - panel.frame.width))
    let y = min(
      max(panel.frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - panel.frame.height))
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
  func windowDidChangeOcclusionState(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if window === detailWindow {
      controller?.dashboardVisible = window.occlusionState.contains(.visible)
    }
    if window === petWindow { controller?.petVisible = window.occlusionState.contains(.visible) }
  }
  func windowWillClose(_ notification: Notification) {
    if let window = notification.object as? NSWindow, window === detailWindow {
      controller?.dashboardVisible = false
    }
  }
  func windowDidMove(_ notification: Notification) {
    if NSEvent.pressedMouseButtons != 0 { wanderOrigin = petWindow?.frame.origin }
    petWindow?.saveFrame(usingName: "MoltPetPosition")
  }
  @objc private func quit() { NSApp.terminate(nil) }
  func applicationWillTerminate(_ notification: Notification) {
    controller?.changeFocus("pause")
    controller?.tick()
    controller?.saveOrganization()
    petWindow?.saveFrame(usingName: "MoltPetPosition")
    if lockDescriptor >= 0 { close(lockDescriptor) }
  }
}
struct QuickCaptureView: View {
  @ObservedObject var controller: PetController
  @State private var text = ""
  @State private var kind = "task"
  @State private var due = Date().addingTimeInterval(3600)
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Make a little space.").font(MoltTheme.display(24))
      Picker("Capture", selection: $kind) {
        Text("Task").tag("task")
        Text("Note").tag("note")
        Text("Reminder").tag("reminder")
        Text("Command").tag("command")
      }.pickerStyle(.segmented)
      TextField(
        kind == "command" ? "today, focus, feed, journal, rest" : "What’s on your mind?",
        text: $text
      ).textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
      if kind == "reminder" { DatePicker("Confirm reminder time", selection: $due) }
      Text(
        kind == "command"
          ? "Explicit commands only. No other apps or files are controlled."
          : "Saved locally. You can organize it later."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Save", action: save).keyboardShortcut(.defaultAction)
      }
    }.padding(25).frame(minWidth: 470, minHeight: 260).background(MoltTheme.paper).onAppear {
      focused = true
    }
  }
  func save() {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    if kind == "command" {
      switch text.lowercased() {
      case "focus": controller.focus(minutes: 25)
      case "feed", "rest":
        if let action = controller.definition.interactions.first(where: {
          $0.id == text.lowercased()
        }) {
          controller.interact(action)
        }
      case "journal":
        controller.tab = "Molt"
        controller.onBringBack?()
      case "today":
        controller.tab = "Today"
        controller.onBringBack?()
      default:
        controller.error = "Unknown command. Try today, focus, feed, journal, or rest."
      }
    } else if kind == "reminder" {
      controller.updateOrganization { $0.reminders.append(Reminder(text, due: due)) }
      controller.configureContext()
    } else {
      controller.capture(text, kind: kind)
    }
    text = ""
  }
}
@main struct MoltApplication {
  @MainActor static func main() {
    let app = NSApplication.shared
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
    MoltTheme.registerFont()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "molt-preview-\(UUID())")
    let controller = try PetController(directory: root)
    controller.changeCompanion { $0.adoptionComplete = true }
    controller.organization.tasks = [
      WorkTask("Make room for one good idea"), WorkTask("A little walk outside"),
    ]
    controller.organization.tasks[0].today = true
    controller.organization.tasks[1].today = true
    controller.tab = CommandLine.arguments.last == "--pet" ? "Molt" : "Today"
    let view = NSHostingView(rootView: CompanionView(controller: controller))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1030, height: 780), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = view
    view.frame = NSRect(x: 0, y: 0, width: 1030, height: 780)
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
