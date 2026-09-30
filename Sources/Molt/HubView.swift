import AppKit
import MoltCore
import SwiftUI
import UniformTypeIdentifiers

/// The Hub: four slots of widgets you choose, like a Home Screen. Edit with the pencil in the
/// header or by holding a widget; drag to reorder, and use the badges to remove or resize.
struct HubView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  @State private var picking: Int?
  @State private var configuring: UUID?
  @State private var dropTarget: UUID?
  static let gap: CGFloat = 12
  var body: some View {
    GeometryReader { proxy in
      let unit = (proxy.size.width - Self.gap * CGFloat(HubLayout.capacity - 1)) / CGFloat(HubLayout.capacity)
      let layout = hub.layout
      HStack(spacing: Self.gap) {
        ForEach(layout) { widget in
          tile(widget)
            .frame(width: unit * CGFloat(widget.span) + Self.gap * CGFloat(widget.span - 1))
        }
        ForEach(0..<max(0, HubLayout.capacity - HubLayout.used(layout)), id: \.self) { index in
          emptySlot(at: layout.count + index).frame(width: unit)
        }
      }
      .frame(maxHeight: .infinity)
      .animation(.spring(response: 0.32, dampingFraction: 0.82), value: layout)
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
    .overlay {
      if let slot = picking {
        WidgetPicker(hub: hub, room: HubLayout.capacity - HubLayout.used(hub.layout)) { kind in
          hub.add(kind, at: slot)
          picking = nil
        } close: { picking = nil }
      } else if let id = configuring, let widget = hub.layout.first(where: { $0.id == id }) {
        ShortcutsEditor(widget: widget, hub: hub, actions: hub.actions) { configuring = nil }
      }
    }
    .onChange(of: hub.editing) { editing in if !editing { picking = nil; configuring = nil } }
  }

  @ViewBuilder private func tile(_ widget: HubWidget) -> some View {
    let editing = hub.editing
    WidgetView(widget: widget, controller: controller, hub: hub)
      .allowsHitTesting(!editing)
      .overlay {
        if editing {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(dropTarget == widget.id ? Color.accentColor : Color.white.opacity(0.18), lineWidth: dropTarget == widget.id ? 2 : 1)
        }
      }
      .overlay(alignment: .topLeading) {
        if editing {
          badge("minus", tint: Color(white: 0.3), label: "Remove \(WidgetKind.find(widget.kind)?.title ?? "widget")") { hub.remove(widget.id) }
            .offset(x: -6, y: -6)
        }
      }
      .overlay(alignment: .topTrailing) {
        if editing {
          HStack(spacing: 4) {
            if widget.kind == "shortcuts" {
              badge("slider.horizontal.3", tint: .accentColor, label: "Choose shortcuts") { configuring = widget.id }
            }
            if hub.canResize(widget) {
              badge(widget.span == 1 ? "arrow.left.and.right" : "arrow.right.and.line.vertical.and.arrow.left", tint: .accentColor,
                label: widget.span == 1 ? "Make wider" : "Make smaller") { hub.resize(widget) }
            }
          }.offset(x: 6, y: -6)
        }
      }
      .modifier(Jiggle(active: editing, seed: widget.id.hashValue))
      .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in if !editing { hub.editing = true } })
      .modifier(Reorder(active: editing, id: widget.id))
      .onDrop(of: [UTType.plainText], delegate: WidgetDrop(target: widget.id, hub: hub, hovering: $dropTarget))
  }

  private func emptySlot(at index: Int) -> some View {
    Button { picking = index } label: {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Color.white.opacity(hub.editing ? 0.25 : 0.1), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain).help("Add a widget").accessibilityLabel("Add a widget")
    .onDrop(of: [UTType.plainText], delegate: WidgetDrop(target: nil, hub: hub, hovering: $dropTarget))
  }
  private func badge(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
        .frame(width: 20, height: 20).background(Circle().fill(tint)).overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
    }.buttonStyle(.plain).help(label).accessibilityLabel(label)
  }
}

/// Widgets can be dragged only while editing, so text and controls inside them work normally.
private struct Reorder: ViewModifier {
  var active: Bool
  var id: UUID
  func body(content: Content) -> some View {
    if active {
      content.onDrag { NSItemProvider(object: "widget:\(id.uuidString)" as NSString) }
    } else {
      content
    }
  }
}

/// The Home Screen wiggle while editing.
private struct Jiggle: ViewModifier {
  var active: Bool
  var seed: Int
  @Environment(\.moltReducedMotion) private var reduced
  @Environment(\.accessibilityReduceMotion) private var systemReduced
  func body(content: Content) -> some View {
    if active && !reduced && !systemReduced {
      TimelineView(.animation(minimumInterval: 1 / 30)) { context in
        let t = context.date.timeIntervalSinceReferenceDate * 11 + Double(seed % 7)
        content.rotationEffect(.degrees(sin(t) * 0.9))
      }
    } else {
      content
    }
  }
}

