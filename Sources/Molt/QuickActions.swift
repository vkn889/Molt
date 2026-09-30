import AppKit
import SwiftUI

/// One-click actions for Shortcuts widgets. Items are stored as "action:<id>", "app:<path>",
/// "shortcut:<name>" (an Apple Shortcut) or "url:<https address>".
@MainActor final class QuickActions: ObservableObject {
  struct Action: Identifiable { var id: String; var title: String; var symbol: String; var tint: Color }
  static let catalog: [Action] = [
    Action(id: "record", title: "Record screen", symbol: "record.circle", tint: .red),
    Action(id: "screenshot", title: "Screenshot", symbol: "camera.viewfinder", tint: .white),
    Action(id: "lens", title: "Ask about screen", symbol: "text.viewfinder", tint: .accentColor),
    Action(id: "color", title: "Pick color", symbol: "eyedropper", tint: .cyan),
    Action(id: "awake", title: "Keep awake", symbol: "cup.and.saucer.fill", tint: .orange),
    Action(id: "dark", title: "Dark mode", symbol: "circle.lefthalf.filled", tint: .white),
    Action(id: "mute", title: "Mute", symbol: "speaker.slash.fill", tint: .white),
    Action(id: "sleep", title: "Sleep screen", symbol: "moon.zzz.fill", tint: .indigo),
    Action(id: "downloads", title: "Downloads", symbol: "arrow.down.circle.fill", tint: .blue),
    Action(id: "trash", title: "Empty Trash", symbol: "trash.fill", tint: .gray),
    Action(id: "focus", title: "Focus 25m", symbol: "timer", tint: .green),
    Action(id: "settings", title: "System Settings", symbol: "gearshape.fill", tint: .gray),
  ]
  static let defaults = ["action:record", "action:screenshot", "action:color", "action:awake"]

  @Published private(set) var recording: Date?
  @Published private(set) var awake = false
  @Published private(set) var shortcuts: [String] = []
  @Published var status = ""
  @Published var confirmingTrash = false
  var onLens: () -> Void = {}
  var onFocus: () -> Void = {}
  var beforeCapture: () -> Void = {}
  private var recorder: Process?
  private var recorderInput: Pipe?
  private var recordingURL: URL?
  private var caffeinate: Process?

  func title(_ item: String) -> String {
    let (kind, value) = Self.split(item)
    switch kind {
    case "action": return Self.catalog.first { $0.id == value }?.title ?? value
    case "app": return URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
    case "url": return URL(string: value)?.host ?? value
    default: return value
    }
  }
  func icon(_ item: String) -> NSImage? {
    let (kind, value) = Self.split(item)
    return kind == "app" ? NSWorkspace.shared.icon(forFile: value) : nil
  }
  func symbol(_ item: String) -> (String, Color) {
    let (kind, value) = Self.split(item)
    switch kind {
    case "action":
      if value == "record", recording != nil { return ("stop.circle.fill", .red) }
      let action = Self.catalog.first { $0.id == value }
      return (action?.symbol ?? "questionmark", action?.tint ?? .white)
    case "shortcut": return ("square.stack.3d.up.fill", .pink)
    case "url": return ("globe", .blue)
    default: return ("app", .white)
    }
  }
  func isActive(_ item: String) -> Bool {
    item == "action:record" && recording != nil || item == "action:awake" && awake
  }
  static func split(_ item: String) -> (String, String) {
    guard let colon = item.firstIndex(of: ":") else { return ("", item) }
    return (String(item[..<colon]), String(item[item.index(after: colon)...]))
  }

