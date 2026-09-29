import AppKit
import Carbon
import MoltCore
import SwiftUI

@MainActor final class IslandCoordinator: NSObject, NSWindowDelegate, ObservableObject {
  @Published var expanded = false
  @Published var shortcutMessage = ""
  @Published var displayChoice = UserDefaults.standard.object(forKey: "islandDisplay") as? Int ?? -1
  @Published var safeTop: CGFloat = 32
  @Published var notchWidth: CGFloat = 180
  @Published var reveal: CGFloat = 0
  @Published var shortcutChoice = 0
  private let controller: PetController
  private var panel: FloatingPanel!
  private var previousApp: NSRunningApplication?
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  init(controller: PetController, preview: Bool = false) {
    self.controller = controller
    super.init()
    if preview {
      expanded = true
      reveal = 1
      return
    }
    panel = FloatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
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
        Task { @MainActor in coordinator.toggleFromShortcut() }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    registerShortcut()
    NotificationCenter.default.addObserver(
      self, selector: #selector(reposition),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(reposition), name: NSWorkspace.didWakeNotification, object: nil)
    reposition()
    controller.dashboardVisible = false
    panel.orderOut(nil)
  }
  func registerShortcut() {
    if let hotKey {
      UnregisterEventHotKey(hotKey)
      self.hotKey = nil
    }
    UserDefaults.standard.set(shortcutChoice, forKey: "islandShortcut")
    let key = kVK_Return
    let result = RegisterEventHotKey(
      UInt32(key), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4D4F_4C54, id: 1),
      GetApplicationEventTarget(), 0, &hotKey)
    shortcutMessage =
      result == noErr
      ? "Shortcut registered: Command–Shift–Enter"
      : "Shortcut unavailable (\(result)). Use the menu bar to open Molt."
  }
  func toggle() { expanded ? collapse() : open() }
  func toggleFromShortcut() {
    if expanded {
      collapse()
    } else {
      controller.tab = "Notch"
      open()
    }
  }
  func open() {
    if !expanded { previousApp = NSWorkspace.shared.frontmostApplication }
    expanded = true
    controller.dashboardVisible = true
    reposition()
    panel.contentView?.layoutSubtreeIfNeeded()
    panel.alphaValue = 1
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    if controller.companion.preferences.reducedMotion {
      reveal = 1
    } else {
      withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { reveal = 1 }
    }
  }
  func collapse() {
    guard expanded else { return }
    expanded = false
    controller.dashboardVisible = false
    let reduced = controller.companion.preferences.reducedMotion
    if reduced {
      reveal = 0
      panel.orderOut(nil)
    } else {
      withAnimation(.spring(response: 0.34, dampingFraction: 0.94)) { reveal = 0 }
      Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 360_000_000)
        guard let self, !self.expanded else { return }
        self.panel.orderOut(nil)
      }
    }
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
    safeTop = screen.safeAreaInsets.top
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      notchWidth = max(1, right.minX - left.maxX)
    } else {
      notchWidth = 180
    }
    panel.setFrame(
      IslandGeometry.frame(
        screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
        expanded: true), display: true)
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
  @AppStorage("islandTheme") private var theme = "dark"
  @AppStorage("islandAccent") private var accent = "mint"
  @State private var navigationOpen = false
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  private var motion: Animation? { controller.companion.preferences.reducedMotion || systemReduced ? nil : .spring(response: 0.3, dampingFraction: 0.86) }
  var previewTheme: String?
  init(controller: PetController, coordinator: IslandCoordinator, previewTheme: String? = nil) {
    self.controller = controller
    self.coordinator = coordinator
    self.assistant = controller.assistant
    self.previewTheme = previewTheme
    _navigationOpen = State(initialValue: CommandLine.arguments.contains("--render-preview") && CommandLine.arguments.contains("--navigation"))
  }
  var body: some View {
    VStack(spacing: 0) {
      Color.black.frame(height: coordinator.safeTop)
      HStack(spacing: 14) {
        Button { navigationOpen.toggle() } label: {
          HStack(spacing: 8) {
            Image(systemName: "leaf")
            Text(controller.tab == "Notch" ? "Molt" : controller.tab)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
              .rotationEffect(.degrees(navigationOpen ? 180 : 0))
          }
        }.accessibilityLabel("Molt navigation and settings")
          .accessibilityValue(navigationOpen ? "Expanded" : "Collapsed")
        Spacer()
        if assistant.running {
          ProgressView().controlSize(.small)
          Button("Stop", action: assistant.cancel)
        }
        Button {
          controller.tab = "Ask Molt"
        } label: {
          Image(systemName: "bubble.left.and.bubble.right")
        }.help("Chat")
        Button {
          controller.tab = "Molting"
        } label: {
          Image(systemName: "globe")
        }.help("Molting search")
        Button {
          controller.tab = "Capture"
        } label: {
          Image(systemName: "plus")
        }.help("Quick capture")
        Button {
          coordinator.collapse()
        } label: {
          Image(systemName: "xmark")
        }.help("Hide Molt (Command–Shift–Enter)")
      }.buttonStyle(GlassButtonStyle()).padding(.horizontal, 18).frame(height: 44)
      Divider().opacity(0.3)
      CompanionView(controller: controller, compact: true)
        .modifier(GlassPageMotion(route: controller.tab))
        .disabled(navigationOpen).accessibilityHidden(navigationOpen)
    }.background {
      ZStack {
        MoltTheme.paper
        LinearGradient(colors: [Color.accentColor.opacity(0.14), .clear, Color.accentColor.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
      }
    }
      .overlay(alignment: .topLeading) {
        if navigationOpen {
          GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
              Color.black.opacity(0.20).contentShape(Rectangle()).onTapGesture { navigationOpen = false }
              GlassNavigation(selection: $controller.tab, theme: $theme, accent: $accent,
                display: $coordinator.displayChoice, shortcut: coordinator.shortcutMessage,
                dismiss: { navigationOpen = false })
                .frame(width: min(480, proxy.size.width - 24), height: max(100, proxy.size.height - coordinator.safeTop - 50))
                .padding(.leading, 12).padding(.top, coordinator.safeTop + 46)
            }
          }.transition(.opacity.combined(with: .offset(y: -5)))
        }
      }
      .animation(motion, value: navigationOpen)
      .animation(motion, value: controller.tab)
      .environment(\.moltReducedMotion, controller.companion.preferences.reducedMotion)
      .buttonStyle(GlassButtonStyle())
      .clipShape(UnevenNotchShape())
      .mask {
        GeometryReader { geometry in
          RoundedRectangle(cornerRadius: 10 + 16 * coordinator.reveal)
            .frame(
              width: coordinator.notchWidth + (geometry.size.width - coordinator.notchWidth)
                * coordinator.reveal,
              height: max(2, coordinator.safeTop)
                + (geometry.size.height - max(2, coordinator.safeTop)) * coordinator.reveal
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
      }
      .tint(MoltTheme.accent(accent))
      .accentColor(MoltTheme.accent(accent))
      .preferredColorScheme(
        (previewTheme ?? theme) == "system"
          ? nil : ((previewTheme ?? theme) == "light" ? .light : .dark)
      )
      .onChange(of: coordinator.displayChoice) { _ in coordinator.reposition() }
      .onExitCommand { if navigationOpen { navigationOpen = false } else { coordinator.collapse() } }
      .onChange(of: coordinator.expanded) { if !$0 { navigationOpen = false } }

      .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url else { return }
          Task { @MainActor in
            controller.assistant.attach(url)
            controller.tab = "Ask Molt"
          }
        }
        return true
      }
  }
}
struct UnevenNotchShape: Shape {
  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = min(26, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.closeSubpath()
    return path
  }
}
struct NotchQuickView: View {
  @ObservedObject var controller: PetController
  var body: some View {
    HStack(alignment: .center, spacing: 24) {
      VStack(spacing: 6) {
        CreatureView(
          appearance: controller.companion.appearance, atlasURL: controller.atlasURL,
          mood: controller.mood,
          moving: controller.dashboardVisible && !controller.companion.preferences.reducedMotion,
          intensity: controller.companion.preferences.animationIntensity,
          stage: controller.state.stageID
        )
        .frame(width: 100, height: 100)
        Text(controller.petName).font(MoltTheme.display(18))
      }
      VStack(alignment: .leading, spacing: 12) {
        Text("A little company. A little clarity.").font(MoltTheme.display(20))
        Text(controller.message).id(controller.message).transition(.opacity).animation(controller.companion.preferences.reducedMotion ? nil : .easeOut(duration: 0.2), value: controller.message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        HStack {
          Button("Chat") { controller.tab = "Ask Molt" }
          Button("Molting") { controller.tab = "Molting" }
          Button("Focus 25m") { controller.focus(minutes: 25) }
        }.buttonStyle(GlassButtonStyle())
        HStack {
          ForEach(controller.definition.interactions.prefix(3), id: \.id) { action in
            Button(action.name) { controller.interact(action) }.disabled(
              controller.blockReason(action) != nil
            )
            .help(controller.blockReason(action) ?? action.name)
          }
        }.buttonStyle(GlassButtonStyle())
      }
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 8) {
        Text(Date(), format: .dateTime.month(.abbreviated)).font(MoltTheme.display(22))
        Text(Date(), format: .dateTime.day()).font(
          .system(size: 36, weight: .bold, design: .rounded)
        ).foregroundStyle(Color.accentColor)
        Text(
          controller.organization.tasks.filter { $0.today && $0.completed == nil }.first?.title
            ?? "A little room for today."
        )
        .font(.caption).lineLimit(3)
      }.frame(width: 120, alignment: .leading)
    }.frame(maxWidth: .infinity, minHeight: 185)
  }
}
