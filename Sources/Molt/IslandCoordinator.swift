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
  /// What's going on beside the closed notch, in your order; a swipe moves through them.
  @Published private(set) var live: [LiveKind] = []
  @Published var liveIndex = 0
  /// What you've typed to jump somewhere, while the notch is open; nil when not searching.
  @Published var jump: String?
  @Published var jumpSelection = 0
  /// Option is held: shortcuts show beside what they do.
  @Published private(set) var optionHeld = false
  /// A file or link is being dragged over Molt.
  @Published private(set) var dropping = false
  /// The pointer is resting on the closed notch: it swells a little before it opens.
  @Published private(set) var peek: CGFloat = 0
  /// The closed notch is being pressed.
  @Published private(set) var pressed = false
  /// The pointer is over a compact approval, which grows into the full card.
  @Published var bannerHovered = false
  /// An app is full screen on this display, so the closed notch keeps to itself.
  @Published private(set) var fullScreen = false
  let prefs = NotchPrefs.shared
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
  let controller: PetController
  let lens: LensController
  let health = HealthDetailController()
  private var panel: FloatingPanel?
  private var screen: NSScreen?
  private var previousApp: NSRunningApplication?
  private var handler: EventHandlerRef?
  private var hoverTimer: Timer?
  private var hoverSince: Date?
  private var outsideSince: Date?
  private var openedByHover = false
  /// A drag in progress (for example, feeding Molt) keeps a hover-opened notch open.
  var dragging: Bool { NSEvent.pressedMouseButtons != 0 }
  private var resize: Task<Void, Never>?
  private var subscriptions = Set<AnyCancellable>()
  private var monitors: [Any] = []
  private var swipe: CGFloat = 0
  private var dragCount = NSPasteboard(name: .drag).changeCount
  /// The page to go back to when a drag leaves without dropping.
  private var beforeDrop: String?
  /// A drop target took the drop; it closes things itself once it's done.
  private var dropClaimed = false
  private var releasedAt: Date?
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
    panel.ignoresMouseEvents = true
    panel.acceptsMouseMovedEvents = true
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
    Publishers.MergeMany(
      media.$isPlaying.map { _ in () }.eraseToAnyPublisher(), media.$track.map { _ in () }.eraseToAnyPublisher(),
      actions.$recording.map { _ in () }.eraseToAnyPublisher(), agents.$live.map { _ in () }.eraseToAnyPublisher(),
      agents.$pending.map { _ in () }.eraseToAnyPublisher(), controller.$organization.map { _ in () }.eraseToAnyPublisher(),
      controller.$health.map { _ in () }.eraseToAnyPublisher(), prefs.$priority.map { _ in () }.eraseToAnyPublisher(),
      prefs.$petReacts.map { _ in () }.eraseToAnyPublisher(), prefs.$liveOff.map { _ in () }.eraseToAnyPublisher(),
      prefs.$featuresOff.map { _ in () }.eraseToAnyPublisher())
      .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
      .sink { [weak self] in self?.refreshLive() }
      .store(in: &subscriptions)
    lens.hide = { [weak self] in self?.collapse() }
    lens.openChat = { [weak controller] in controller?.tab = "Ask Molt" }
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
    let hub = controller.hub
    hub.timers.onAlert = { [weak self] text, symbol in self?.present(.notice(text, symbol: symbol == "alarm" ? "alarm.fill" : "timer")) }
    hub.daily.onBreak = { [weak self, weak controller] text, symbol in
      controller?.mood = symbol == "drop.fill" ? "drinking" : "happy"
      self?.present(.notice(text, symbol: symbol))
    }
    hub.daily.onHabitStreak = { [weak controller] habit in
      controller?.poked = Date()
      if habit.streak(at: Date()) >= 3 { controller?.mood = "celebrating" }
    }
    if prefs.has("clipboard") { hub.clipboard.start() }
    prefs.$featuresOff.map { !$0.contains("clipboard") }.removeDuplicates()
      .sink { [weak hub] on in if on { hub?.clipboard.start() } else { hub?.clipboard.stop() } }
      .store(in: &subscriptions)
    // The open notch fits what's on the page: the tab, the Hub's rows, search results.
    Publishers.MergeMany(
      controller.$tab.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
      controller.hub.$saved.map { _ in () }.eraseToAnyPublisher(), controller.hub.$editing.map { _ in () }.eraseToAnyPublisher(),
      $jump.map { _ in () }.eraseToAnyPublisher(), prefs.$fitContent.map { _ in () }.eraseToAnyPublisher())
      .dropFirst()
      .sink { [weak self] in Task { @MainActor [weak self] in self?.updateHitTesting() } }
      .store(in: &subscriptions)
    $jump.map { $0 == nil }.removeDuplicates().sink { [weak self] _ in self?.jumpSelection = 0 }.store(in: &subscriptions)
    watchInput()
    reposition()
    controller.dashboardVisible = false
    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.trackPointer() }
    }
    hoverTimer?.tolerance = 0.03
  }

  // MARK: Geometry

  /// Height of the band beside the hardware notch; the header lives here.
  var headerHeight: CGFloat { hasNotch ? max(28, safeTop) : 34 }
  /// Home's footprint; with "Fit to content" off, no page is smaller.
  static let bodyHeight: CGFloat = 176
  /// One row of Hub widgets, and the space around the rows.
  static let hubRow: CGFloat = 152, hubGap: CGFloat = 10
  var expandedSize: CGSize { CGSize(width: bodyWidth(for: controller.tab), height: headerHeight + bodyHeight(for: controller.tab)) }
  /// Narrow pages make a narrower notch, as in the mockups.
  func bodyWidth(for route: String) -> CGFloat {
    guard controller.account.phase == .signedIn, prefs.fitContent else { return 720 }
    if jump != nil { return 600 }
    switch route {
    case "Focus": return 640
    case "Drop": return 600
    default: return 720
    }
  }
  func bodyHeight(for route: String) -> CGFloat {
    guard controller.account.phase == .signedIn else { return Self.bodyHeight }
    if let query = jump { return JumpView.height(results: jumpResults(query).count) }
    let height: CGFloat
    switch route {
    case "Hub":
      // While editing, an empty row can show where another widget could go.
      let rows = HubView.rows(controller.hub.layout, editing: controller.hub.editing, limit: controller.hub.rows).count
      height = 20 + CGFloat(rows) * Self.hubRow + CGFloat(rows - 1) * Self.hubGap
    case "Focus": height = 170
    case "Drop": height = 166
    case "AddWidget": height = 300
    case "NotchSettings": height = 214
    default: height = Self.bodyHeight
    }
    return prefs.fitContent ? height : max(Self.bodyHeight, height)
  }
  /// Each kind of live activity needs a little more or less room beside the notch.
  var wing: CGFloat {
    guard liveActivity, let kind = currentLive else { return 0 }
    switch kind {
    case .focus: return 86
    case .battery: return 96
    default: return headerHeight + 8
    }
  }
  var currentLive: LiveKind? { live.isEmpty ? nil : live[liveIndex % live.count] }
  var collapsedSize: CGSize {
    if banner != nil { return bannerSize }
    let wing = fullScreen ? 0 : self.wing
    return CGSize(width: notchWidth + 2 * wing + 14 * peek, height: (hasNotch ? headerHeight : 0) + 3 * peek)
  }
  var bannerSize: CGSize { size(for: banner) }
  func size(for banner: IslandBanner?) -> CGSize {
    var height: CGFloat = 58
    if banner?.isApproval == true, prefs.compactApprovals, !bannerHovered, !expanded {
      // A pill beside the notch: who's asking, and Allow or Deny.
      return CGSize(width: notchWidth + 2 * 150, height: headerHeight)
    }
    if banner?.isApproval == true {
      // Questions need room for their options; edits for their diff.
      let item = controller.agents.pending.first
      let options = item?.questions.map(\.options.count).max() ?? 0
      height = item?.isQuestion == true ? QuestionCard.height(options: options) : item?.change != nil ? 104 + DiffPreview.height - 24 : 104
    }
    return CGSize(width: min(680, max(notchWidth + 380, 600)), height: headerHeight + height)
  }
  var reducedMotion: Bool {
    controller.companion.preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
  /// The window is this big and never moves: only the notch drawn inside it changes, so nothing
  /// jumps while it animates. Everywhere outside the notch lets clicks through.
  static let canvas = CGSize(width: 720 + 2 * flare + 96, height: 640)
  /// Where the notch is drawn right now, in screen coordinates.
  var shapeRect: CGRect {
    guard let screen else { return .zero }
    let size = booting ? bootSize : expanded ? expandedSize : collapsedSize
    let width = max(size.width, hasNotch ? notchWidth : 0) + 2 * Self.flare
    let height = max(size.height, hasNotch ? headerHeight : 6)
    return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
  }
  enum Motion { case open, close, morph, peek, press }
  /// The springs everything moves with; nil with Reduce Motion on.
  func animation(_ motion: Motion) -> Animation? {
    guard !reducedMotion else { return nil }
    let speed = prefs.animationSpeed
    switch motion {
    case .open: return .spring(response: 0.5 / speed, dampingFraction: 0.8)
    case .close: return .spring(response: 0.34 / speed, dampingFraction: 1).delay(0.04)
    case .morph: return .spring(response: 0.42 / speed, dampingFraction: 0.86)
    case .peek: return .spring(response: 0.3 / speed, dampingFraction: 0.68)
    case .press: return .spring(response: 0.18, dampingFraction: 0.6)
    }
  }
  func animate(_ motion: Motion, _ change: @escaping () -> Void) {
    if let animation = animation(motion) { withAnimation(animation, change) } else { change() }
  }

  // MARK: Shortcut

  /// Registers every shortcut, from your bindings in Settings › Shortcuts (or the defaults).
  /// Allow and Deny exist only while an approval waits.
  func registerShortcut() {
    for (_, key) in keys { UnregisterEventHotKey(key) }
    keys = [:]
    UserDefaults.standard.set(shortcutChoice, forKey: "islandShortcut")
    let open = register(1)
    for action in HotKeys.actions where action.id != 1 && action.id != 10 && action.id != 11 { register(action.id) }
    if !controller.agents.pending.isEmpty { register(10); register(11) }
    let lens = HotKeys.describe(HotKeys.binding(2))
    shortcutMessage = open
      ? "\(HotKeys.describe(HotKeys.binding(1))) opens Molt · \(lens) asks about your screen"
      : "That shortcut is taken by another app. Choose another in Settings › Shortcuts."
  }
  static var shortcutList: [(String, String)] {
    HotKeys.actions.map { (HotKeys.describe(HotKeys.binding($0.id)), $0.title) }
  }
  @discardableResult private func register(_ id: UInt32) -> Bool {
    guard keys[id] == nil, let binding = HotKeys.binding(id) else { return false }
    var ref: EventHotKeyRef?
    if RegisterEventHotKey(UInt32(binding.key), binding.modifiers, EventHotKeyID(signature: 0x4D4F_4C54, id: id), GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
      keys[id] = ref
      return true
    }
    return false
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
    case 12: controller.focus(minutes: UserDefaults.standard.object(forKey: "focusMinutes") as? Int ?? 25); show("Focus")
    case 13: show("Hub")
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

  /// For screenshots: the wake-up animation, `seconds` in.
  func preview(bootAt seconds: Double) {
    expanded = false
    booting = true
    reveal = 1
    bootStarted = Date().addingTimeInterval(-seconds)
  }
  /// For screenshots: live activities beside the closed notch.
  func preview(live kinds: [LiveKind], index: Int = 0) {
    banner = nil
    expanded = false
    reveal = 0
    live = kinds
    liveIndex = index
    liveActivity = !kinds.isEmpty
  }
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
            self.register(10)
            self.register(11)
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
    bannerHovered = false
    animate(.open) { self.banner = next }
    updateHitTesting()
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
    animate(.close) { self.banner = nil; self.bannerHovered = false }
    updateHitTesting()
  }

  // MARK: Open and close

  func open(hover: Bool = false) {
    guard let panel else { return }
    if !expanded {
      openedByHover = hover
      if !hover { previousApp = NSWorkspace.shared.frontmostApplication }
    } else if !hover {
      openedByHover = false
    }
    outsideSince = nil
    controller.dashboardVisible = true
    controller.hub.media.active = true
    controller.refreshHealth()
    panel.orderFrontRegardless()
    if !hover {
      panel.makeKey()
      NSApp.activate(ignoringOtherApps: true)
    }
    if !expanded {
      // The shape springs open; the header and page follow a beat later (see IslandView).
      animate(.open) {
        self.expanded = true
        self.reveal = 1
        self.peek = 0
        self.pressed = false
      }
    }
    updateHitTesting()
  }
  func collapse() {
    guard expanded else { return }
    controller.hub.editing = false
    jump = nil
    dropping = false
    dropClaimed = false
    beforeDrop = nil
    openedByHover = false
    controller.dashboardVisible = false
    controller.hub.media.active = false
    // The page fades first, then the shape settles back without a bounce.
    if reducedMotion {
      expanded = false
      reveal = 0
    } else {
      withAnimation(.easeOut(duration: 0.1)) { expanded = false }
      animate(.close) { self.reveal = 0 }
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier
      == ProcessInfo.processInfo.processIdentifier
    {
      previousApp?.activate(options: [])
    }
    panel?.resignKey()
    updateHitTesting()
  }
  /// Puts the window over the top of the screen, once per display change.
  private func placePanel() {
    guard let panel, let screen else { return }
    let size = CGSize(width: min(Self.canvas.width, screen.frame.width), height: min(Self.canvas.height, screen.frame.height * 0.8))
    let frame = IslandGeometry.frame(screen: screen.frame, visible: screen.frame, size: size)
    if panel.frame != frame { panel.setFrame(frame, display: true) }
    panel.orderFrontRegardless()
    updateHitTesting()
  }
  /// Clicks reach the notch only where it's drawn; everywhere else they pass to the app below.
  func updateHitTesting() {
    guard let panel else { return }
    let inside = shapeRect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) || dropping || overlayActive
    if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
  }
  var overlayActive: Bool { false }
  /// Molt's wake-up animation is playing.
  @Published private(set) var booting = false
  private(set) var bootStarted = Date()
  private var bootTask: Task<Void, Never>?
  private var afterBoot: (() -> Void)?
  /// The tour is running: the notch stays open while you click its speech bubbles.
  var touring = false
  /// Where the tabs and tools are drawn, in the window, for the tour to point at.
  var anchors: [String: CGRect] = [:]
  var bootSize: CGSize { CGSize(width: 420, height: headerHeight + 170) }
  /// Plays the wake-up animation, then runs `then`. With Reduce Motion on, it goes straight on.
  func boot(then: @escaping () -> Void = {}) {
    guard let panel, !reducedMotion else { then(); return }
    bootStarted = Date()
    afterBoot = then
    panel.orderFrontRegardless()
    animate(.open) {
      self.booting = true
      self.reveal = 1
    }
    updateHitTesting()
    bootTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(BootView.length * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.finishBoot()
    }
  }
  func finishBoot() {
    guard booting else { return }
    bootTask?.cancel()
    let next = afterBoot
    afterBoot = nil
    withAnimation(.easeOut(duration: 0.14)) { booting = false }
    if !expanded { animate(.close) { self.reveal = 0 } }
    updateHitTesting()
    next?()
  }
  /// Brings the notch in front of the tour's dimming, so it stays clickable.
  func raisePanel() { panel?.orderFrontRegardless() }
  /// An anchor reported by the island view, in screen coordinates.
  func screenRect(_ anchor: String) -> CGRect? {
    guard let panel, let rect = anchors[anchor] else { return nil }
    return CGRect(x: panel.frame.minX + rect.minX, y: panel.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
  }
  /// Works out what's going on, in your order, and fits the closed notch to the one showing.
  private func refreshLive() {
    let agents = controller.agents, media = controller.hub.media
    var active = Set<LiveKind>()
    if agents.needsYou || !agents.working.isEmpty { active.insert(.agents) }
    if controller.hub.actions.recording != nil { active.insert(.recording) }
    if controller.organization.sessions.contains(where: { $0.finished == nil }) { active.insert(.focus) }
    if media.isPlaying && media.track != nil { active.insert(.music) }
    if controller.lowBattery { active.insert(.battery) }
    active = active.filter { !prefs.liveOff.contains($0.rawValue) && prefs.shows($0.rawValue) }
    if active.contains(.battery) && !live.contains(.battery) && !batteryNoted {
      batteryNoted = true
      present(.notice("\(controller.petName)'s running low with your Mac. Plug in to wake it up.", symbol: "battery.25"))
    } else if !controller.lowBattery {
      batteryNoted = false
    }
    let next = NotchLayout.live(active, priority: prefs.priority)
    let shown = currentLive
    // Something more important than what's showing comes to the front.
    var index = 0
    if let first = next.first, live.contains(first), let shown, let at = next.firstIndex(of: shown) { index = at }
    if next != live || index != liveIndex {
      animate(.morph) {
        self.live = next
        self.liveIndex = index
      }
    }
    setLiveActivity(!next.isEmpty)
    updateHitTesting()
  }
  /// Shows the next live activity, after a swipe on the closed notch.
  func cycleLive(_ step: Int) {
    guard live.count > 1 else { return }
    animate(.morph) { self.liveIndex = (self.liveIndex + step + self.live.count) % self.live.count }
    updateHitTesting()
  }
  private func setLiveActivity(_ playing: Bool) {
    let show = playing && hasNotch
    guard show != liveActivity else { return }
    animate(.morph) { self.liveActivity = show }
  }
  /// Whether the app in front is full screen on the notch's display.
  private func checkFullScreen() {
    guard prefs.hideInFullScreen, let screen, !expanded else {
      if fullScreen { animate(.morph) { self.fullScreen = false } }
      return
    }
    let mine = ProcessInfo.processInfo.processIdentifier
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // The primary display's top-left origin, for converting Quartz window bounds.
    let primary = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let target = CGRect(x: screen.frame.minX, y: primary - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    let covering = list.contains { info in
      guard (info[kCGWindowLayer as String] as? Int) == 0, let pid = info[kCGWindowOwnerPID as String] as? pid_t,
        pid != mine, pid == front, let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
      else { return false }
      let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
      return rect.equalTo(target)
    }
    if covering != fullScreen { animate(.morph) { self.fullScreen = covering } }
  }

  // MARK: Hover

  private func trackPointer() {
    guard let screen, let panel else { return }
    let mouse = NSEvent.mouseLocation
    let now = Date()
    let pressed = NSEvent.pressedMouseButtons != 0
    let board = NSPasteboard(name: .drag)
    if !pressed { dragCount = board.changeCount }
    // A file or link dragged up to the notch opens it to catch the drop.
    if pressed, board.changeCount != dragCount, controller.account.phase == .signedIn,
      board.canReadObject(forClasses: [NSURL.self], options: nil)
    {
      let size = expanded ? expandedSize : collapsedSize
      let width = max(size.width, hasNotch ? notchWidth + 120 : 260) + 2 * Self.flare
      let height = expanded ? size.height : (hasNotch ? headerHeight : 4) + 24
      let zone = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height + 1)
      if zone.contains(mouse) && !dropping { startDrop() }
    } else if dropping && !pressed && !dropClaimed {
      // Released somewhere other than one of the drop targets. A drop is delivered a moment after
      // the button comes up, so wait briefly before giving up on it.
      if let releasedAt, now.timeIntervalSince(releasedAt) > 0.35 { endDrop() } else if releasedAt == nil { releasedAt = now }
    }
    if pressed { releasedAt = nil }
    updateHitTesting()
    if Int(now.timeIntervalSinceReferenceDate * 12.5) % 12 == 0 { checkFullScreen() }
    if !expanded {
      let size = collapsedSize
      let width = max(size.width, hasNotch ? notchWidth : 200) + 2 * Self.flare
      let height = max(size.height, hasNotch ? headerHeight : 4)
      let zone = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height + 1)
      let over = zone.contains(mouse) && !pressed && !booting
      // A compact approval grows into the full card while the pointer is on it.
      if banner?.isApproval == true && prefs.compactApprovals {
        let card = shapeRect.insetBy(dx: -10, dy: -10)
        if (over || card.contains(mouse)) != bannerHovered { animate(.morph) { self.bannerHovered.toggle() } }
      }
      let peeks = over && banner == nil && (hoverToOpen || prefs.openOnClick)
      if (peeks ? 1 : 0) != peek { animate(.peek) { self.peek = peeks ? 1 : 0 } }
      guard hoverToOpen, banner == nil, !pressed else { hoverSince = nil; return }
      if over {
        if let since = hoverSince, now.timeIntervalSince(since) > prefs.hoverDelay {
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
      if shapeRect.insetBy(dx: -8, dy: -8).contains(mouse) {
        outsideSince = nil
      } else if let since = outsideSince, now.timeIntervalSince(since) > 0.3 {
        collapse()
      } else if outsideSince == nil {
        outsideSince = now
      }
    }
  }

  // MARK: Dropping on Molt

  private func startDrop() {
    dropping = true
    if controller.tab != "Drop" { beforeDrop = expanded ? controller.tab : nil }
    jump = nil
    controller.tab = "Drop"
    if !expanded { open(hover: true) }
  }
  /// A drop target calls this as soon as something lands on it.
  func claimDrop() { dropClaimed = true }
  /// After a drop, or when a drag ends elsewhere: back to the page you were on, or closed.
  func endDrop(keepOpen: Bool = false) {
    guard dropping else { return }
    dropping = false
    dropClaimed = false
    releasedAt = nil
    if let page = beforeDrop {
      controller.tab = page
    } else if !keepOpen {
      collapse()
    }
    beforeDrop = nil
  }
  /// The Share menu for dropped items, under the notch.
  func share(_ urls: [URL]) {
    guard let view = panel?.contentView, !urls.isEmpty else { return }
    let picker = NSSharingServicePicker(items: urls)
    let bottom = view.isFlipped ? expandedSize.height : view.bounds.maxY - expandedSize.height
    let rect = NSRect(x: view.bounds.midX - 1, y: bottom, width: 2, height: 2)
    picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
  }

  // MARK: Typing, Option and swipes

  private func watchInput() {
    monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      return self.key(event) ? nil : event
    } as Any)
    monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
      if self?.optionHeld != held { self?.optionHeld = held }
      return event
    } as Any)
    monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, !self.expanded, self.banner == nil, event.window === self.panel else { return event }
      if event.phase == .began || event.phase == .mayBegin { self.swipe = 0; self.pull = 0; self.swipeLocked = false }
      // One step per gesture: after it acts, the rest of it (and its momentum) is ignored.
      if !self.swipeLocked {
        self.swipe += event.scrollingDeltaX
        // Fingers moving down, whichever way scrolling is set.
        self.pull += event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        if abs(self.swipe) > 24 && abs(self.swipe) > abs(self.pull) && self.live.count > 1 {
          self.cycleLive(self.swipe < 0 ? 1 : -1)
          self.swipeLocked = true
        } else if self.pull > 18 && self.prefs.openOnScroll {
          self.controller.tab = "Notch"
          self.open()
          self.swipeLocked = true
        }
      }
      if event.phase == .ended || event.phase == .cancelled { self.swipe = 0; self.pull = 0 }
      if event.momentumPhase == .ended { self.swipeLocked = false }
      return nil
    } as Any)
    monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
      guard let self, event.window === self.panel, !self.expanded, self.banner == nil else { return event }
      let down = event.type == .leftMouseDown
      if down != self.pressed { self.animate(.press) { self.pressed = down } }
      return event
    } as Any)
    // Clicks pass through everywhere but the notch; this keeps that exact as the pointer moves.
    let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
    monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moved) { [weak self] _ in self?.updateHitTesting() } as Any)
    monitors.append(NSEvent.addLocalMonitorForEvents(matching: moved) { [weak self] event in self?.updateHitTesting(); return event } as Any)
  }
  private var swipeLocked = false
  private var batteryNoted = false
  private var pull: CGFloat = 0
  /// Handles a key press in the open notch. Returns true when it was used.
  private func key(_ event: NSEvent) -> Bool {
    guard expanded, let panel, event.window === panel, controller.account.phase == .signedIn else { return false }
    let mods = event.modifierFlags.intersection([.command, .control])
    if jump != nil {
      switch event.keyCode {
      case 125: jumpSelection += 1; return true
      case 126: jumpSelection = max(0, jumpSelection - 1); return true
      case 53: jump = nil; return true
      default: return false
      }
    }
    guard prefs.typeToJump, mods.isEmpty, !(panel.firstResponder is NSText),
      let characters = event.characters, characters.count == 1,
      let scalar = characters.unicodeScalars.first,
      CharacterSet.alphanumerics.contains(scalar)
    else { return false }
    // Pages that are mostly typing, or a game, keep their keys.
    guard !["Ask Molt", "Lens", "Play"].contains(controller.tab), !dropping else { return false }
    jump = characters
    return true
  }
  /// Everything you can jump to, built fresh as the notch changes.
  func jumpResults(_ query: String) -> [JumpItem] { JumpSearch.rank(query, JumpCatalog.items(controller: controller), limit: 5) }

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
    if !hasNotch && liveActivity { liveActivity = false }
    placePanel()
  }
  func windowDidResignKey(_ notification: Notification) {
    // Native file pickers own focus temporarily; never collapse beneath them, or under the tour.
    guard expanded, !touring, NSApp.modalWindow == nil, panel?.attachedSheet == nil else { return }
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
  @ObservedObject var prefs: NotchPrefs
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
    self.prefs = coordinator.prefs
  }
  /// Pages one level down: a back arrow and their name replace the tabs.
  static let subpages: [String: (title: String, parent: String)] = [
    "Focus": ("Focus", "Notch"), "Health": ("Mac health", "Notch"), "Wardrobe": ("Wardrobe", "Play"),
    "NotchSettings": ("Notch", "Settings"), "Drop": ("Drop it on Molt", "Notch"), "AddWidget": ("Add a widget", "Hub"),
  ]
  var body: some View {
    let reveal = coordinator.reveal
    let collapsed = coordinator.collapsedSize
    let target = coordinator.booting ? coordinator.bootSize : coordinator.expandedSize
    let flare = IslandCoordinator.flare
    let width = collapsed.width + (target.width - collapsed.width) * reveal
    let height = collapsed.height + (target.height - collapsed.height) * reveal
    let corner = CGFloat(prefs.cornerScale)
    let shape = NotchShape(topRadius: flare * (0.6 + 0.4 * reveal), bottomRadius: 10 + (26 * corner - 10) * reveal)
    let collapsedClosed = !coordinator.expanded && coordinator.banner == nil
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        shape.fill(Color.black)
        if let banner = coordinator.banner, !coordinator.expanded {
          if banner.isApproval && prefs.compactApprovals && !coordinator.bannerHovered {
            CompactApproval(agents: agents, appearance: controller.companion.appearance, notchWidth: coordinator.notchWidth, height: collapsed.height)
              .frame(width: collapsed.width, height: collapsed.height)
              .transition(.opacity)
          } else {
            VStack(spacing: 0) {
              Color.clear.frame(height: coordinator.hasNotch ? coordinator.headerHeight : 6)
              IslandBannerView(
                banner: banner, agents: agents, appearance: controller.companion.appearance,
                dismiss: { coordinator.dismissBanner() },
                open: { route in UserDefaults.standard.set(route, forKey: "agentsTab"); controller.tab = "Agents"; coordinator.open() })
            }
            .frame(width: collapsed.width, height: collapsed.height, alignment: .top)
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
          }
        } else if coordinator.liveActivity && !coordinator.expanded && !coordinator.fullScreen, let kind = coordinator.currentLive {
          liveWings(kind, height: collapsed.height)
            .frame(width: collapsed.width, height: collapsed.height)
            .contentShape(Rectangle())
            .onTapGesture { openLive(kind) }
            .help(coordinator.live.count > 1 ? "Swipe sideways on the notch to see what else is going on" : "")
            .id(kind)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -4)), removal: .opacity))
        } else if collapsedClosed && prefs.openOnClick {
          // The bare notch: a click opens Home.
          Color.clear.contentShape(Rectangle())
            .frame(width: collapsed.width + 2 * flare, height: max(collapsed.height, 6))
            .onTapGesture { controller.tab = "Notch"; coordinator.open() }
        }
        if coordinator.booting {
          BootView(appearance: controller.companion.appearance, started: coordinator.bootStarted, top: coordinator.hasNotch ? coordinator.headerHeight - 10 : 0)
            .frame(width: target.width, height: target.height)
            .onTapGesture { coordinator.finishBoot() }
            .transition(.opacity)
        } else if coordinator.expanded {
          expandedContent
            .frame(width: target.width, height: target.height, alignment: .top)
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
        }
      }
      .frame(width: width + 2 * flare, height: max(0, height), alignment: .top)
      .clipShape(shape)
      // A soft shadow that grows as the notch opens.
      .background(alignment: .top) {
        shape.fill(Color.black)
          .frame(width: width + 2 * flare, height: max(0, height))
          .shadow(color: .black.opacity(0.34 * reveal), radius: 24 * reveal, y: 12 * reveal)
      }
      .overlay {
        if coordinator.dropping {
          shape.stroke(MoltTheme.body(controller.companion.appearance.palette).opacity(0.55), lineWidth: 1.5)
            .frame(width: width + 2 * flare, height: max(0, height))
            .transition(.opacity)
        }
      }
      .scaleEffect(coordinator.pressed ? 0.97 : 1, anchor: .top)
      // Which of several things beside the notch is showing; swipe for the others.
      if collapsedClosed && coordinator.liveActivity && !coordinator.fullScreen && coordinator.live.count > 1 {
        LiveDots(count: coordinator.live.count, index: coordinator.liveIndex % coordinator.live.count)
          .padding(.top, 6)
          .transition(.opacity.combined(with: .offset(y: -3)))
      }
    }
    .animation(coordinator.animation(.morph), value: target)
    .animation(coordinator.animation(.morph), value: collapsed)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .environment(\.moltReducedMotion, controller.companion.preferences.reducedMotion)
    .environment(\.colorScheme, .dark)
    .preferredColorScheme(.dark)
    .tint(MoltTheme.accent(accent))
    .accentColor(MoltTheme.accent(accent))
    .onChange(of: coordinator.displayChoice) { _ in coordinator.reposition() }
    .onPreferenceChange(AnchorKey.self) { coordinator.anchors = $0 }
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
      if signedIn && coordinator.jump != nil {
        // Searching: the band beside the notch stays clear, as in the mockup.
        Color.clear.frame(height: coordinator.headerHeight)
      } else if controller.tab != "Drop" || !signedIn {
        header.frame(height: coordinator.headerHeight)
          .modifier(Entrance(delay: 0.05, motion: coordinator.animation(.open)))
      }
      Group {
        if signedIn, let query = coordinator.jump {
          JumpView(coordinator: coordinator, query: Binding(get: { coordinator.jump ?? query }, set: { coordinator.jump = $0 }))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        } else {
          page.modifier(NotchPageMotion(route: controller.tab))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .modifier(Entrance(delay: 0.11, motion: coordinator.animation(.open)))
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
    .animation(motion, value: coordinator.jump == nil)
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
    case "NotchSettings": NotchSettingsView(prefs: prefs, coordinator: coordinator)
    case "Focus": FocusPage(controller: controller)
    case "Drop": DropPage(controller: controller, coordinator: coordinator, hub: hub)
    case "AddWidget": WidgetGallery(controller: controller, hub: hub, prefs: prefs)
    default: NotchHomeView(controller: controller, media: media)
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      HStack(spacing: 4) {
        if signedIn, let sub = Self.subpages[controller.tab] {
          Button { if controller.tab == "Drop" { coordinator.endDrop(keepOpen: true) }; controller.tab = sub.parent } label: {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
              Text(Self.title(of: sub.parent)).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.6)).padding(.horizontal, 8).frame(height: 24).contentShape(Capsule())
          }
          .buttonStyle(.plain).help("Back").accessibilityLabel("Back to \(Self.title(of: sub.parent))")
          Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1, height: 12).padding(.horizontal, 2)
          Text(sub.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.leading, 4)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        } else if signedIn {
          HStack(spacing: 4) {
          ForEach(prefs.visibleTabs, id: \.self) { route in
            if let tab = Self.tabs.first(where: { $0.route == route }) { tabButton(tab.route, tab.title, tab.icon) }
          }
          if !Self.tabs.contains(where: { $0.route == controller.tab }) && !Self.tools.contains(where: { $0.route == controller.tab }) {
            tabButton(controller.tab, controller.tab, "chevron.right")
          }
          }
          .anchor("tabs")
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
        if signedIn, Self.subpages[controller.tab] != nil {
          if controller.tab == "AddWidget" {
            HStack(spacing: 5) {
              Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
              TextField("Search \(WidgetKind.catalog.filter { prefs.shows($0.id) }.count) widgets", text: $hub.pickerQuery)
                .textFieldStyle(.plain).font(.system(size: 11.5))
            }
            .padding(.horizontal, 10).frame(width: 160, height: 26)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .padding(.trailing, 6)
          }
          PageMenu(route: controller.tab, controller: controller, prefs: prefs)
        } else if signedIn {
          HStack(spacing: 2) {
          ForEach(Self.tools.filter { prefs.shows($0.route) }, id: \.route) { tool in
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
          .anchor("tools")
        }
      }.frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 14)
  }
  static func title(of route: String) -> String {
    tabs.first { $0.route == route }?.title ?? tools.first { $0.route == route }.map { $0.route == "Ask Molt" ? "Chat" : $0.route } ?? route
  }
  @ViewBuilder private func liveWings(_ kind: LiveKind, height: CGFloat) -> some View {
    switch kind {
    case .agents:
      AgentWings(agents: agents, appearance: controller.companion.appearance, notchWidth: coordinator.notchWidth, height: height)
    case .focus:
      FocusWings(controller: controller, notchWidth: coordinator.notchWidth, height: height)
    case .battery:
      BatteryWings(controller: controller, notchWidth: coordinator.notchWidth, height: height)
    case .recording, .music:
      NotchLiveActivity(media: media, actions: actions, notchWidth: coordinator.notchWidth, height: height, showRecording: kind == .recording)
    }
  }
  private func openLive(_ kind: LiveKind) {
    switch kind {
    case .agents: UserDefaults.standard.set("Live", forKey: "agentsTab"); controller.tab = "Agents"
    case .recording: actions.stopRecording(); return
    case .focus: controller.tab = "Focus"
    case .battery: controller.tab = "Health"
    case .music: controller.tab = "Notch"
    }
    coordinator.open()
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
