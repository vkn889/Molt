import AppKit
import Carbon
import Combine
import MoltCore
import SwiftUI

@MainActor final class IslandCoordinator: NSObject, NSWindowDelegate, ObservableObject {
  @Published var expanded = false
  @Published var shortcutMessage = ""
  @Published var displayChoice = UserDefaults.standard.object(forKey: "islandDisplay") as? Int ?? -1
  @Published var safeTop: CGFloat = 32
  @Published var notchWidth: CGFloat = 185
  @Published var hasNotch = true
  @Published var reveal: CGFloat = 0
  @Published var menuOpen = false
  @Published private(set) var liveActivity = false
  @Published var hoverToOpen = UserDefaults.standard.object(forKey: "islandHoverOpen") as? Bool ?? true {
    didSet { UserDefaults.standard.set(hoverToOpen, forKey: "islandHoverOpen") }
  }
  @Published var shortcutChoice = 0
  /// Outward flare where the panel meets the menu bar, and the lower corner radius.
  static let flare: CGFloat = 14
  private let controller: PetController
  private var panel: FloatingPanel?
  private var screen: NSScreen?
  private var previousApp: NSRunningApplication?
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var hoverTimer: Timer?
  private var hoverSince: Date?
  private var outsideSince: Date?
  private var openedByHover = false
  private var resize: Task<Void, Never>?
  private var subscriptions = Set<AnyCancellable>()
  init(controller: PetController, preview: Bool = false) {
    self.controller = controller
    super.init()
    if preview {
      expanded = true
      reveal = 1
      return
    }
    controller.tab = "Notch"
    let panel = FloatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.delegate = self
    panel.contentView = NSHostingView(
      rootView: IslandView(controller: controller, coordinator: self))
    self.panel = panel
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
    let media = controller.hub.media
    media.$isPlaying.combineLatest(media.$track)
      .map { playing, track in playing && track != nil }
      .removeDuplicates()
      .sink { [weak self] playing in self?.setLiveActivity(playing) }
      .store(in: &subscriptions)
    controller.$tab.removeDuplicates().dropFirst()
      .sink { [weak self] _ in Task { @MainActor [weak self] in self?.fitToContent() } }
      .store(in: &subscriptions)
    $menuOpen.removeDuplicates().dropFirst()
      .sink { [weak self] _ in Task { @MainActor [weak self] in self?.fitToContent() } }
      .store(in: &subscriptions)
    reposition()
    controller.dashboardVisible = false
    panel.orderOut(nil)
    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.trackPointer() }
    }
    hoverTimer?.tolerance = 0.03
  }

  // MARK: Geometry

  /// Height of the band beside the hardware notch; the header lives here.
  var headerHeight: CGFloat { hasNotch ? max(28, safeTop) : 34 }
  var expandedSize: CGSize {
    let home = controller.tab == "Notch" && !menuOpen
    return CGSize(width: 720, height: headerHeight + (home ? 132 : 380))
  }
  var collapsedSize: CGSize {
    let wing = liveActivity ? headerHeight + 8 : 0
    return CGSize(width: notchWidth + 2 * wing, height: hasNotch ? headerHeight : 0)
  }
  private var reducedMotion: Bool {
    controller.companion.preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
  private func frame(for size: CGSize) -> CGRect? {
    guard let screen else { return nil }
    return IslandGeometry.frame(
      screen: screen.frame, visible: screen.visibleFrame,
      size: CGSize(width: size.width + 2 * Self.flare, height: size.height))
  }

  // MARK: Shortcut

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
      ? "Command-Shift-Enter opens and closes Molt"
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

  // MARK: Open and close

  func open(hover: Bool = false) {
    guard let panel else { return }
    resize?.cancel()
    if !expanded {
      openedByHover = hover
      if !hover { previousApp = NSWorkspace.shared.frontmostApplication }
    } else if !hover {
      openedByHover = false
    }
    expanded = true
    outsideSince = nil
    controller.dashboardVisible = true
    controller.hub.media.active = true
    controller.refreshHealth()
    if let target = frame(for: expandedSize) { panel.setFrame(target, display: true) }
    panel.orderFrontRegardless()
    if !hover {
      panel.makeKey()
      NSApp.activate(ignoringOtherApps: true)
    }
    animate(response: 0.42, damping: 0.8) { self.reveal = 1 }
  }
  func collapse() {
    guard expanded else { return }
    expanded = false
    menuOpen = false
    openedByHover = false
    controller.dashboardVisible = false
    controller.hub.media.active = false
    animate(response: 0.36, damping: 0.92) { self.reveal = 0 }
    settle(after: reducedMotion ? 0 : 0.4)
    if NSWorkspace.shared.frontmostApplication?.processIdentifier
      == ProcessInfo.processInfo.processIdentifier
    {
      previousApp?.activate(options: [])
    }
    panel?.resignKey()
  }
  private func animate(response: Double, damping: Double, _ change: @escaping () -> Void) {
    if reducedMotion { change() } else { withAnimation(.spring(response: response, dampingFraction: damping), change) }
  }
  /// After a closing animation, shrink the window to the live activity or hide it.
  private func settle(after delay: Double) {
    resize?.cancel()
    resize = Task { @MainActor [weak self] in
      if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
      guard let self, !Task.isCancelled, !self.expanded, let panel = self.panel else { return }
      if self.liveActivity, let target = self.frame(for: self.collapsedSize) {
        panel.setFrame(target, display: true)
        panel.orderFrontRegardless()
      } else {
        panel.orderOut(nil)
      }
    }
  }
  /// Grows the window before content expands; shrinks only after content has animated in.
  private func fitToContent() {
    guard expanded, let panel, let target = frame(for: expandedSize) else { return }
    if target.height >= panel.frame.height {
      resize?.cancel()
      panel.setFrame(target, display: true)
    } else {
      resize?.cancel()
      resize = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard let self, !Task.isCancelled, self.expanded, let panel = self.panel,
          let target = self.frame(for: self.expandedSize)
        else { return }
        panel.setFrame(target, display: true)
      }
    }
  }
  private func setLiveActivity(_ playing: Bool) {
    let show = playing && hasNotch
    guard show != liveActivity else { return }
    if show, !expanded, let panel, let target = frame(for: CGSize(width: notchWidth + 2 * (headerHeight + 8), height: headerHeight)) {
      resize?.cancel()
      panel.setFrame(target, display: true)
      panel.orderFrontRegardless()
    }
    animate(response: 0.4, damping: 0.8) { self.liveActivity = show }
    if !expanded && !show { settle(after: reducedMotion ? 0 : 0.4) }
  }

  // MARK: Hover

  private func trackPointer() {
    guard let screen, let panel else { return }
    let mouse = NSEvent.mouseLocation
    let now = Date()
    if !expanded {
      guard hoverToOpen, NSEvent.pressedMouseButtons == 0 else { hoverSince = nil; return }
      let size = collapsedSize
      let width = max(size.width, hasNotch ? notchWidth : 200) + 2 * Self.flare
      let height = hasNotch ? headerHeight : 4
      let zone = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height + 1)
      if zone.contains(mouse) {
        if let since = hoverSince, now.timeIntervalSince(since) > 0.12 {
          hoverSince = nil
          controller.tab = "Notch"
          open(hover: true)
        } else if hoverSince == nil {
          hoverSince = now
        }
      } else {
        hoverSince = nil
      }
    } else if openedByHover, !panel.isKeyWindow, !menuOpen {
      if panel.frame.insetBy(dx: -8, dy: -8).contains(mouse) {
        outsideSince = nil
      } else if let since = outsideSince, now.timeIntervalSince(since) > 0.3 {
        collapse()
      } else if outsideSince == nil {
        outsideSince = now
      }
    }
  }

  @objc func reposition() {
    let screens = NSScreen.screens
    let selected =
      displayChoice >= 0 && displayChoice < screens.count ? screens[displayChoice] : nil
    let automatic =
      displayChoice == -2 ? NSScreen.main : screens.first(where: { $0.safeAreaInsets.top > 0 })
    guard let screen = selected ?? automatic ?? NSScreen.main ?? screens.first else { return }
    self.screen = screen
    UserDefaults.standard.set(displayChoice, forKey: "islandDisplay")
    safeTop = screen.safeAreaInsets.top
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, safeTop > 0 {
      hasNotch = true
      notchWidth = max(1, right.minX - left.maxX)
    } else {
      hasNotch = false
      notchWidth = 200
    }
    if expanded, let target = frame(for: expandedSize) {
      panel?.setFrame(target, display: true)
    } else {
      if !hasNotch && liveActivity { liveActivity = false }
      settle(after: 0)
    }
  }
  func windowDidResignKey(_ notification: Notification) {
    // Native file pickers own focus temporarily; never collapse beneath them.
    guard expanded, NSApp.modalWindow == nil, panel?.attachedSheet == nil else { return }
    collapse()
  }
}

