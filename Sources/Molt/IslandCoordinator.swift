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
  @Published private(set) var liveActivity = false
  @Published var hoverToOpen = UserDefaults.standard.object(forKey: "islandHoverOpen") as? Bool ?? true {
    didSet { UserDefaults.standard.set(hoverToOpen, forKey: "islandHoverOpen") }
  }
  @Published var shortcutChoice = 0
  /// A short notice shown beside the closed notch: an approval, a finished task, a habit or a note.
  @Published private(set) var banner: IslandBanner?
  private var bannerTimer: Task<Void, Never>?
  private var keys: [UInt32: EventHotKeyRef] = [:]
  /// Outward flare where the panel meets the menu bar, and the lower corner radius.
  static let flare: CGFloat = 14
  private let controller: PetController
  let lens: LensController
  let health = HealthDetailController()
  private var panel: FloatingPanel?
  private var lensKey: EventHotKeyRef?
  private var screen: NSScreen?
  private var previousApp: NSRunningApplication?
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var hoverTimer: Timer?
  private var hoverSince: Date?
  private var outsideSince: Date?
  private var openedByHover = false
  /// A drag in progress (for example, feeding Molt) keeps a hover-opened notch open.
  var dragging: Bool { NSEvent.pressedMouseButtons != 0 }
  private var resize: Task<Void, Never>?
  private var subscriptions = Set<AnyCancellable>()
  init(controller: PetController, preview: Bool = false) {
    self.controller = controller
    lens = LensController(assistant: controller.assistant)
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
      { _, event, pointer in
        guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
        var key = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &key)
        let coordinator = Unmanaged<IslandCoordinator>.fromOpaque(pointer).takeUnretainedValue()
        let id = key.id
        Task { @MainActor in coordinator.shortcut(id) }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    registerShortcut()
    NotificationCenter.default.addObserver(
      self, selector: #selector(reposition),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(reposition), name: NSWorkspace.didWakeNotification, object: nil)
    let media = controller.hub.media
    let actions = controller.hub.actions
    let agents = controller.agents
    media.$isPlaying.combineLatest(media.$track, actions.$recording, agents.$live.combineLatest(agents.$pending.map(\.count)))
      .map { playing, track, recording, agentState in
        (playing && track != nil) || recording != nil || agentState.1 > 0
          || agentState.0.values.contains { $0.status == .working || $0.status == .needsYou }
      }
      .removeDuplicates()
      .sink { [weak self] active in self?.setLiveActivity(active) }
      .store(in: &subscriptions)
    lens.hide = { [weak self] in self?.collapse() }
    lens.show = { [weak self] in
      guard let self else { return }
      self.controller.tab = "Lens"
      self.open()
    }
    actions.onLens = { [weak self] in self?.startLens() }
    actions.onFocus = { [weak controller] in controller?.focus(minutes: 25) }
    actions.beforeCapture = { [weak self] in self?.collapse() }
    // Friends and hangouts connect once you're signed in.
    controller.account.$phase.removeDuplicates()
      .sink { [weak controller] phase in
        Task { @MainActor in
          if phase == .signedIn { controller?.social.start() } else { controller?.social.stop() }
        }
      }
      .store(in: &subscriptions)
    bridgeSetup()
    bridgeAgents()
    controller.$tab.removeDuplicates().dropFirst()
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
  /// Every page shares Home's footprint.
  static let bodyHeight: CGFloat = 176
  var expandedSize: CGSize { CGSize(width: 720, height: headerHeight + Self.bodyHeight) }
  var collapsedSize: CGSize {
    if banner != nil { return bannerSize }
    let wing = liveActivity ? headerHeight + 8 : 0
    return CGSize(width: notchWidth + 2 * wing, height: hasNotch ? headerHeight : 0)
  }
  var bannerSize: CGSize { size(for: banner) }
  func size(for banner: IslandBanner?) -> CGSize {
    let tall = banner?.isApproval == true
    return CGSize(width: min(680, max(notchWidth + 380, 600)), height: headerHeight + (tall ? 104 : 58))
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
    for (_, key) in keys { UnregisterEventHotKey(key) }
    keys = [:]
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    if let lensKey { UnregisterEventHotKey(lensKey); self.lensKey = nil }
    UserDefaults.standard.set(shortcutChoice, forKey: "islandShortcut")
    let result = RegisterEventHotKey(
      UInt32(kVK_Return), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4D4F_4C54, id: 1),
      GetApplicationEventTarget(), 0, &hotKey)
    RegisterEventHotKey(
      UInt32(kVK_ANSI_L), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4D4F_4C54, id: 2),
      GetApplicationEventTarget(), 0, &lensKey)
    for (id, key) in Self.extraShortcuts { register(id, key) }
    shortcutMessage =
      result == noErr
      ? "⌘⇧↩ opens Molt · ⌘⇧L asks about your screen"
      : "Shortcut unavailable (\(result)). Use the menu bar to open Molt."
  }
  /// Control-Option shortcuts for each part of Molt. Allow and Deny exist only while an approval waits.
  static let extraShortcuts: [(UInt32, Int)] = [(3, kVK_ANSI_C), (4, kVK_ANSI_W), (5, kVK_ANSI_A), (6, kVK_ANSI_U), (7, kVK_ANSI_G), (8, kVK_ANSI_H)]
  static var shortcutList: [(String, String)] {
    let mod = NSWorkspace.shared.isVoiceOverEnabled ? "⌃⌥⌘" : "⌃⌥"
    return [
      ("⌘⇧↩", "Open Molt"), ("⌘⇧L", "Ask about your screen"), (mod + "C", "Chat"), (mod + "A", "Agents"), (mod + "U", "Plan usage"),
      (mod + "G", "GitHub"), (mod + "W", "Wardrobe"), (mod + "H", "Hub"), (mod + "Y", "Allow an approval"), (mod + "N", "Deny an approval"),
    ]
  }
  /// Control-Option is VoiceOver's own modifier; with VoiceOver on, Molt adds Command.
  static var modifiers: UInt32 {
    UInt32(NSWorkspace.shared.isVoiceOverEnabled ? controlKey | optionKey | cmdKey : controlKey | optionKey)
  }
  private func register(_ id: UInt32, _ key: Int) {
    guard keys[id] == nil else { return }
    var ref: EventHotKeyRef?
    if RegisterEventHotKey(UInt32(key), Self.modifiers, EventHotKeyID(signature: 0x4D4F_4C54, id: id), GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
      keys[id] = ref
    }
  }
  private func unregister(_ id: UInt32) {
    if let ref = keys.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
  }
  func shortcut(_ id: UInt32) {
    switch id {
    case 1: toggleFromShortcut()
    case 2: startLens()
    case 3: show("Ask Molt")
    case 4: show("Wardrobe")
    case 5: UserDefaults.standard.set("Live", forKey: "agentsTab"); show("Agents")
    case 6: UserDefaults.standard.set("Usage", forKey: "agentsTab"); show("Agents")
    case 7: UserDefaults.standard.set("GitHub", forKey: "agentsTab"); show("Agents")
    case 8: show("Hub")
    case 10: if let item = controller.agents.pending.first { controller.agents.allow(item.id) }
    case 11: if let item = controller.agents.pending.first { controller.agents.deny(item.id) }
    default: break
    }
  }
  /// Opens Molt on a page, or closes it if that page is already showing.
  func show(_ route: String) {
    guard controller.account.phase == .signedIn else { controller.tab = "Notch"; open(); return }
    if expanded && controller.tab == route { collapse(); return }
    controller.tab = route
    open()
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

  func startLens() {
    guard controller.account.phase == .signedIn else { controller.tab = "Notch"; open(); return }
    lens.clear()
    lens.capture()
  }
  /// What a friend borrows when you lend your setup: Hub widgets, accent color and Molt's color.
  private func bridgeSetup() {
    let controller = self.controller
    controller.social.captureSetup = {
      let widgets = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.hub.layout))) ?? []
      return [
        "widgets": widgets, "accent": UserDefaults.standard.string(forKey: "islandAccent") ?? "blue",
        "palette": controller.companion.appearance.palette,
        "outfit": controller.companion.appearance.outfit,
      ]
    }
    controller.social.applySetup = { setup in
      if let widgets = setup["widgets"], let data = try? JSONSerialization.data(withJSONObject: widgets),
        let layout = try? JSONDecoder().decode([HubWidget].self, from: data)
      {
        controller.hub.setLayout(HubLayout.sanitize(layout, known: Set(WidgetKind.catalog.map(\.id))))
      }
      if let accent = setup["accent"] as? String, ["blue", "mint", "violet", "amber", "rose"].contains(accent) {
        UserDefaults.standard.set(accent, forKey: "islandAccent")
      }
      if let palette = setup["palette"] as? String, ["sage", "ocean", "sunset", "violet"].contains(palette) {
        controller.changeCompanion { $0.appearance.palette = palette }
      }
      // A borrowed outfit can include items you haven't earned; it goes back with the loan.
      if let outfit = setup["outfit"] as? [String] {
        controller.changeCompanion { $0.appearance.outfit = outfit.filter { WardrobeItem.find($0) != nil } }
      }
    }
  }

  // MARK: Agents and banners

  /// For screenshots: a banner over the closed notch, or over the open page.
  func preview(banner: IslandBanner?, expanded: Bool = false) {
    self.banner = banner
    self.expanded = expanded
    reveal = expanded ? 1 : 0
    if banner == nil { liveActivity = true }
  }

  private func bridgeAgents() {
    let agents = controller.agents, controller = self.controller
    agents.start()
    agents.onBanner = { [weak self] banner in self?.present(banner) }
    controller.github.onBanner = { [weak self] banner in self?.present(banner) }
    controller.github.recentDirectory = { [weak agents] in
      agents?.live.values.sorted { $0.since > $1.since }.first { !$0.directory.isEmpty }?.directory
    }
    agents.$pending.map(\.count).removeDuplicates()
      .sink { [weak self] count in
        Task { @MainActor [weak self] in
          guard let self else { return }
          if count > 0 {
            self.register(10, kVK_ANSI_Y)
            self.register(11, kVK_ANSI_N)
          } else {
            self.unregister(10)
            self.unregister(11)
            if self.banner?.isApproval == true { self.dismissBanner() }
          }
        }
      }
      .store(in: &subscriptions)
    agents.$suggestion.compactMap { $0 }
      .sink { [weak self] signature in Task { @MainActor [weak self] in self?.present(.habit(signature)) } }
      .store(in: &subscriptions)
    // Friends can see which agent you're working with, if you allow it.
    agents.$live
      .map { live in live.values.first { $0.status == .working }.map { "Coding with \(AgentKind.find($0.agent)?.name ?? "an agent")" } }
      .removeDuplicates()
      .sink { [weak controller] doing in Task { @MainActor in controller?.social.doing = doing } }
      .store(in: &subscriptions)
    // Keep plan limits and GitHub fresh in the background.
    Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak controller] _ in
      Task { @MainActor in controller?.plans.refresh(); controller?.github.refresh() }
    }.tolerance = 30
    controller.plans.refresh(force: true)
    controller.github.refresh(force: true)
  }

  /// Shows a banner beside the closed notch, or on top of the open page. Approvals stay until
  /// answered; anything else fades after a few seconds. Finished tasks wait while you focus.
  func present(_ next: IslandBanner) {
    if banner?.isApproval == true && !next.isApproval { return }
    if case .finished = next, controller.focusing { return }
    if case .message = next, controller.focusing { return }
    bannerTimer?.cancel()
    if !expanded, let panel, let target = frame(for: size(for: next)) {
      resize?.cancel()
      // Grow the window first so the content can animate into it.
      if target.height >= panel.frame.height || target.width >= panel.frame.width { panel.setFrame(target, display: true) }
      panel.orderFrontRegardless()
    }
    animate(response: 0.45, damping: 0.78) { self.banner = next }
    if !expanded, let panel, let target = frame(for: size(for: next)), panel.frame != target {
      resize = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard let self, !Task.isCancelled, !self.expanded, self.banner == next else { return }
        panel.setFrame(target, display: true)
      }
    }
    if !next.isApproval {
      bannerTimer = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        guard !Task.isCancelled else { return }
        self?.dismissBanner()
      }
    }
  }
  func dismissBanner() {
    bannerTimer?.cancel()
    if case .habit = banner { controller.agents.suggestion = nil }
    // Another approval may be waiting.
    if !controller.agents.pending.isEmpty, banner?.isApproval != true {
      banner = nil
      present(.approval(controller.agents.pending[0].id))
      return
    }
    animate(response: 0.36, damping: 0.92) { self.banner = nil }
    if !expanded { settle(after: reducedMotion ? 0 : 0.4) }
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
    controller.hub.editing = false
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
      if self.liveActivity || self.banner != nil, let target = self.frame(for: self.collapsedSize) {
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
    if show, !expanded, banner == nil, let panel, let target = frame(for: CGSize(width: notchWidth + 2 * (headerHeight + 8), height: headerHeight)) {
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
      guard hoverToOpen, banner == nil, NSEvent.pressedMouseButtons == 0 else { hoverSince = nil; return }
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
    } else if openedByHover, !panel.isKeyWindow, !dragging {
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
  @ObservedObject var account: AccountController
  @ObservedObject var social: SocialController
  @ObservedObject var hub: HubController
  @ObservedObject var actions: QuickActions
  @ObservedObject var agents: AgentController
  @AppStorage("islandAccent") private var accent = "blue"
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  private var reduced: Bool { controller.companion.preferences.reducedMotion || systemReduced }
  private var motion: Animation? { reduced ? nil : .spring(response: 0.34, dampingFraction: 0.86) }
  static let tabs: [(route: String, title: String, icon: String)] = [
    ("Notch", "Home", "house.fill"), ("Hub", "Hub", "square.grid.2x2.fill"), ("Play", "Play", "gamecontroller.fill"),
    ("Molting", "Molting", "person.2.fill"),
  ]
  static let tools: [(route: String, title: String, icon: String)] = [
    ("Lens", "Ask about your screen (⌘⇧L)", "text.viewfinder"), ("Agents", "Agents (⌃⌥A)", "terminal.fill"),
    ("Ask Molt", "Chat", "bubble.left.fill"), ("Settings", "Settings", "gearshape.fill"),
  ]
  private var signedIn: Bool { account.phase == .signedIn }
  init(controller: PetController, coordinator: IslandCoordinator) {
    self.controller = controller
    self.coordinator = coordinator
    self.assistant = controller.assistant
    self.media = controller.hub.media
    self.account = controller.account
    self.social = controller.social
    self.hub = controller.hub
    self.actions = controller.hub.actions
    self.agents = controller.agents
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
      if let banner = coordinator.banner, !coordinator.expanded {
        VStack(spacing: 0) {
          Color.clear.frame(height: coordinator.hasNotch ? coordinator.headerHeight : 6)
          IslandBannerView(
            banner: banner, agents: agents, appearance: controller.companion.appearance,
            dismiss: { coordinator.dismissBanner() },
            open: { route in UserDefaults.standard.set(route, forKey: "agentsTab"); controller.tab = "Agents"; coordinator.open() })
        }
        .frame(width: collapsed.width, height: collapsed.height, alignment: .top)
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
      } else if coordinator.liveActivity && !coordinator.expanded && actions.recording == nil
        && (agents.needsYou || !agents.working.isEmpty)
      {
        AgentWings(agents: agents, appearance: controller.companion.appearance, notchWidth: coordinator.notchWidth, height: collapsed.height)
          .frame(width: collapsed.width, height: collapsed.height)
          .contentShape(Rectangle())
          .onTapGesture { UserDefaults.standard.set("Live", forKey: "agentsTab"); controller.tab = "Agents"; coordinator.open() }
          .transition(.opacity)
      } else if coordinator.liveActivity && !coordinator.expanded {
        NotchLiveActivity(media: media, actions: actions, notchWidth: coordinator.notchWidth, height: collapsed.height)
          .frame(width: collapsed.width, height: collapsed.height)
          .contentShape(Rectangle())
          .onTapGesture {
            if actions.recording != nil { actions.stopRecording() } else { controller.tab = "Notch"; coordinator.open() }
          }
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
    .onExitCommand { coordinator.collapse() }
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
      page
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(NotchPageMotion(route: controller.tab))
    }
    .foregroundStyle(.white)
    .buttonStyle(NotchButtonStyle())
    .overlay(alignment: .top) {
      if signedIn, let banner = coordinator.banner {
        IslandBannerView(
          banner: banner, agents: agents, appearance: controller.companion.appearance,
          dismiss: { coordinator.dismissBanner() },
          open: { route in UserDefaults.standard.set(route, forKey: "agentsTab"); controller.tab = "Agents" })
          .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.11)).shadow(color: .black.opacity(0.5), radius: 12, y: 4))
          .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
          .padding(.horizontal, 30)
          .padding(.top, coordinator.headerHeight + 6)
          .transition(.move(edge: .top).combined(with: .opacity))
      } else if signedIn, controller.tab != "Molting", let invite = social.invites.first {
        HStack(spacing: 8) {
          Image(systemName: "figure.2").foregroundStyle(Color.accentColor)
          Text("@\(invite.from.username) wants to hang out").font(.system(size: 12, weight: .semibold))
          Button("Join") { social.accept(invite); controller.tab = "Molting" }
          Button("Later") { social.decline(invite) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(Color(white: 0.14)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .padding(.top, coordinator.headerHeight + 6)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottom) {
      if let error = controller.error {
        Text(error).font(.system(size: 11, weight: .medium)).lineLimit(1)
          .padding(.horizontal, 12).frame(height: 26)
          .background(Capsule().fill(Color(white: 0.16)))
          .padding(.bottom, 10)
          .onTapGesture { controller.error = nil }
          .task(id: error) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if controller.error == error { controller.error = nil }
          }
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .animation(motion, value: controller.tab)
    .animation(motion, value: controller.error)
    .animation(motion, value: social.invites)
    .animation(motion, value: coordinator.banner)
  }

  @ViewBuilder private var page: some View {
    if !signedIn {
      AccountGate(account: account, appearance: controller.companion.appearance)
    } else {
      signedInPage
    }
  }
  @ViewBuilder private var signedInPage: some View {
    switch controller.tab {
    case "Hub": HubView(controller: controller, hub: controller.hub)
    case "Molting": MoltingView(social: social, account: account, appearance: controller.companion.appearance)
    case "Lens": LensView(lens: coordinator.lens)
    case "Health": HealthDetailView(detail: coordinator.health, controller: controller)
    case "Play": PlayView(controller: controller)
    case "Sessions", "Agents": AgentsView(controller: controller)
    case "Wardrobe": WardrobeView(controller: controller)
    case "Ask Molt": PersonalChatView(assistant: assistant)
    case "Settings": SettingsView(controller: controller, coordinator: coordinator, accent: $accent)
    default: NotchHomeView(controller: controller, media: media)
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      HStack(spacing: 4) {
        if signedIn {
          ForEach(Self.tabs, id: \.route) { tab in tabButton(tab.route, tab.title, tab.icon) }
          if !Self.tabs.contains(where: { $0.route == controller.tab }) && !Self.tools.contains(where: { $0.route == controller.tab }) {
            tabButton(controller.tab, controller.tab, "chevron.right")
          }
        } else {
          Label("Molt", systemImage: "leaf.fill").font(.system(size: 12, weight: .semibold)).padding(.leading, 6)
        }
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity)
      if coordinator.hasNotch { Color.clear.frame(width: coordinator.notchWidth + 12) }
      HStack(spacing: 2) {
        Spacer(minLength: 0)
        if assistant.running || coordinator.lens.running {
          ProgressView().controlSize(.mini).padding(.trailing, 4)
        }
        if signedIn && controller.tab == "Hub" {
          Button { hub.editing.toggle() } label: {
            Image(systemName: hub.editing ? "checkmark" : "pencil").font(.system(size: 12, weight: .semibold))
          }
          .buttonStyle(NotchIconButtonStyle(size: 26, prominent: hub.editing))
          .background(Circle().fill(hub.editing ? Color.accentColor : Color.clear))
          .help(hub.editing ? "Done" : "Edit widgets").accessibilityLabel(hub.editing ? "Done editing" : "Edit widgets")
          .padding(.trailing, 4)
        }
        if signedIn {
          ForEach(Self.tools, id: \.route) { tool in
            Button { controller.tab = tool.route } label: {
              Image(systemName: tool.icon).font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(NotchIconButtonStyle(size: 26, prominent: controller.tab == tool.route))
            .background(Circle().fill(Color.white.opacity(controller.tab == tool.route ? 0.14 : 0)))
            .overlay(alignment: .topTrailing) {
              // A quiet nudge until two-factor authentication is on.
              if tool.route == "Settings" && !account.mfaEnabled && account.profile != nil {
                Circle().fill(Color.orange).frame(width: 6, height: 6).offset(x: -3, y: 3)
              }
            }
            .help(tool.title).accessibilityLabel(tool.title)
            .accessibilityAddTraits(controller.tab == tool.route ? .isSelected : [])
          }
        }
      }.frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 14)
  }
  /// The selected tab shows its name; the others are icons, so four fit beside the notch.
  private func tabButton(_ route: String, _ title: String, _ icon: String) -> some View {
    let selected = controller.tab == route
    return Button {
      controller.tab = route
    } label: {
      HStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: 11, weight: .semibold))
        if selected { Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
      }
      .overlay(alignment: .topTrailing) {
        if route == "Molting" && !social.invites.isEmpty {
          Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: 4, y: -3)
        }
      }
      .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
      .padding(.horizontal, selected ? 10 : 8).frame(height: 24)
      .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
