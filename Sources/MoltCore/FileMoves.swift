import CryptoKit
import Foundation

public struct FileMove: Codable, Identifiable {
  public var id = UUID()
  public var source: String
  public var destination: String
  public var digest: String
  public var state = "awaiting review"
}
public struct FileMovePlan: Codable, Identifiable {
  public var id = UUID()
  public var destinationFolder: String
  public var moves: [FileMove]
  public var created = Date()
  public var detail = ""
  public static func preview(files: [URL], folder: URL) throws -> FileMovePlan {
    guard !files.isEmpty, files.count <= 30 else {
      throw MoltError.invalid("Choose 1 to 30 files.")
    }
    let root = folder.resolvingSymlinksInPath().standardizedFileURL
    var seen = Set<String>()
    let moves = try files.map { source -> FileMove in
      let original = source.resolvingSymlinksInPath().standardizedFileURL
      guard original == source.standardizedFileURL else {
        throw MoltError.invalid("Symbolic links are not moved.")
      }
      let destination = root.appendingPathComponent(source.lastPathComponent)
      guard seen.insert(destination.path).inserted, original != destination,
        !FileManager.default.fileExists(atPath: destination.path)
      else {
        throw MoltError.invalid(
          "A destination collides. Choose another folder or rename the file first.")
      }
      return FileMove(
        source: original.path, destination: destination.path, digest: try fingerprint(original))
    }
    return FileMovePlan(destinationFolder: root.path, moves: moves)
  }
  public static func fingerprint(_ url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      (values.fileSize ?? Int.max) <= 100_000_000
    else {
      throw MoltError.invalid("Only regular files up to 100 MB can be moved in this release.")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
  public mutating func execute(persist: (FileMovePlan) throws -> Void) throws {
    // Full preflight before the first mutation. Never overwrite a destination.
    for move in moves {
      guard move.state == "awaiting review", try valid(move, undo: false) else {
        throw MoltError.invalid(
          "Files changed since preview, destination is occupied, or this operation already ran. Make a new preview."
        )
      }
    }
    for index in moves.indices {
      moves[index].state = "running"
      try persist(self)
      do {
        guard try valid(moves[index], undo: false) else {
          throw MoltError.invalid("File changed during execution.")
        }
        try FileManager.default.moveItem(
          atPath: moves[index].source, toPath: moves[index].destination)
        moves[index].state = "completed"
        try persist(self)
      } catch {
        moves[index].state = "failed"
        detail = error.localizedDescription
        try? persist(self)
        throw error
      }
    }
  }
  public mutating func undo(persist: (FileMovePlan) throws -> Void) throws {
    for index in moves.indices.reversed() where moves[index].state == "completed" {
      guard try valid(moves[index], undo: true) else {
        throw MoltError.invalid("Undo stopped: a file changed or its original path is occupied.")
      }
      moves[index].state = "undoing"
      try persist(self)
      do {
        try FileManager.default.moveItem(
          atPath: moves[index].destination, toPath: moves[index].source)
        moves[index].state = "undone"
        try persist(self)
      } catch {
        detail = error.localizedDescription
        try? persist(self)
        throw error
      }
    }
  }
  private func valid(_ move: FileMove, undo: Bool) throws -> Bool {
    let source = URL(fileURLWithPath: undo ? move.destination : move.source)
    let destination = URL(fileURLWithPath: undo ? move.source : move.destination)
    guard
      source.resolvingSymlinksInPath().path == source.path
        && destination.deletingLastPathComponent().resolvingSymlinksInPath().path
          == destination.deletingLastPathComponent().path
        && URL(fileURLWithPath: move.destination).deletingLastPathComponent().path
          == destinationFolder
        && !FileManager.default.fileExists(atPath: destination.path)
    else { return false }
    return try Self.fingerprint(source) == move.digest
  }
}
