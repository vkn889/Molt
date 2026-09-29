import Foundation

public enum AssistantTool: String, Codable, CaseIterable, Sendable {
  case createTask, saveNote, startFocus, openWorkspace
}
public struct ToolProposal: Codable, Identifiable, Sendable {
  public var id: UUID
  public var tool: AssistantTool
  public var text: String
  public var minutes: Int?
  public init(tool: AssistantTool, text: String, minutes: Int? = nil) {
    id = UUID()
    self.tool = tool
    self.text = text
    self.minutes = minutes
  }
  public func validate() throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 8000 else {
      throw MoltError.invalid("Provide between 1 and 8,000 characters.")
    }
    if tool == .startFocus, !(1...180).contains(minutes ?? 0) {
      throw MoltError.invalid("Focus duration must be 1 to 180 minutes.")
    }
  }
  public static func parse(_ text: String) throws -> ToolProposal {
    let proposal = try JSONDecoder().decode(ToolProposal.self, from: Data(text.utf8))
    try proposal.validate()
    return proposal
  }
}
public struct AssistantJob: Codable, Identifiable {
  public var id: UUID { proposal.id }
  public var proposal: ToolProposal
  public var status = "awaiting review"
  public var detail = ""
  public var created = Date()
  public var resultSnapshot: String?
  public init(_ proposal: ToolProposal) { self.proposal = proposal }
}
public struct ProjectMemory: Codable, Identifiable {
  public var id = UUID()
  public var name: String
  public var folder: String
  public var facts = ""
  public var nextStep = ""
  public var enabled = true
  public init(name: String, folder: String) {
    self.name = name
    self.folder = folder
  }
}
public struct AssistantWorkspace: Codable {
  public var schemaVersion: Int? = 1
  public var projects: [ProjectMemory] = []
  public var jobs: [AssistantJob] = []
  public var rituals: [WorkspaceRitual]?
  public var ritualsPaused: Bool?
  public init() {}
  public mutating func reconcile() {
    for index in jobs.indices where jobs[index].status == "running" {
      jobs[index].status = "failed"
      jobs[index].detail =
        "Interrupted. Check the result before creating a new request. This action will not replay."
    }
    trimHistory()
  }
  public mutating func enqueue(_ proposals: [ToolProposal]) throws {
    for proposal in proposals { try proposal.validate() }
    let pending = jobs.filter { $0.status == "awaiting review" || $0.status == "running" }
    guard pending.count + proposals.count <= 100 else {
      throw MoltError.invalid(
        "Review or cancel pending actions before adding more. The limit is 100.")
    }
    guard Set(proposals.map(\.id)).count == proposals.count,
      !proposals.contains(where: { proposal in jobs.contains { $0.id == proposal.id } })
    else { throw MoltError.invalid("This action is already recorded.") }
    jobs.append(contentsOf: proposals.map(AssistantJob.init))
    trimHistory()
  }
  public mutating func trimHistory(now: Date = Date()) {
    let pending = jobs.filter { $0.status == "awaiting review" || $0.status == "running" }
    let cutoff = now.addingTimeInterval(-30 * 86400)
    let recent = jobs.filter {
      $0.status != "awaiting review" && $0.status != "running" && $0.created >= cutoff
    }.suffix(100)
    jobs = (pending + recent).sorted { $0.created < $1.created }
  }

}
public struct FileSearchHit: Identifiable, Sendable {
  public var id: String { url.path }
  public var url: URL
  public var excerpt: String?
}
public enum ApprovedFiles {
  public static func contains(_ file: URL, in folder: URL) -> Bool {
    let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
    let candidate = file.resolvingSymlinksInPath().standardizedFileURL.path
    return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }
  public static func text(at file: URL) throws -> String {
    let allowed = ["txt", "md", "log", "swift", "json", "csv", "py", "js", "ts", "html", "css"]
    guard allowed.contains(file.pathExtension.lowercased()) else {
      throw MoltError.invalid("Choose a plain-text, Markdown, code, JSON, CSV, or log file.")
    }
    let attrs = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard attrs.isRegularFile == true, (attrs.fileSize ?? Int.max) <= 256_000 else {
      throw MoltError.invalid("Choose a regular text file smaller than 256 KB.")
    }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 256_001) ?? Data()
    guard data.count <= 256_000, let text = String(data: data, encoding: .utf8) else {
      throw MoltError.invalid("This file is too large or is not UTF-8 text.")
    }
    return text
  }
  public static func search(_ query: String, folder: URL) -> [URL] {
    searchHits(query, folder: folder, includeContents: false).map(\.url)
  }
  public static func searchHits(_ query: String, folder: URL, includeContents: Bool)
    -> [FileSearchHit]
  {
    guard folder.resolvingSymlinksInPath().path == folder.standardizedFileURL.path,
      !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let files = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var results: [FileSearchHit] = []
    var visited = 0
    var scannedBytes = 0
    for case let file as URL in files {
      visited += 1
      if visited > 2000 || results.count >= 40 || Task.isCancelled { break }
      if ["node_modules", "build", "dist", "vendor"].contains(file.lastPathComponent) {
        files.skipDescendants()
        continue
      }
      guard contains(file, in: folder),
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
        values.isRegularFile == true
      else { continue }
      if file.lastPathComponent.localizedCaseInsensitiveContains(query) {
        results.append(FileSearchHit(url: file, excerpt: nil))
        continue
      }
      guard includeContents, let size = values.fileSize, size <= 64_000,
        scannedBytes + size <= 2_000_000
      else { continue }
      // Account attempted reads as well as matches, keeping each search bounded.
      scannedBytes += size
      guard let contents = try? text(at: file),
        let match = contents.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
      else { continue }
      let start =
        contents.index(match.lowerBound, offsetBy: -60, limitedBy: contents.startIndex)
        ?? contents.startIndex
      let end =
        contents.index(match.upperBound, offsetBy: 100, limitedBy: contents.endIndex)
        ?? contents.endIndex
      results.append(
        FileSearchHit(
          url: file,
          excerpt: String(contents[start..<end]).replacingOccurrences(of: "\n", with: " ")))
    }
    return results
  }

}

public struct WorkspaceRitual: Codable, Identifiable {
  public var id = UUID()
  public var name: String
  public var projectID: UUID?
  public var focusMinutes: Int
  public var scheduled: Date?
  public var enabled = true
  public init(name: String, projectID: UUID?, focusMinutes: Int, scheduled: Date? = nil) {
    self.name = name
    self.projectID = projectID
    self.focusMinutes = focusMinutes
    self.scheduled = scheduled
  }
}
