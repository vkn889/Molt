import AppKit
import MoltCore
import SwiftUI
import UniformTypeIdentifiers

/// Drag files or links up to the notch and drop them on Molt: ask about them, keep them in the
/// tray for later, or share them.
struct DropPage: View {
  @ObservedObject var controller: PetController
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var hub: HubController
  @State private var hovering: String?
  @State private var kept = false
  var body: some View {
    let dragged = Self.dragged()
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        CreatureView(appearance: controller.companion.appearance, mood: kept ? "celebrating" : hovering == nil ? "happy" : "love", followsPointer: false)
          .frame(width: 34, height: 32)
        VStack(alignment: .leading, spacing: 1) {
          Text(kept ? "Kept it!" : "Drop it on \(controller.petName)").font(.system(size: 15, weight: .semibold))
          Text(kept ? "It's in your Tray" : Self.describe(dragged)).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55))
            .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: 170, alignment: .leading)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 22).padding(.top, 14)
      HStack(spacing: 10) {
        target("ask", "Ask", "bubble.left.fill", "Chat about it", .accentColor)
        target("keep", "Keep", "tray.and.arrow.down.fill", "\(controller.petName) holds it for later", MoltTheme.body(controller.companion.appearance.palette))
        target("share", "Share", "square.and.arrow.up", "AirDrop, Mail, Messages", Color(red: 0.39, green: 0.82, blue: 1))
      }
      .frame(height: 112)
      .padding(.horizontal, 18).padding(.top, 14)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: kept)
  }
  private func target(_ id: String, _ title: String, _ symbol: String, _ detail: String, _ tint: Color) -> some View {
    let on = hovering == id
    return VStack(spacing: 0) {
      Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
        .scaleEffect(on ? 1.15 : 1)
      Text(title).font(.system(size: 14, weight: .semibold)).padding(.top, 8)
      Text(detail).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1).padding(.top, 2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? tint.opacity(0.18) : Color.white.opacity(0.05)))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(on ? tint : Color.white.opacity(0.14), style: StrokeStyle(lineWidth: on ? 1.5 : 1, dash: on ? [] : [5, 4])))
    .scaleEffect(on ? 1.02 : 1)
    .onDrop(of: [.fileURL, .url], isTargeted: Binding(get: { hovering == id }, set: { hovering = $0 ? id : (hovering == id ? nil : hovering) })) { providers in
      coordinator.claimDrop()
      Self.load(providers) { urls in handle(id, urls) }
      return true
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(detail)")
  }
  private func handle(_ id: String, _ urls: [URL]) {
    guard !urls.isEmpty else { coordinator.endDrop(); return }
    switch id {
    case "ask":
      coordinator.endDrop(keepOpen: true)
      for url in urls {
        if url.isFileURL { controller.assistant.attach(url) } else { controller.assistant.draft += (controller.assistant.draft.isEmpty ? "" : " ") + url.absoluteString }
      }
      controller.tab = "Ask Molt"
      coordinator.open()
    case "keep":
      hub.keep(urls)
      kept = true
      controller.poked = Date()
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 900_000_000)
        coordinator.endDrop()
      }
    default:
      coordinator.share(urls)
      coordinator.endDrop(keepOpen: true)
    }
  }
  /// What's being dragged, read from the drag itself.
  static func dragged() -> [URL] {
    NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
  }
  /// "Pitch Deck.pdf · 4.2 MB", or how many things are coming.
  static func describe(_ urls: [URL]) -> String {
    guard let first = urls.first else { return "Drop on what you'd like" }
    let name = first.isFileURL ? first.lastPathComponent : (first.host ?? first.absoluteString)
    if urls.count > 1 { return "\(name) and \(urls.count - 1) more" }
    guard first.isFileURL, let bytes = (try? first.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return name }
    return "\(name) · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
  /// Reads the dropped files and links, then calls back on the main actor.
  static func load(_ providers: [NSItemProvider], done: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { lock.lock(); urls.append(url); lock.unlock() }
        group.leave()
      }
    }
    group.notify(queue: .main) { Task { @MainActor in done(urls) } }
  }
}

/// What you've dropped on Molt to keep: click to open, drag it out to use it.
struct TrayTile: View {
  @ObservedObject var hub: HubController
  var span: Int
  @State private var hovered: UUID?
  var body: some View {
    let items = Array(hub.tray.prefix(span == 2 ? 6 : 3))
    Tile(title: "Tray", icon: "tray.fill") {
      if items.isEmpty {
        Text("Drag files or links up to the notch and drop them on Keep.").font(.system(size: 11)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: span), alignment: .leading, spacing: 6) {
          ForEach(items) { item in row(item) }
        }
      }
      Spacer(minLength: 0)
      if hub.tray.count > items.count {
        Text("+\(hub.tray.count - items.count) more").font(.system(size: 9)).foregroundStyle(.secondary)
      }
    }
    .onAppear(perform: hub.pruneTray)
    .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
      DropPage.load(providers) { hub.keep($0) }
      return true
    }
  }
  /// A tinted symbol for each kind of thing, as in the mockup.
  static func symbol(_ item: TrayItem) -> (String, Color) {
    guard item.kind == .file else { return ("link", .blue) }
    let type = UTType(filenameExtension: URL(fileURLWithPath: item.value).pathExtension)
    if type?.conforms(to: .pdf) == true { return ("doc.fill", .red) }
    if type?.conforms(to: .image) == true { return ("photo", .orange) }
    if type?.conforms(to: .movie) == true { return ("film", .purple) }
    if type?.conforms(to: .folder) == true || type == nil && URL(fileURLWithPath: item.value).hasDirectoryPath { return ("folder.fill", .blue) }
    return ("doc.fill", Color.white.opacity(0.7))
  }
  private func row(_ item: TrayItem) -> some View {
    let url = item.kind == .file ? URL(fileURLWithPath: item.value) : URL(string: item.value)
    let symbol = Self.symbol(item)
    return HStack(spacing: 8) {
      Image(systemName: symbol.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(symbol.1).frame(width: 16)
      Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
      Spacer(minLength: 0)
      if hovered == item.id {
        Button { hub.removeFromTray(item.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
          .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from the tray").accessibilityLabel("Remove \(item.name)")
      }
    }
    .padding(.horizontal, 8).frame(height: 28)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovered == item.id ? 0.1 : 0.05)))
    .contentShape(Rectangle())
    .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
    .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
    .onDrag { url.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider() }
    .help("Open, or drag it where you need it")
  }
}
