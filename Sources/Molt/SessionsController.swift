import AppKit
import MoltCore
import SwiftUI

/// Indexes Claude Code and Codex conversations on this Mac, and optionally keeps a private copy
/// in Molt's folder so chats survive the tools' own cleanup. Nothing leaves the Mac.
@MainActor final class SessionsController: ObservableObject {
  @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "sessionsEnabled"); if enabled { scan() } else { sessions = []; records = [] } } }
  @Published var archive: Bool { didSet { UserDefaults.standard.set(archive, forKey: "sessionsArchive"); if archive { scan() } } }
  @Published private(set) var sessions: [AgentSession] = []
  @Published private(set) var records: [TokenRecord] = []
  @Published private(set) var busy = false
  @Published private(set) var transcript: [AgentMessage] = []
  @Published var selected: String? { didSet { loadTranscript() } }
  @Published private(set) var archivedCount = 0
  let archiveRoot: URL
  private var cache: [String: CacheEntry] = [:]
  private var lastScan = Date.distantPast

  struct CacheEntry: Sendable {
    var size: Int
    var modified: Date
    var session: AgentSession?
    var records: [TokenRecord]
  }
  nonisolated static let sources: [(tool: String, folder: String)] = [("Claude Code", ".claude/projects"), ("Codex", ".codex/sessions")]

  init(directory: URL, consent: Bool) {
    archiveRoot = directory.appendingPathComponent("Sessions")
    enabled = UserDefaults.standard.object(forKey: "sessionsEnabled") as? Bool ?? consent
    archive = UserDefaults.standard.object(forKey: "sessionsArchive") as? Bool ?? true
  }

  var selectedSession: AgentSession? { sessions.first { $0.id == selected } }
  func tokens(tool: String? = nil, since: Date) -> Int {
    records.filter { $0.date >= since && (tool == nil || $0.tool == tool) }.reduce(0) { $0 + $1.input + $1.output + $1.cached }
  }

  /// Scans at most once every 30 seconds unless forced.
  func scan(force: Bool = false) {
    guard enabled, !busy, force || Date().timeIntervalSince(lastScan) > 30 else { return }
    busy = true
    lastScan = Date()
    let cache = self.cache, archive = self.archive, root = archiveRoot
    Task {
      let result = await Task.detached(priority: .utility) { Self.index(cache: cache, archive: archive, root: root) }.value
      self.cache = result.cache
      self.sessions = result.sessions
      self.records = result.records
      self.archivedCount = result.archived
      self.busy = false
      if self.selected == nil || !self.sessions.contains(where: { $0.id == self.selected }) {
        self.selected = self.sessions.first?.id
      } else {
        self.loadTranscript()
      }
    }
  }
  struct FileChange: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var added: Int
    var removed: Int
  }
  @Published private(set) var changes: [FileChange] = []
  @Published private(set) var changesDirectory = ""
  @Published private(set) var diff: (path: String, text: String)?
  @Published private(set) var loadingChanges = false

  /// Files the agent edited in the selected conversation, with what's still uncommitted in each.
  func loadChanges() {
    guard let session = selectedSession else { changes = []; return }
    loadingChanges = true
    diff = nil
    let path = session.path, tool = session.tool, id = session.id
    Task {
      let result = await Task.detached(priority: .userInitiated) { () -> (String, [FileChange]) in
        guard let data = FileManager.default.contents(atPath: path) else { return ("", []) }
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        var directory = ""
        for line in lines.prefix(400) where line.contains("\"cwd\"") {
          guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
          directory = row["cwd"] as? String ?? (row["payload"] as? [String: Any])?["cwd"] as? String ?? ""
          if !directory.isEmpty { break }
        }
        let files = AgentChanges.files(lines: lines, tool: tool).map { file -> String in
          file.hasPrefix(directory + "/") ? String(file.dropFirst(directory.count + 1)) : file
        }
        guard !directory.isEmpty, !files.isEmpty else { return (directory, []) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "diff", "--numstat", "HEAD", "--"] + files.prefix(80)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var stats: [String: (added: Int, removed: Int)] = [:]
        if (try? process.run()) != nil {
          let output = pipe.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()
          stats = AgentChanges.numstat(String(decoding: output, as: UTF8.self))
        }
        return (directory, files.map { FileChange(path: $0, added: stats[$0]?.added ?? 0, removed: stats[$0]?.removed ?? 0) })
      }.value
      guard self.selected == id else { return }
      self.changesDirectory = result.0
      self.changes = result.1
      self.loadingChanges = false
    }
  }
  func showDiff(_ change: FileChange) {
    let directory = changesDirectory
    Task {
      let text = await QuickActions.output("/usr/bin/git", ["-C", directory, "diff", "HEAD", "--", change.path])
      diff = (change.path, text.isEmpty ? "No uncommitted changes in this file. They may already be committed." : String(text.prefix(60_000)))
    }
  }
  func closeDiff() { diff = nil }

  func reveal(_ session: AgentSession) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.path)])
  }
  func openArchive() {
    try? FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
    NSWorkspace.shared.open(archiveRoot)
  }
  private func loadTranscript() {
    guard let session = selectedSession else { transcript = []; return }
    let path = session.path, tool = session.tool
    Task {
      let messages = await Task.detached(priority: .userInitiated) { () -> [AgentMessage] in
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return [] }
        return Array(AgentSessionParser.messages(lines: text.components(separatedBy: .newlines), tool: tool).suffix(300))
      }.value
      if self.selected == session.id { self.transcript = messages }
    }
  }

  nonisolated private static func index(cache: [String: CacheEntry], archive: Bool, root: URL)
    -> (cache: [String: CacheEntry], sessions: [AgentSession], records: [TokenRecord], archived: Int)
  {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    var next: [String: CacheEntry] = [:]
    var seen: Set<String> = []
    var files = 0
    // Source transcripts first, then archived copies whose originals were removed.
    for (tool, folder) in sources {
      let sourceRoot = home.appendingPathComponent(folder)
      let archiveFolder = root.appendingPathComponent(tool)
      for (base, isArchive) in [(sourceRoot, false), (archiveFolder, true)] {
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
        for case let file as URL in enumerator {
          guard files < 3000, file.pathExtension == "jsonl",
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]),
            values.isSymbolicLink != true, let size = values.fileSize, size <= 60_000_000
          else { continue }
          let relative = String(file.path.dropFirst(base.path.count))
          let key = tool + relative
          if isArchive && seen.contains(key) { continue }
          seen.insert(key)
          files += 1
          let modified = values.contentModificationDate ?? Date.distantPast
          if archive && !isArchive {
            let copy = archiveFolder.appendingPathComponent(relative)
            let copyValues = try? copy.resourceValues(forKeys: [.fileSizeKey])
            if copyValues?.fileSize != size {
              try? fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
              try? fm.removeItem(at: copy)
              try? fm.copyItem(at: file, to: copy)
            }
          }
          if let hit = cache[file.path], hit.size == size, hit.modified == modified {
            next[file.path] = hit
            continue
          }
          guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else { continue }
          let lines = text.components(separatedBy: .newlines)
          next[file.path] = CacheEntry(
            size: size, modified: modified,
            session: AgentSessionParser.summary(lines: lines, tool: tool, path: file.path, modified: modified),
            records: LocalUsageParser.records(lines: lines, tool: tool, source: file.lastPathComponent)
              .filter { $0.date > Date().addingTimeInterval(-30 * 86400) })
        }
      }
    }
    var archived = 0
    for (tool, _) in sources {
      let folder = root.appendingPathComponent(tool)
      if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) {
        for case let file as URL in enumerator where file.pathExtension == "jsonl" { archived += 1 }
      }
    }
    let sessions = next.values.compactMap(\.session).sorted { $0.updated > $1.updated }
    // Resumed conversations repeat earlier messages; count each record once.
    var unique: [String: TokenRecord] = [:]
    for record in next.values.flatMap(\.records) { unique[record.tool + record.id] = record }
    return (next, sessions, Array(unique.values), archived)
  }
}
