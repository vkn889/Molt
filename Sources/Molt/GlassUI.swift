import AppKit
import SwiftUI

private struct MoltReducedMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
  var moltReducedMotion: Bool {
    get { self[MoltReducedMotionKey.self] }
    set { self[MoltReducedMotionKey.self] = newValue }
  }
}
struct RetroSurface: View {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceTransparency) private var solid
  var radius: CGFloat = 16
  var body: some View {
    PixelPanel()
      .fill(scheme == .dark ? Color(red: 0.16, green: 0.13, blue: 0.25) : Color(red: 1, green: 0.96, blue: 0.86))
      .overlay(PixelPanel().stroke(Color.primary.opacity(0.35), lineWidth: 2))
      .overlay(PixelPanel().inset(by: 3).stroke(Color.white.opacity(0.15), lineWidth: 1))

  }
}
struct RetroButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { GlassButton(configuration: configuration) }
  private struct GlassButton: View {
    let configuration: Configuration
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.moltReducedMotion) private var reduced
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    var body: some View {
      configuration.label.font(MoltTheme.display(13))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(PixelPanel())
        .background(RetroSurface(radius: 11))
        .overlay(PixelPanel().fill(Color.accentColor.opacity(hovered && enabled ? 0.14 : 0)))
        .overlay(PixelPanel().strokeBorder(Color.accentColor.opacity(hovered && enabled ? 0.5 : 0), lineWidth: 1))
        .opacity(enabled ? 1 : 0.42)
        .scaleEffect(configuration.isPressed && !reduced && !systemReduced ? 0.96 : 1)
        .animation(reduced || systemReduced ? nil : .easeOut(duration: 0.18), value: hovered)
        .animation(reduced || systemReduced ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
        .onHover { hovered = $0 }
    }
  }
}
struct RetroNavigation: View {
  @Binding var selection: String
  @Binding var theme: String
  @Binding var accent: String
  @Binding var display: Int
  var shortcut: String
  var dismiss: () -> Void
  @State private var category = "For you"
  @Environment(\.moltReducedMotion) private var reduced
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  private var routes: [(String, String, String)] {
    switch category {
    case "Daily": return [("Notch", "My Mac hub", "square.grid.2x2"), ("Today", "Today & focus", "sun.max"), ("Library", "Tasks & notes", "tray.full"), ("Capture", "Quick capture", "plus.circle")]
    case "Companion": return [("Molt", "Care & training", "heart"), ("Play", "Play together", "gamecontroller"), ("Home", "Home & wardrobe", "house")]
    case "Settings": return [("Settings", "Preferences", "slider.horizontal.3"), ("AI & tools", "Connect Ollama", "cpu"), ("Agent", "Memory & recent actions", "clock")]
    default: return [("Notch", "My companion hub", "house"), ("Ask Molt", "Chat with Molt", "bubble.left.and.bubble.right"), ("Molting", "Search & explore", "globe")]
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        ForEach(["For you", "Daily", "Companion", "Settings"], id: \.self) { title in
          Button { category = title } label: {
            Text(title).foregroundStyle(category == title ? Color.accentColor : .primary)
          }.accessibilityAddTraits(category == title ? .isSelected : [])
        }
        Spacer(minLength: 0)
        Button(action: dismiss) { Image(systemName: "xmark") }.accessibilityLabel("Close navigation")
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 7) {
          ForEach(routes, id: \.0) { route in
            Button { selection = route.0; dismiss() } label: {
              HStack(spacing: 10) {
                Image(systemName: route.2).frame(width: 20).foregroundStyle(Color.accentColor)
                Text(route.1)
                Spacer()
                Image(systemName: selection == route.0 ? "checkmark.circle.fill" : "arrow.up.right").foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityAddTraits(selection == route.0 ? .isSelected : [])
          }
          if category == "Settings" {
            Text("APPEARANCE").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
            HStack {
              ForEach(["dark", "light", "system"], id: \.self) { value in
                Button { theme = value } label: { Label(value.capitalized, systemImage: theme == value ? "checkmark.circle.fill" : "circle") }
              }
            }
            HStack {
              ForEach(["mint", "blue", "violet", "amber", "rose"], id: \.self) { value in
                Button { accent = value } label: {
                  Circle().fill(MoltTheme.accent(value)).frame(width: 14, height: 14)
                    .overlay { if accent == value { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.black) } }
                }.accessibilityLabel("\(value) accent").accessibilityAddTraits(accent == value ? .isSelected : [])
              }
            }
            Text("DISPLAY").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
            Button(display == -1 ? "✓ Automatic" : "Automatic") { display = -1 }
            Button(display == -2 ? "✓ Active display" : "Active display") { display = -2 }
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
              Button((display == index ? "✓ " : "") + screen.localizedName) { display = index }
            }
            Text(shortcut).font(.caption2).foregroundStyle(.secondary)
          }
        }.padding(2)
      }
    }.padding(12).background(RetroSurface(radius: 18))
      .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
      .buttonStyle(RetroButtonStyle())
      .animation(reduced || systemReduced ? nil : .easeInOut(duration: 0.2), value: category)
  }
}

struct RetroPageMotion: ViewModifier {
  var route: String
  @State private var visible = true
  @Environment(\.moltReducedMotion) private var reduced
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  func body(content: Content) -> some View {
    content.opacity(visible || reduced || systemReduced ? 1 : 0)
      .offset(y: visible || reduced || systemReduced ? 0 : 6)
      .task(id: route) {
        if CommandLine.arguments.contains("--render-preview") { visible = true; return }
        guard !reduced, !systemReduced else { visible = true; return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { visible = false }
        do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
        withAnimation(.easeOut(duration: 0.24)) { visible = true }
      }
  }
}

struct PixelPanel: InsettableShape {
  var insetAmount: CGFloat = 0
  func inset(by amount: CGFloat) -> PixelPanel { var shape = self; shape.insetAmount += amount; return shape }
  func path(in original: CGRect) -> Path {
    let r = original.insetBy(dx: insetAmount, dy: insetAmount)
    let c: CGFloat = min(5, min(r.width, r.height) / 3)
    return Path { p in
      p.move(to: CGPoint(x: r.minX + c, y: r.minY))
      let points = [CGPoint(x: r.maxX - c, y: r.minY), CGPoint(x: r.maxX - c, y: r.minY + c), CGPoint(x: r.maxX, y: r.minY + c), CGPoint(x: r.maxX, y: r.maxY - c), CGPoint(x: r.maxX - c, y: r.maxY - c), CGPoint(x: r.maxX - c, y: r.maxY), CGPoint(x: r.minX + c, y: r.maxY), CGPoint(x: r.minX + c, y: r.maxY - c), CGPoint(x: r.minX, y: r.maxY - c), CGPoint(x: r.minX, y: r.minY + c), CGPoint(x: r.minX + c, y: r.minY + c)]
      for point in points { p.addLine(to: point) }
      p.closeSubpath()
    }
  }
}
