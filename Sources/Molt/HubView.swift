import AppKit
import MoltCore
import SwiftUI
import UniformTypeIdentifiers

/// The Hub: up to two rows of four slots of widgets you choose, like a Home Screen. Edit with
/// the pencil in the header or by holding a widget; drag to reorder, and use the badges to
/// remove or resize. The notch grows a row when the second one is in use.
struct HubView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  @State private var configuring: UUID?
  @State private var dropTarget: UUID?
  static let gap: CGFloat = 10
  var body: some View {
    GeometryReader { proxy in
      let unit = (proxy.size.width - Self.gap * CGFloat(HubLayout.capacity - 1)) / CGFloat(HubLayout.capacity)
      let layout = hub.layout
      let rows = Self.rows(layout, editing: hub.editing, limit: hub.rows)
      VStack(spacing: IslandCoordinator.hubGap) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          HStack(spacing: Self.gap) {
            ForEach(row.widgets) { widget in
              tile(widget)
                .frame(width: unit * CGFloat(widget.span) + Self.gap * CGFloat(widget.span - 1))
            }
            ForEach(0..<row.empty, id: \.self) { index in
              emptySlot(at: row.end).frame(width: unit)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: IslandCoordinator.hubRow)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
      .animation(.spring(response: 0.32, dampingFraction: 0.82), value: layout)
      .animation(.spring(response: 0.32, dampingFraction: 0.82), value: rows.count)
    }
    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    .overlay {
      if let id = configuring, let widget = hub.layout.first(where: { $0.id == id }) {
        ShortcutsEditor(widget: widget, hub: hub, actions: hub.actions) { configuring = nil }
      }
    }
    .onChange(of: hub.editing) { editing in if !editing { configuring = nil } }
  }

  struct Row { var widgets: [HubWidget]; var empty: Int; var end: Int }
  /// The rows to draw: the layout's rows with their empty slots, and while editing, an empty row
  /// where another widget could go. A row that has a later row after it shows no empty slots.
  static func rows(_ layout: [HubWidget], editing: Bool, limit: Int) -> [Row] {
    var result: [Row] = []
    var index = 0
    let rows = HubLayout.rows(layout)
    for (number, row) in rows.enumerated() {
      index += row.count
      let last = number == rows.count - 1
      result.append(Row(widgets: row, empty: last ? HubLayout.capacity - HubLayout.used(row) : 0, end: index))
    }
    if result.isEmpty { result.append(Row(widgets: [], empty: HubLayout.capacity, end: 0)) }
    if editing && rows.count < limit && result.last?.empty == 0 {
      result.append(Row(widgets: [], empty: HubLayout.capacity, end: layout.count))
    }
    return result
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
    Button {
      hub.pickerSlot = index
      hub.pickerQuery = ""
      controller.tab = "AddWidget"
    } label: {
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

/// Adding a widget, as in the mockup: browse by kind or search (in the header), what's new is
/// marked, and a click adds it where you chose.
struct WidgetGallery: View {
  @ObservedObject var controller: PetController
  @ObservedObject var hub: HubController
  @ObservedObject var prefs: NotchPrefs
  var body: some View {
    let room = HubLayout.room(hub.layout, rows: hub.rows)
    let placed = Set(hub.layout.map(\.kind))
    let available = WidgetKind.catalog.filter { kind in
      prefs.shows(kind.id) && (kind.id == "shortcuts" || !placed.contains(kind.id))
    }
    let query = hub.pickerQuery
    let kinds = available.filter { kind in
      (hub.pickerCategory == "All" || (hub.pickerCategory == "New" ? kind.badge != nil : kind.category == hub.pickerCategory))
        && (query.isEmpty || kind.title.localizedCaseInsensitiveContains(query) || kind.blurb.localizedCaseInsensitiveContains(query))
    }
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        if room == 0 {
          Label("Your Hub is full. Remove a widget, or allow more rows in Hub settings.", systemImage: "info.circle")
            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.orange).lineLimit(1)
          Spacer()
        }
        ForEach(room == 0 ? [] : WidgetKind.categories, id: \.self) { name in
          let count = name == "All" ? available.count : available.filter { name == "New" ? $0.badge != nil : $0.category == name }.count
          if count > 0 { chip(name) }
        }
      }
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
          ForEach(kinds) { kind in
            let fits = kind.spans.contains { $0 <= room }
            Button { add(kind) } label: { tile(kind, fits: fits) }
              .buttonStyle(.plain).disabled(!fits)
              .help(fits ? kind.blurb : "No room. Remove a widget, or allow more rows in Settings.")
          }
        }
        if kinds.isEmpty {
          Text(query.isEmpty ? "Everything here is already on your Hub." : "No widgets match \u{201C}\(query)\u{201D}.")
            .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
        }
      }
    }
    .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
  }
  private func chip(_ name: String) -> some View {
    let selected = hub.pickerCategory == name
    let green = Color(red: 0.36, green: 0.8, blue: 0.55)
    return Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { hub.pickerCategory = name } } label: {
      Text(name == "New" ? "New in 0.9.2" : name).font(.system(size: 12, weight: .semibold)).fixedSize()
        .foregroundStyle(selected ? (name == "New" ? green : .white) : Color.white.opacity(0.55))
        .padding(.horizontal, 11).frame(height: 26)
        .background(Capsule().fill(selected ? (name == "New" ? green.opacity(0.2) : Color.white.opacity(0.14)) : Color.white.opacity(0.06)))
    }.buttonStyle(.plain)
  }
  private func tile(_ kind: WidgetKind, fits: Bool) -> some View {
    VStack(spacing: 8) {
      Image(systemName: kind.symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(kind.tint)
        .frame(width: 40, height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
      Text(kind.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity).frame(height: 104)
    .background(NotchSurface(radius: 16))
    .overlay(alignment: .topTrailing) {
      if kind.badge != nil {
        Text("NEW").font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(Color(red: 0.36, green: 0.8, blue: 0.55))
          .padding(.top, 7).padding(.trailing, 8)
      }
    }
    .overlay(alignment: .topLeading) {
      Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor)).padding(6)
    }
    .opacity(fits ? 1 : 0.4)
    .contentShape(Rectangle())
  }
  private func add(_ kind: WidgetKind) {
    hub.add(kind, at: hub.pickerSlot)
    hub.pickerSlot = nil
    hub.pickerQuery = ""
    hub.editing = true
    controller.tab = "Hub"
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
