import AppKit
import SwiftUI

private struct MoltReducedMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
  var moltReducedMotion: Bool {
    get { self[MoltReducedMotionKey.self] }
    set { self[MoltReducedMotionKey.self] = newValue }
  }
}
struct GlassSurface: View {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceTransparency) private var solid
  var radius: CGFloat = 16
  var body: some View {
    RoundedRectangle(cornerRadius: radius)
      .fill(.regularMaterial)
      .overlay(RoundedRectangle(cornerRadius: radius).fill(
        scheme == .dark ? Color.black.opacity(solid ? 1 : 0.30) : Color.white.opacity(solid ? 1 : 0.58)))
      .overlay(RoundedRectangle(cornerRadius: radius).fill(LinearGradient(
        colors: [.white.opacity(scheme == .dark ? 0.12 : 0.45), .clear, Color.accentColor.opacity(0.06)],
        startPoint: .topLeading, endPoint: .bottomTrailing)))
      .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(
        LinearGradient(colors: [.white.opacity(0.30), Color.primary.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
  }
}
struct GlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { GlassButton(configuration: configuration) }
  private struct GlassButton: View {
    let configuration: Configuration
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.moltReducedMotion) private var reduced
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    var body: some View {
      configuration.label.font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .background(GlassSurface(radius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).fill(Color.accentColor.opacity(hovered && enabled ? 0.14 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.accentColor.opacity(hovered && enabled ? 0.5 : 0), lineWidth: 1))
        .opacity(enabled ? 1 : 0.42)
        .scaleEffect(configuration.isPressed && !reduced && !systemReduced ? 0.96 : 1)
        .animation(reduced || systemReduced ? nil : .easeOut(duration: 0.18), value: hovered)
        .animation(reduced || systemReduced ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
        .onHover { hovered = $0 }
    }
  }
}
struct GlassNavigation: View {
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
    case "Daily": return [("Notch", "Quick controls", "square.grid.2x2"), ("Today", "Today & focus", "sun.max"), ("Library", "Tasks & notes", "tray.full"), ("Capture", "Quick capture", "plus.circle"), ("AI & tools", "Projects & tools", "folder")]
    case "Companion": return [("Molt", "Care & training", "heart"), ("Play", "Play together", "gamecontroller"), ("Home", "Home & wardrobe", "house"), ("Activity", "Computer health", "waveform.path.ecg")]
    case "Settings": return [("Settings", "Preferences", "slider.horizontal.3"), ("AI & tools", "Local AI setup", "cpu")]
    default: return [("Ask Molt", "Chat with Molt", "bubble.left.and.bubble.right"), ("Molting", "Search & research", "globe"), ("Agent", "Tasks, memory & history", "sparkles")]
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
    }.padding(12).background(GlassSurface(radius: 18))
      .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
      .buttonStyle(GlassButtonStyle())
      .animation(reduced || systemReduced ? nil : .easeInOut(duration: 0.2), value: category)
  }
}

struct GlassPageMotion: ViewModifier {
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
