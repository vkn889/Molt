import AppKit
import MoltCore
import SwiftUI

/// The first-run tour: the screen dims, a spotlight moves from feature to feature, and Molt
/// walks over to each one and explains it in a speech bubble, asking a few questions on the way
/// to set things up.
@MainActor final class Onboarding: ObservableObject {
  enum Target: Equatable { case none, island, tabs, tools, notch, menuBar }
  enum Kind: Equatable { case info, account, features, opening, color, calendar }
  struct Step {
    var title: String
    var body: String
    var page: String? = nil
    var target: Target = .island
    var kind: Kind = .info
    var mood = "happy"
    /// Search text to show, to demonstrate typing to jump.
    var jump: String? = nil
    /// The notch is closed for this step.
    var closed = false
  }
  @Published private(set) var index = 0
  @Published private(set) var active = false
  /// The spotlight, and where Molt stands, in the overlay's coordinates (top-left origin).
  @Published var hole: CGRect = .zero
  @Published var molt: CGPoint = .zero
  @Published var walking = false
  @Published var facingLeft = false
  private let controller: PetController
  private let coordinator: IslandCoordinator
  /// Where the menu bar icon is, from the app delegate.
  var menuBarFrame: () -> CGRect? = { nil }
  var onFinish: () -> Void = {}
  private var window: NSWindow?
  private var screen: NSScreen?
  private var waitForAccount: Task<Void, Never>?
  init(controller: PetController, coordinator: IslandCoordinator) {
    self.controller = controller
    self.coordinator = coordinator
  }

  var steps: [Step] {
    let name = controller.petName
    var steps = [Step(title: "Hi, I'm \(name)!", body: "I live in your notch. Let me show you around. It only takes a minute.", target: .notch, mood: "waving", closed: true)]
    if controller.account.phase != .signedIn {
      steps.append(Step(title: "First, your account", body: "Make one here so your \(name) is yours, on any Mac. I'll wait right here.", target: .island, kind: .account, mood: "idle"))
    }
    steps += [
      Step(title: "What should I help with?", body: "Pick what you'd like. You can change this any time in Settings.", target: .none, kind: .features, mood: "happy", closed: true),
      Step(title: "How should I open?", body: "Hover over the notch, click it, or both. Scrolling down on it works too.", target: .notch, kind: .opening, mood: "idle", closed: true),
      Step(title: "Pick my color", body: "I look good in all of them, honestly.", target: .none, kind: .color, mood: "love", closed: true),
    ]
    if coordinator.prefs.has("calendar") {
      steps.append(Step(title: "Can I peek at your calendar?", body: "I'll show what's next and count down to your meetings. I never change your events.", target: .none, kind: .calendar, mood: "idle", closed: true))
    }
    steps += [
      Step(title: "This is Home", body: "Your music, what's next today, and how your Mac is doing. I hang out along the bottom.", page: "Notch"),
      Step(title: "Pages live here", body: "Home, Hub, Play and Molting. Arrange them in Settings › Notch layout.", page: "Notch", target: .tabs, mood: "idle"),
      Step(title: "Your Hub", body: "Widgets you pick: clipboard, timers, calendar, batteries and lots more. Click the pencil to add or rearrange them.", page: "Hub"),
      Step(title: "Tools on the right", body: "Lens asks about your screen, Agents watches your coding agents, Chat talks to me, and Settings has everything else.", page: "Notch", target: .tools, mood: "idle"),
      Step(title: "Just start typing", body: "With the notch open, type to jump anywhere. Try \u{201C}focus 25\u{201D}.", page: "Notch", mood: "happy", jump: "foc"),
    ]
    if coordinator.prefs.has("focus") {
      steps.append(Step(title: "Focus with me", body: "Drag the ruler and press Start. I'll put on my glasses and work with you, and you'll see the time left beside the notch.", page: "Focus", mood: "working"))
    }
    steps += [
      Step(title: "Drop things on me", body: "Drag a file or link up to the notch to ask about it, keep it in your Tray, or share it.", target: .notch, mood: "love", closed: true),
      Step(title: "Beside the notch", body: "When I'm closed, I show what's going on: agents, recordings, focus, music. Swipe sideways on me to see the next one.", target: .notch, mood: "idle", closed: true),
      Step(title: "I'm in the menu bar too", body: "Click my icon for a quick look and shortcuts. Right-click for the classic menu.", target: .menuBar, mood: "waving", closed: true),
      Step(title: "That's everything!", body: "Hover over the notch whenever you need me. Take care of me and I'll grow.", target: .notch, mood: "celebrating", closed: true),
    ]
    return steps
  }
  var step: Step { let all = steps; return all[min(index, all.count - 1)] }
  var hoverToOpen: Bool {
    get { coordinator.hoverToOpen }
    set { objectWillChange.send(); coordinator.hoverToOpen = newValue }
  }
  var isLast: Bool { index >= steps.count - 1 }