struct IslandView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var assistant: AssistantController
  @ObservedObject var media: NowPlayingController
  @AppStorage("islandAccent") private var accent = "blue"
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  private var reduced: Bool { controller.companion.preferences.reducedMotion || systemReduced }
  private var motion: Animation? { reduced ? nil : .spring(response: 0.34, dampingFraction: 0.86) }
  init(controller: PetController, coordinator: IslandCoordinator) {
    self.controller = controller
    self.coordinator = coordinator
    self.assistant = controller.assistant
    self.media = controller.hub.media
  }
  var body: some View {
    let reveal = coordinator.reveal
    let collapsed = coordinator.collapsedSize
    let target = coordinator.expandedSize
    let flare = IslandCoordinator.flare
    let width = collapsed.width + (target.width - collapsed.width) * reveal
    let height = collapsed.height + (target.height - collapsed.height) * reveal
    let shape = NotchShape(topRadius: flare * (0.6 + 0.4 * reveal), bottomRadius: 10 + 16 * reveal)
    ZStack(alignment: .top) {
      shape.fill(Color.black)
      if coordinator.liveActivity && !coordinator.expanded {
        NotchLiveActivity(media: media, notchWidth: coordinator.notchWidth, height: collapsed.height)
          .frame(width: collapsed.width, height: collapsed.height)
          .contentShape(Rectangle())
          .onTapGesture { controller.tab = "Notch"; coordinator.open() }
          .transition(.opacity)
      }
      if coordinator.expanded {
        expandedContent
          .frame(width: target.width, height: target.height, alignment: .top)
          .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
      }
    }
    .frame(width: width + 2 * flare, height: max(0, height), alignment: .top)
    .clipShape(shape)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .environment(\.moltReducedMotion, controller.companion.preferences.reducedMotion)
    .environment(\.colorScheme, .dark)
    .preferredColorScheme(.dark)
    .tint(MoltTheme.accent(accent))
    .accentColor(MoltTheme.accent(accent))
    .onChange(of: coordinator.displayChoice) { _ in coordinator.reposition() }
    .onExitCommand { if coordinator.menuOpen { coordinator.menuOpen = false } else { coordinator.collapse() } }
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

  private var expandedContent: some View {
    VStack(spacing: 0) {
      header.frame(height: coordinator.headerHeight)
      Group {
        if controller.tab == "Notch" {
          NotchHomeView(controller: controller, media: media)
        } else {
          CompanionView(controller: controller, compact: true)
            .buttonStyle(NotchButtonStyle())
        }
      }
      .modifier(NotchPageMotion(route: controller.tab))
      .disabled(coordinator.menuOpen).accessibilityHidden(coordinator.menuOpen)
    }
    .foregroundStyle(.white)
    .overlay(alignment: .topTrailing) {
      if coordinator.menuOpen {
        ZStack(alignment: .topTrailing) {
          Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { coordinator.menuOpen = false }
          NotchNavigation(
            selection: $controller.tab, accent: $accent, display: $coordinator.displayChoice,
            hoverToOpen: $coordinator.hoverToOpen, shortcut: coordinator.shortcutMessage,
            dismiss: { coordinator.menuOpen = false }
          )
          .frame(width: 250).padding(.trailing, 16).padding(.top, coordinator.headerHeight + 4).padding(.bottom, 14)
        }
        .transition(.opacity)
      }
    }
    .animation(motion, value: coordinator.menuOpen)
    .animation(motion, value: controller.tab)
  }

  private var header: some View {
    HStack(spacing: 0) {
      HStack(spacing: 4) {
        tabButton("Notch", "Home", "house.fill")
        tabButton("Hub", "Hub", "square.grid.2x2.fill")
        if !["Notch", "Hub"].contains(controller.tab) {
          tabButton(controller.tab, controller.tab == "Ask Molt" ? "Chat" : controller.tab, "circle.fill", dot: true)
        }
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity)
      if coordinator.hasNotch { Color.clear.frame(width: coordinator.notchWidth + 12) }
      HStack(spacing: 2) {
        Spacer(minLength: 0)
        if assistant.running {
          ProgressView().controlSize(.mini).padding(.trailing, 4)
          iconButton("stop.fill", "Stop reply", action: assistant.cancel)
        }
        iconButton("bubble.left.fill", "Chat") { controller.tab = "Ask Molt" }
        iconButton("magnifyingglass", "Search with Molting") { controller.tab = "Molting" }
        iconButton("plus", "Quick capture") { controller.tab = "Capture" }
        iconButton(coordinator.menuOpen ? "xmark" : "ellipsis", coordinator.menuOpen ? "Close menu" : "All destinations and settings") {
          coordinator.menuOpen.toggle()
        }
      }.frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 14)
  }
  private func tabButton(_ route: String, _ title: String, _ icon: String, dot: Bool = false) -> some View {
    let selected = controller.tab == route
    return Button {
      controller.tab = route
      coordinator.menuOpen = false
    } label: {
      HStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: dot ? 5 : 10, weight: .semibold))
        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
      }
      .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
      .padding(.horizontal, 10).frame(height: 24)
      .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
    }
    .buttonStyle(NotchIconButtonStyle(size: 26))
    .help(help).accessibilityLabel(help)
  }
}
