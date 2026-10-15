import MoltCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Notch: which tabs show and in what order, what the closed notch shows first, and
/// how it feels to open.
struct NotchSettingsView: View {
  @ObservedObject var prefs: NotchPrefs
  @ObservedObject var coordinator: IslandCoordinator
  @State private var dragging: String?
  @State private var target: String?
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      card("Tabs") {
        ForEach(NotchLayout.allTabs(order: prefs.tabOrder), id: \.self) { route in
          let tab = IslandView.tabs.first { $0.route == route }
          let shown = route == "Notch" || !prefs.hiddenTabs.contains(route)
          reorderable("tab:\(route)") {
            Image(systemName: tab?.icon ?? "circle").font(.system(size: 11)).frame(width: 16)
              .foregroundStyle(shown ? Color.white : Color.white.opacity(0.35))
            Text(tab?.title ?? route).font(.system(size: 12)).foregroundStyle(shown ? Color.white : Color.white.opacity(0.35))
            Spacer(minLength: 4)
            Toggle(tab?.title ?? route, isOn: Binding(get: { shown }, set: { prefs.setTab(route, shown: $0) }))
              .labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(route == "Notch")
              .help(route == "Notch" ? "Home always shows" : "Show \(tab?.title ?? route)")
          } move: { before in prefs.moveTab(route, before: before.flatMap { $0.hasPrefix("tab:") ? String($0.dropFirst(4)) : nil }) }
        }
      }
      card("When it's closed, show first") {
        ForEach(Array(prefs.priority.enumerated()), id: \.element) { index, kind in
          reorderable("live:\(kind.rawValue)") {
            Text("\(index + 1)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.35)).frame(width: 12)
            Circle().fill(Self.tint(kind)).frame(width: 7, height: 7)
            Text(kind.title).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
          } move: { before in
            prefs.movePriority(kind, before: before.flatMap { $0.hasPrefix("live:") ? LiveKind(rawValue: String($0.dropFirst(5))) : nil })
          }
        }
      }
      card("Feel") {
        Text(coordinator.hoverToOpen ? "Open on hover after" : "Opening on hover is off").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.85))
        Slider(value: $prefs.hoverDelay, in: 0...1, step: 0.05).controlSize(.mini).disabled(!coordinator.hoverToOpen)
          .help(prefs.hoverDelay < 0.05 ? "Instantly" : String(format: "%.2g seconds", prefs.hoverDelay))
        HStack {
          Text("Instantly"); Spacer(); Text(String(format: "%.2g s", max(0.05, prefs.hoverDelay))).foregroundStyle(Color.white.opacity(0.6)); Spacer(); Text("1 s")
        }
        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.white.opacity(0.35)).padding(.bottom, 6)
        toggle("Fit to content", $prefs.fitContent, help: "Each page sizes the notch to what's on it")
        toggle("Molt reacts to the Mac", $prefs.petReacts, help: "Sleepy on low battery")
        toggle("Type to jump", $prefs.typeToJump, help: "Start typing with the notch open to search everything")
      }
      .frame(width: 210)
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
  }

  /// A row you can drag above another to reorder.
  private func reorderable<Content: View>(_ id: String, @ViewBuilder content: () -> Content, move: @escaping (String?) -> Void) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.white.opacity(0.3))
      content()
    }
    .padding(.horizontal, 8).frame(height: 28)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(target == id ? 0.12 : dragging == id ? 0.08 : 0)))
    .overlay(alignment: .top) {
      if target == id && dragging != id { Capsule().fill(Color.accentColor).frame(height: 2).offset(y: -1) }
    }
    .contentShape(Rectangle())
    .onDrag {
      dragging = id
      return NSItemProvider(object: id as NSString)
    }
    .onDrop(of: [UTType.plainText], delegate: RowDrop(id: id, target: $target) { dragged in
      // Tabs reorder among tabs, and the closed-notch order among itself.
      guard Self.group(dragged) == Self.group(id) else { return }
      dragging = nil
      withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
        // Dropping on a row puts the dragged one in front of it.
        if dragged.hasPrefix("tab:") { prefs.moveTab(String(dragged.dropFirst(4)), before: String(id.dropFirst(4))) }
        else if let kind = LiveKind(rawValue: String(dragged.dropFirst(5))) { prefs.movePriority(kind, before: LiveKind(rawValue: String(id.dropFirst(5)))) }
      }
    })
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Move up") { move(previous(id)) }
  }
  static func group(_ id: String) -> Substring { id.split(separator: ":").first ?? "" }
  /// For VoiceOver's Move up: the row above, so this one goes in front of it.
  private func previous(_ id: String) -> String? {
    if id.hasPrefix("tab:") {
      let all = NotchLayout.allTabs(order: prefs.tabOrder)
      guard let index = all.firstIndex(of: String(id.dropFirst(4))), index > 0 else { return id }
      return "tab:" + all[index - 1]
    }
    let all = prefs.priority.map(\.rawValue)
    guard let index = all.firstIndex(of: String(id.dropFirst(5))), index > 0 else { return id }
    return "live:" + all[index - 1]
  }
  private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
      content()
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 16))
  }
  private func toggle(_ title: String, _ value: Binding<Bool>, help: String) -> some View {
    HStack {
      Text(title).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
      Spacer(minLength: 4)
      Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }
    .frame(height: 22).help(help)
  }
  static func tint(_ kind: LiveKind) -> Color {
    switch kind {
    case .agents: return .orange
    case .recording: return .red
    case .focus: return .green
    case .music: return .pink
    case .battery: return .yellow
    }
  }
}

private struct RowDrop: DropDelegate {
  var id: String
  @Binding var target: String?
  var drop: (String) -> Void
  func dropEntered(info: DropInfo) { target = id }
  func dropExited(info: DropInfo) { if target == id { target = nil } }
  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
  func performDrop(info: DropInfo) -> Bool {
    target = nil
    guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
      guard let text = value as? String else { return }
      Task { @MainActor in drop(text) }
    }
    return true
  }
}