  /// For screenshots: a step with its spotlight and Molt placed by hand.
  func preview(step: Int, hole: CGRect, molt: CGPoint) {
    index = step
    active = true
    self.hole = hole
    self.molt = molt
  }
  func start() {
    guard !active, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
    self.screen = screen
    let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.contentView = NSHostingView(rootView: OnboardingOverlay(tour: self, controller: controller, prefs: coordinator.prefs))
    window.setFrame(screen.frame, display: true)
    window.alphaValue = 0
    self.window = window
    active = true
    coordinator.touring = true
    index = 0
    molt = CGPoint(x: screen.frame.width / 2 - 260, y: 150)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    // The notch stays above the dimming, so it can be clicked during the tour.
    coordinator.raisePanel()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.35; window.animator().alphaValue = 1 }
    show()
  }
  func next() {
    guard active else { return }
    if isLast { finish(); return }
    index += 1
    show()
  }
  func back() {
    guard active, index > 0 else { return }
    index -= 1
    show()
  }
  func finish() {
    guard active else { return }
    waitForAccount?.cancel()
    active = false
    coordinator.touring = false
    coordinator.jump = nil
    UserDefaults.standard.set(true, forKey: "moltTourDone")
    let window = self.window
    NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; window?.animator().alphaValue = 0 }) { [weak self] in
      Task { @MainActor in
        window?.orderOut(nil)
        self?.window = nil
      }
    }
    coordinator.collapse()
    onFinish()
  }

  /// Shows the step: opens the right page, moves the spotlight, and walks Molt over.
  private func show() {
    let step = self.step
    if step.closed {
      coordinator.jump = nil
      coordinator.collapse()
    } else {
      if let page = step.page { controller.tab = page }
      coordinator.open()
      coordinator.jump = step.jump
    }
    if step.kind == .account { watchAccount() }
    // The notch takes a moment to reach its new size before the spotlight settles on it.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 380_000_000)
      self.place(step)
    }
  }
  private func place(_ step: Step) {
    guard let screen, active else { return }
    var rect: CGRect?
    switch step.target {
    case .none: rect = nil
    case .island: rect = coordinator.shapeRect
    case .tabs: rect = coordinator.screenRect("tabs")
    case .tools: rect = coordinator.screenRect("tools")
    case .notch:
      let notch = coordinator.shapeRect
      rect = notch.insetBy(dx: -40, dy: 0).offsetBy(dx: 0, dy: 0)
    case .menuBar: rect = menuBarFrame()
    }
    let local = rect.map { r in
      CGRect(x: r.minX - screen.frame.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height).insetBy(dx: -8, dy: -6)
    }
    // Molt stands below what it's talking about, a little to the left, or mid-screen.
    let width = screen.frame.width
    var point: CGPoint
    if let local {
      point = CGPoint(x: min(width - 380, max(60, local.midX - 200)), y: local.maxY + 70)
    } else {
      point = CGPoint(x: width / 2 - 230, y: screen.frame.height * 0.36)
    }
    point.y = min(screen.frame.height - 260, point.y)
    let distance = hypot(point.x - molt.x, point.y - molt.y)
    facingLeft = point.x < molt.x
    walking = distance > 30
    let duration = min(1.2, max(0.35, distance / 700))
    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { hole = local ?? .zero }
    withAnimation(.easeInOut(duration: duration)) { molt = point }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      self.walking = false
    }
  }
  private func watchAccount() {
    waitForAccount?.cancel()
    waitForAccount = Task { @MainActor [weak self] in
      while let self, !Task.isCancelled, self.active, self.step.kind == .account {
        if self.controller.account.phase == .signedIn { self.next(); return }
        try? await Task.sleep(nanoseconds: 400_000_000)
      }
    }
  }
}