  func run(_ item: String) {
    let (kind, value) = Self.split(item)
    switch kind {
    case "action": perform(value)
    case "app":
      guard value.hasSuffix(".app"), FileManager.default.fileExists(atPath: value) else { status = "That app has moved."; return }
      NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: value), configuration: .init())
    case "shortcut": runShortcut(value)
    case "url":
      guard let url = URL(string: value), url.scheme == "https" || url.scheme == "http" else { return }
      NSWorkspace.shared.open(url)
    default: break
    }
  }

  private func perform(_ id: String) {
    switch id {
    case "record": recording == nil ? startRecording() : stopRecording()
    case "screenshot":
      beforeCapture()
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    case "lens": onLens()
    case "color": pickColor()
    case "awake": toggleAwake()
    case "dark":
      script("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    case "mute":
      script("set volume output muted not (output muted of (get volume settings))")
    case "sleep": launch("/usr/bin/pmset", ["displaysleepnow"])
    case "downloads":
      NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
    case "trash": confirmingTrash = true
    case "focus": onFocus()
    case "settings": NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    default: break
    }
  }
  func emptyTrash() {
    confirmingTrash = false
    script("tell application \"Finder\" to empty trash")
    status = "Trash emptied."
  }

  // MARK: Screen recording

  /// Records the whole screen with clicks shown. Stop from the widget, the menu bar or the notch.
  func startRecording() {
    guard recording == nil else { return }
    guard CGPreflightScreenCaptureAccess() else {
      CGRequestScreenCaptureAccess()
      status = "Allow Molt under Screen Recording in System Settings, then try again."
      return
    }
    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
    let url = folder.appendingPathComponent("Molt Recording \(stamp).mov")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-v", "-C", "-k", "-x", url.path]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [weak self] _ in
      Task { @MainActor in self?.recordingEnded() }
    }
    do {
      beforeCapture()
      try process.run()
      recorder = process
      recorderInput = input
      recordingURL = url
      recording = Date()
      status = ""
    } catch { status = "Couldn't start recording." }
  }
  func stopRecording() {
    guard let recorder, recorder.isRunning else { recordingEnded(); return }
    // screencapture stops when it reads a key from its input.
    recorderInput?.fileHandleForWriting.write(Data("\n".utf8))
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if recorder.isRunning { recorder.interrupt() } }
  }
  private func recordingEnded() {
    recording = nil
    recorder = nil
    recorderInput = nil
    if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
      status = "Saved to Movies."
    }
    recordingURL = nil
  }

  // MARK: Other actions

  private func pickColor() {
    NSColorSampler().show { [weak self] color in
      guard let color = color?.usingColorSpace(.sRGB) else { return }
      let hex = String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(hex, forType: .string)
      Task { @MainActor in self?.status = "Copied \(hex)" }
    }
  }
  /// Keeps the Mac and display awake until turned off or Molt quits.
  private func toggleAwake() {
    if let caffeinate {
      caffeinate.terminate()
      self.caffeinate = nil
      awake = false
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    process.arguments = ["-di", "-w", String(ProcessInfo.processInfo.processIdentifier)]
    do {
      try process.run()
      caffeinate = process
      awake = true
    } catch { status = "Couldn't keep the Mac awake." }
  }
  func loadShortcuts() {
    Task {
      let output = await Self.output("/usr/bin/shortcuts", ["list"])
      shortcuts = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
    }
  }
  private func runShortcut(_ name: String) {
    Task {
      // Only names that exist in your Shortcuts library are ever run.
      if shortcuts.isEmpty { shortcuts = await Self.output("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init) }
      guard shortcuts.contains(name) else { status = "Shortcut \"\(name)\" wasn't found."; return }
      launch("/usr/bin/shortcuts", ["run", name])
    }
  }
  private func script(_ source: String) {
    Task.detached {
      var error: NSDictionary?
      NSAppleScript(source: source)?.executeAndReturnError(&error)
      let failed = error != nil
      await MainActor.run { if failed { self.status = "macOS didn't allow that. Check Automation in Privacy settings." } }
    }
  }
  private func launch(_ path: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
  }
  nonisolated static func output(_ path: String, _ arguments: [String]) async -> String {
    await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      guard (try? process.run()) != nil else { return "" }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return String(decoding: data, as: UTF8.self)
    }.value
  }
}
