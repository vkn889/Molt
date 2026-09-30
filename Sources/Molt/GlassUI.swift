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
      .fill(Color.white.opacity(0.06))
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

/// The notch menu: every destination plus a few display preferences, styled like a macOS menu.
struct NotchNavigation: View {
  @Binding var selection: String
  @Binding var accent: String
  @Binding var display: Int
  @Binding var hoverToOpen: Bool
  var shortcut: String
  var dismiss: () -> Void
  private let sections: [(String, [(String, String, String)])] = [
    ("Molt", [("Notch", "Home", "house"), ("Hub", "Mac hub", "square.grid.2x2"), ("Ask Molt", "Chat", "bubble.left.and.bubble.right"), ("Molting", "Search & explore", "globe")]),
    ("Daily", [("Today", "Today & focus", "sun.max"), ("Library", "Tasks & notes", "tray.full"), ("Capture", "Quick capture", "plus.circle"), ("Activity", "Activity", "chart.bar")]),
    ("Companion", [("Molt", "Care & training", "heart"), ("Play", "Play together", "gamecontroller"), ("Home", "Home & wardrobe", "sparkles")]),
    ("Settings", [("Settings", "Preferences", "gearshape"), ("AI & tools", "Connect Ollama", "cpu"), ("Agent", "Memory & recent actions", "clock.arrow.circlepath")]),
  ]
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(sections, id: \.0) { section in
          header(section.0)
          ForEach(section.1, id: \.0) { route in
            NotchMenuRow(icon: route.2, title: route.1, selected: selection == route.0) {
              selection = route.0
              dismiss()
            }
          }
        }
        header("Appearance")
        HStack(spacing: 10) {
          ForEach(["blue", "mint", "violet", "amber", "rose"], id: \.self) { value in
            Button { accent = value } label: {
              Circle().fill(MoltTheme.accent(value)).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.white.opacity(accent == value ? 0.9 : 0), lineWidth: 2).padding(-3))
            }.buttonStyle(.plain)
              .accessibilityLabel("\(value) accent").accessibilityAddTraits(accent == value ? .isSelected : [])
          }
        }.padding(.horizontal, 10).padding(.vertical, 6)
        Toggle("Open when hovering the notch", isOn: $hoverToOpen)
          .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
          .padding(.horizontal, 10).padding(.vertical, 4)
        header("Display")
        NotchMenuRow(icon: "display", title: "Automatic", selected: display == -1) { display = -1 }
        NotchMenuRow(icon: "cursorarrow.rays", title: "Active display", selected: display == -2) { display = -2 }
        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
          NotchMenuRow(icon: "rectangle.on.rectangle", title: screen.localizedName, selected: display == index) { display = index }
        }
        Text(shortcut).font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 8)
      }.padding(6)
    }
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.11))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)))
    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
  }
  private func header(_ title: String) -> some View {
    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
  }
}

struct NotchMenuRow: View {
  var icon: String
  var title: String
  var selected: Bool
  var action: () -> Void
  @State private var hovered = false
  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 18)
        Text(title).font(.system(size: 13))
        Spacer(minLength: 8)
        if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
      }
      .foregroundStyle(hovered ? Color.white : Color.white.opacity(0.88))
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovered ? Color.accentColor.opacity(0.85) : .clear))
      .contentShape(Rectangle())
    }.buttonStyle(.plain).onHover { hovered = $0 }
      .accessibilityAddTraits(selected ? .isSelected : [])
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