/// The dimmed screen with a spotlight, Molt, and its speech bubble.
struct OnboardingOverlay: View {
  @ObservedObject var tour: Onboarding
  @ObservedObject var controller: PetController
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    let step = tour.step
    ZStack(alignment: .topLeading) {
      Spotlight(hole: tour.hole)
        .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
      if tour.hole != .zero {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
          .shadow(color: Color.accentColor.opacity(0.5), radius: 10)
          .frame(width: tour.hole.width, height: tour.hole.height)
          .offset(x: tour.hole.minX, y: tour.hole.minY)
          .allowsHitTesting(false)
      }
      HStack(alignment: .bottom, spacing: 14) {
        CreatureView(appearance: controller.companion.appearance, mood: tour.walking ? "idle" : step.mood, walking: tour.walking,
          facingLeft: tour.facingLeft, followsPointer: !tour.walking)
          .frame(width: 78, height: 72)
        bubble(step)
      }
      .offset(x: tour.molt.x, y: tour.molt.y)
    }
    .environment(\.colorScheme, .dark)
    .tint(MoltTheme.accent(UserDefaults.standard.string(forKey: "islandAccent") ?? "blue"))
    .onExitCommand { tour.finish() }
  }

  private func bubble(_ step: Onboarding.Step) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(step.title).font(.system(size: 16, weight: .bold))
      Text(step.body).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
      question(step.kind)
      HStack(spacing: 8) {
        Text("\(tour.index + 1) of \(tour.steps.count)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.white.opacity(0.4))
        Spacer()
        if !tour.isLast {
          Button("Skip tour") { tour.finish() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
        }
        if tour.index > 0 {
          Button("Back") { tour.back() }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
        }
        if step.kind != .account {
          Button(tour.isLast ? "Let's go" : tour.index == 0 ? "Show me" : "Next") { tour.next() }
            .buttonStyle(PillButtonStyle(tint: .accentColor)).keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(16)
    .frame(width: 330, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.11)))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    .foregroundStyle(.white)
    .id(tour.index)
    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tour.index)
  }

  @ViewBuilder private func question(_ kind: Onboarding.Kind) -> some View {
    switch kind {
    case .features:
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
        ForEach(NotchPrefs.features) { feature in
          let on = prefs.has(feature.id)
          Button { prefs.set(feature.id, on: !on) } label: {
            HStack(spacing: 6) {
              Image(systemName: feature.symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14)
              Text(feature.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
              Spacer(minLength: 0)
              Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                .foregroundStyle(on ? Color.accentColor : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(on ? 0.12 : 0.05)))
            .contentShape(Rectangle())
          }.buttonStyle(.plain).help(feature.detail)
        }
      }
    case .opening:
      let coordinatorHover = tour.hoverToOpen
      HStack(spacing: 6) {
        choice("Hover", selected: coordinatorHover && !prefs.openOnClick) { setOpening(hover: true, click: false) }
        choice("Click", selected: !coordinatorHover && prefs.openOnClick) { setOpening(hover: false, click: true) }
        choice("Both", selected: coordinatorHover && prefs.openOnClick) { setOpening(hover: true, click: true) }
      }
    case .color:
      HStack(spacing: 12) {
        ForEach(["sage", "ocean", "sunset", "violet"], id: \.self) { palette in
          let selected = controller.companion.appearance.palette == palette
          Button { controller.changeCompanion { $0.appearance.palette = palette } } label: {
            Circle().fill(MoltTheme.body(palette)).frame(width: 26, height: 26)
              .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 2).padding(-4))
          }.buttonStyle(.plain).accessibilityLabel(palette)
        }
      }.padding(.vertical, 4)
    case .calendar:
      HStack(spacing: 6) {
        Button("Allow calendar") {
          controller.contexts.enableCalendar { granted in
            controller.updateOrganization { $0.consent.calendar = granted }
            controller.updateOrganization { $0.consent.selectedCalendars = controller.contexts.calendars.map(\.calendarIdentifier) }
            controller.configureContext()
            if granted { tour.next() }
          }
        }.buttonStyle(PillButtonStyle(tint: .accentColor))
        Button("Not now") { tour.next() }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
      }
    case .account:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text("Waiting for you to sign in…").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
      }
    case .info: EmptyView()
    }
  }
  private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 28)
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.white.opacity(0.07)))
    }.buttonStyle(.plain)
  }
  private func setOpening(hover: Bool, click: Bool) {
    tour.hoverToOpen = hover
    prefs.openOnClick = click
  }
}

/// The whole screen with a rounded hole cut out; the hole animates between steps.
struct Spotlight: Shape {
  var hole: CGRect
  var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
    get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
    set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
  }
  func path(in rect: CGRect) -> Path {
    var path = Path(rect)
    if hole.width > 1 && hole.height > 1 {
      path.addRoundedRect(in: hole, cornerSize: CGSize(width: 20, height: 20), style: .continuous)
    }
    return path
  }
}
