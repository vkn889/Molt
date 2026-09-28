import AppKit
import Carbon
import MoltCore
import SwiftUI

@MainActor final class IslandCoordinator: NSObject, NSWindowDelegate, ObservableObject {
  @Published var expanded = false
  @Published var shortcutMessage = ""
  @Published var displayChoice = UserDefaults.standard.object(forKey: "islandDisplay") as? Int ?? -1
  @Published var shortcutChoice = UserDefaults.standard.integer(forKey: "islandShortcut")
  private let controller: PetController
  private var panel: FloatingPanel!
  private var previousApp: NSRunningApplication?
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  init(controller: PetController) {
    self.controller = controller
    super.init()
    panel = FloatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentView = NSHostingView(
      rootView: IslandView(controller: controller, coordinator: self))
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, pointer in
        guard let pointer else { return OSStatus(eventNotHandledErr) }
        let coordinator = Unmanaged<IslandCoordinator>.fromOpaque(pointer).takeUnretainedValue()
        Task { @MainActor in coordinator.toggle() }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    registerShortcut()
    NotificationCenter.default.addObserver(
      self, selector: #selector(reposition),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(reposition), name: NSWorkspace.didWakeNotification, object: nil)
    reposition()
    panel.orderFrontRegardless()
  }
  func registerShortcut() {
    if let hotKey {
      UnregisterEventHotKey(hotKey)
      self.hotKey = nil
    }
    UserDefaults.standard.set(shortcutChoice, forKey: "islandShortcut")
    let key = shortcutChoice == 1 ? kVK_ANSI_M : kVK_Space
    let result = RegisterEventHotKey(
      UInt32(key), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4D4F_4C54, id: 1),
      GetApplicationEventTarget(), 0, &hotKey)
    shortcutMessage =
      result == noErr
      ? "Shortcut registered: Command–Shift–\(shortcutChoice == 1 ? "M" : "Space")"
      : "Shortcut unavailable (\(result)). Choose the alternative or use the menu bar."
  }
  func toggle() { expanded ? collapse() : open() }
  func open() {
    if !expanded { previousApp = NSWorkspace.shared.frontmostApplication }
    expanded = true
    controller.dashboardVisible = true
    reposition()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }
  func collapse() {
    expanded = false
    controller.dashboardVisible = false
    reposition()
    panel.resignKey()
    if NSWorkspace.shared.frontmostApplication?.processIdentifier
      == ProcessInfo.processInfo.processIdentifier
    {
      previousApp?.activate(options: [])
    }
  }
  @objc func reposition() {
    let screens = NSScreen.screens
    let selected =
      displayChoice >= 0 && displayChoice < screens.count ? screens[displayChoice] : nil
    let automatic =
      displayChoice == -2 ? NSScreen.main : screens.first(where: { $0.safeAreaInsets.top > 0 })
    guard let screen = selected ?? automatic ?? NSScreen.main ?? screens.first else { return }
    UserDefaults.standard.set(displayChoice, forKey: "islandDisplay")
    panel.setFrame(
      IslandGeometry.frame(
        screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
        expanded: expanded), display: true)
  }
  func windowDidResignKey(_ notification: Notification) {
    // Native file pickers own focus temporarily; never collapse beneath them.
    guard expanded, NSApp.modalWindow == nil, panel.attachedSheet == nil else { return }
    collapse()
  }
}
struct IslandView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var assistant: AssistantController
  init(controller: PetController, coordinator: IslandCoordinator) {
    self.controller = controller
    self.coordinator = coordinator
    self.assistant = controller.assistant
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          coordinator.toggle()
        } label: {
          HStack {
            CreatureView(
              appearance: controller.companion.appearance, atlasURL: controller.atlasURL,
              mood: controller.mood, moving: false, intensity: 0, stage: controller.state.stageID
            )
            .frame(width: 28, height: 28)
            Text(controller.petName).font(MoltTheme.display(16))
            if assistant.running {
              ProgressView().controlSize(.small)
            } else if assistant.workspace.jobs.contains(where: { $0.status == "awaiting review" }) {
              Image(systemName: "checkmark.shield").accessibilityLabel("Action awaiting review")
            }
          }
        }.buttonStyle(.plain).accessibilityLabel(
          coordinator.expanded ? "Collapse Molt Island" : "Expand Molt Island")
        if coordinator.expanded {
          Spacer()
          Button("Ask Molt") { controller.tab = "Ask Molt" }
          Button {
            controller.tab = "Settings"
          } label: {
            Image(systemName: "gearshape")
          }.accessibilityLabel("Settings")
          Button {
            coordinator.collapse()
          } label: {
            Image(systemName: "chevron.up")
          }.accessibilityLabel("Collapse island")
        }
      }.padding(12).foregroundStyle(.white).frame(height: 44)
      CompanionView(controller: controller, compact: true)
        .frame(height: coordinator.expanded ? nil : 0)
        .clipped().opacity(coordinator.expanded ? 1 : 0)
        .allowsHitTesting(coordinator.expanded).accessibilityHidden(!coordinator.expanded)
      if coordinator.expanded {
        HStack {
          if assistant.running {
            Text("Local AI working").font(.caption)
            Button("Stop", action: assistant.cancel)
          } else if assistant.workspace.jobs.contains(where: { $0.status == "awaiting review" }) {
            Button("Review pending actions") { controller.tab = "Ask Molt" }
          }
          Spacer()
          Picker("Display", selection: $coordinator.displayChoice) {
            Text("Built-in / automatic").tag(-1)
            Text("Active display").tag(-2)
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
              Text(screen.localizedName).tag(index)
            }
          }.frame(width: 220).onChange(of: coordinator.displayChoice) { _ in
            coordinator.reposition()
          }
        }.padding(.horizontal, 10).foregroundStyle(.white)
        HStack {
          Picker("Shortcut", selection: $coordinator.shortcutChoice) {
            Text("⌘⇧Space").tag(0)
            Text("⌘⇧M").tag(1)
          }.frame(width: 190).onChange(of: coordinator.shortcutChoice) { _ in
            coordinator.registerShortcut()
          }
          Text(coordinator.shortcutMessage).font(.caption2)
          Spacer()
        }.padding(8).foregroundStyle(.white)
      }
    }.background(Color(red: 0.045, green: 0.055, blue: 0.06))
      .clipShape(RoundedRectangle(cornerRadius: 22)).onExitCommand { coordinator.collapse() }
      .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url else { return }
          Task { @MainActor in
            controller.assistant.attach(url)
            controller.tab = "Ask Molt"
            coordinator.open()
          }
        }
        return true
      }
  }
}
