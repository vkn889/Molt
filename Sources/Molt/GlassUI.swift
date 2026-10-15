import MoltCore
import AppKit
import SwiftUI

private struct MoltReducedMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
  var moltReducedMotion: Bool {
    get { self[MoltReducedMotionKey.self] }
    set { self[MoltReducedMotionKey.self] = newValue }
  }
}

/// A quiet grouped surface that sits on the notch's black, in the style of macOS widgets.
struct NotchSurface: View {
  var radius: CGFloat = 16
  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(Color(red: 0.075, green: 0.075, blue: 0.086))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
  }
}

struct NotchButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }
  private struct Styled: View {
    let configuration: Configuration
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.moltReducedMotion) private var reduced
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    var body: some View {
      configuration.label
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(configuration.isPressed ? 0.2 : hovered && enabled ? 0.14 : 0.09)))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(enabled ? 1 : 0.4)
        .animation(reduced || systemReduced ? nil : .easeOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }
  }
}

/// Draws the label exactly as given, dimming slightly while pressed. The system plain style can
/// restyle some symbol colors, which would hide an action's color.
struct BareButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// Borderless circular icon control used for media transport and header actions.
struct NotchIconButtonStyle: ButtonStyle {
  var size: CGFloat = 28
  var prominent = false
  func makeBody(configuration: Configuration) -> some View {
    Styled(configuration: configuration, size: size, prominent: prominent)
  }
  private struct Styled: View {
    let configuration: Configuration
    let size: CGFloat
    let prominent: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.moltReducedMotion) private var reduced
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    var body: some View {
      configuration.label
        .foregroundStyle(Color.white.opacity(prominent || hovered ? 1 : 0.78))
        .frame(width: size, height: size)
        .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.2 : hovered && enabled ? 0.12 : 0)))
        .contentShape(Circle())
        .scaleEffect(configuration.isPressed && !reduced && !systemReduced ? 0.9 : 1)
        .opacity(enabled ? 1 : 0.35)
        .animation(reduced || systemReduced ? nil : .easeOut(duration: 0.15), value: hovered)
        .animation(reduced || systemReduced ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
        .onHover { hovered = $0 }
    }
  }
}

struct NotchPageMotion: ViewModifier {
  var route: String
  @State private var visible = true
  @Environment(\.moltReducedMotion) private var reduced
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  func body(content: Content) -> some View {
    content.opacity(visible || reduced || systemReduced ? 1 : 0)
      .offset(y: visible || reduced || systemReduced ? 0 : 4)
      .task(id: route) {
        if CommandLine.arguments.contains("--render-preview") { visible = true; return }
        guard !reduced, !systemReduced else { visible = true; return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { visible = false }
        do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
        withAnimation(.easeOut(duration: 0.22)) { visible = true }
      }
  }
}

/// The silhouette of the MacBook notch: small outward flares where it meets the menu bar,
/// and continuous rounded corners at the bottom. Radii animate with the reveal.
struct NotchShape: Shape {
  var topRadius: CGFloat
  var bottomRadius: CGFloat
  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(topRadius, bottomRadius) }
    set { topRadius = newValue.first; bottomRadius = newValue.second }
  }
  func path(in rect: CGRect) -> Path {
    let top = min(topRadius, rect.width / 4)
    let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2))
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

/// How the open notch's header and page arrive: a beat after the shape starts to open, they
/// come into focus from a slight blur and scale. Leaving is a quick fade, handled by the parent.
struct Entrance: ViewModifier {
  var delay: Double
  var motion: Animation?
  @State private var shown = false
  func body(content: Content) -> some View {
    content
      .opacity(shown ? 1 : 0)
      .scaleEffect(shown ? 1 : 0.98, anchor: .top)
      .blur(radius: shown ? 0 : 6)
      .offset(y: shown ? 0 : -4)
      .onAppear {
        guard let motion, !CommandLine.arguments.contains("--render-preview") else { shown = true; return }
        withAnimation(motion.delay(delay)) { shown = true }
      }
  }
}

/// Frames of named parts of the notch, in its window, for the tour's spotlight.
struct AnchorKey: PreferenceKey {
  static var defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
extension View {
  func anchor(_ name: String) -> some View {
    background(GeometryReader { proxy in Color.clear.preference(key: AnchorKey.self, value: [name: proxy.frame(in: .global)]) })
  }
}

extension Notification.Name {
  /// Opens the Settings window, at the section in `object` when there is one.
  static let moltOpenSettings = Notification.Name("moltOpenSettings")
}

/// The "…" button that subpages show in place of the tools: that page's options, in a menu.
struct PageMenu: View {
  var route: String
  @ObservedObject var controller: PetController
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    Button(action: show) {
      Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white.opacity(0.6))
        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.08))).contentShape(Circle())
    }
    .buttonStyle(.plain).help("More").accessibilityLabel("More")
  }
  private var items: [(String, () -> Void)] {
    let settings: (String?) -> () -> Void = { section in { NotificationCenter.default.post(name: .moltOpenSettings, object: section) } }
    switch route {
    case "Focus":
      var list: [(String, () -> Void)] = [("Reset to 25 minutes", { UserDefaults.standard.set(25, forKey: "focusMinutes") })]
      if controller.openFocus != nil { list.append(("Stop this session", { controller.changeFocus("stop") })) }
      return list + [("-", {}), ("Focus settings…", settings("focus"))]
    case "Health":
      return [("Open Activity Monitor", { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) })]
    case "NotchSettings":
      return [
        ("Reset the notch layout", {
          prefs.tabOrder = NotchLayout.tabs
          prefs.hiddenTabs = []
          prefs.priority = LiveKind.allCases
        }), ("-", {}), ("All settings…", settings("notch")),
      ]
    case "AddWidget": return [("Hub settings…", settings("hub"))]
    default: return [("All settings…", settings(nil))]
    }
  }
  private func show() {
    let menu = NSMenu()
    for (title, action) in items {
      if title == "-" { menu.addItem(.separator()); continue }
      menu.addItem(ClosureItem(title, action))
    }
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
  }
}

/// A menu item that runs a closure.
final class ClosureItem: NSMenuItem {
  private let run: () -> Void
  init(_ title: String, _ run: @escaping () -> Void) {
    self.run = run
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }
  required init(coder: NSCoder) { fatalError() }
  @objc private func fire() { run() }
}