private struct WidgetDrop: DropDelegate {
  var target: UUID?
  var hub: HubController
  @Binding var hovering: UUID?
  func dropEntered(info: DropInfo) { hovering = target }
  func dropExited(info: DropInfo) { if hovering == target { hovering = nil } }
  func performDrop(info: DropInfo) -> Bool {
    hovering = nil
    guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
    let target = target
    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
      guard let text = value as? String, text.hasPrefix("widget:"), let id = UUID(uuidString: String(text.dropFirst(7))) else { return }
      Task { @MainActor in hub.move(id, before: target) }
    }
    return true
  }
}

/// Choose a widget to add. Sizes that don't fit in the remaining space are hidden.
struct WidgetPicker: View {
  @ObservedObject var hub: HubController
  var room: Int
  var choose: (WidgetKind) -> Void
  var close: () -> Void
  var body: some View {
    let placed = Set(hub.layout.map(\.kind))
    let kinds = WidgetKind.catalog.filter { kind in
      (kind.id == "shortcuts" || !placed.contains(kind.id)) && kind.spans.contains { $0 <= room }
    }
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Add a widget").font(.system(size: 13, weight: .semibold))
        Text("\(room) \(room == 1 ? "slot" : "slots") free").font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer()
        Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 24)).accessibilityLabel("Close")
      }
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
          ForEach(kinds) { kind in
            Button { choose(kind) } label: {
              HStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 15)).foregroundStyle(Color.accentColor).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                  Text(kind.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                  Text(kind.spans == [2] ? "Wide" : kind.spans.count > 1 ? "Small or wide" : "Small")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 8).frame(height: 40)
              .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
              .contentShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help(kind.blurb)
          }
        }
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.09)))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
  }
}

/// Pick what a Shortcuts widget shows: built-in actions, your Apple Shortcuts, apps and links.
struct ShortcutsEditor: View {
  var widget: HubWidget
  @ObservedObject var hub: HubController
  @ObservedObject var actions: QuickActions
  var close: () -> Void
  @State private var link = ""
  private var limit: Int { widget.span == 2 ? 8 : 4 }
  var body: some View {
    let items = hub.layout.first { $0.id == widget.id }?.items ?? widget.items
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Choose shortcuts").font(.system(size: 13, weight: .semibold))
        Text("\(items.count) of \(limit)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
        Spacer()
        Button("Add app…") { addApp(items) }.disabled(items.count >= limit)
        Button("Done", action: close)
      }
      HStack(alignment: .top, spacing: 10) {
        ScrollView {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(QuickActions.catalog) { action in
              toggle("action:\(action.id)", title: action.title, symbol: action.symbol, tint: action.tint, items: items)
            }
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Apple Shortcuts").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
              if actions.shortcuts.isEmpty {
                Text("Shortcuts you make in the Shortcuts app appear here.").font(.system(size: 10)).foregroundStyle(.secondary)
              }
              ForEach(actions.shortcuts, id: \.self) { name in
                toggle("shortcut:\(name)", title: name, symbol: "square.stack.3d.up.fill", tint: .pink, items: items)
              }
            }
          }
          HStack(spacing: 4) {
            TextField("https:// link", text: $link).textFieldStyle(.plain).font(.system(size: 10))
              .padding(.horizontal, 7).frame(height: 22).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
              .onSubmit { addLink(items) }
            Button { addLink(items) } label: { Image(systemName: "plus").font(.system(size: 10, weight: .bold)) }
              .buttonStyle(NotchIconButtonStyle(size: 22)).disabled(items.count >= limit).accessibilityLabel("Add link")
          }
        }.frame(width: 190)
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.09)))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
    .onAppear(perform: actions.loadShortcuts)
  }
  private func toggle(_ item: String, title: String, symbol: String, tint: Color, items: [String]) -> some View {
    let on = items.contains(item)
    return Button {
      hub.setItems(widget.id, on ? items.filter { $0 != item } : items + [item])
    } label: {
      HStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint).frame(width: 16)
        Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 11)).foregroundStyle(on ? Color.accentColor : .secondary)
      }
      .padding(.horizontal, 7).frame(height: 26)
      .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(on ? 0.12 : 0.05)))
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain).disabled(!on && items.count >= limit)
  }
  private func addApp(_ items: [String]) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    let added = panel.urls.map { "app:" + $0.path }.filter { !items.contains($0) }
    hub.setItems(widget.id, Array((items + added).prefix(limit)))
  }
  private func addLink(_ items: [String]) {
    let value = link.trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: value), url.scheme == "https", url.host != nil, items.count < limit else { return }
    hub.setItems(widget.id, items + ["url:" + value])
    link = ""
  }
}
