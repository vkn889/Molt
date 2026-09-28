import AppKit
import MoltCore
import SwiftUI

@MainActor final class FileOrganizer: ObservableObject {
  @Published var plan: FileMovePlan?
  @Published var message = "Select files and a destination. Review every path before moving. No deletion or overwrite."
  private let url: URL
  private var blocked = false
  init(directory: URL) {
    url = directory.appendingPathComponent("file-move-journal.json")
    if FileManager.default.fileExists(atPath: url.path) {
      do { plan = try JSONDecoder().decode(FileMovePlan.self, from: Data(contentsOf: url)) }
      catch { blocked = true; message = "Move journal could not load. Original preserved. File operations are disabled." }
    }
  }
  func preview() {
    guard !blocked else { return }
    if let plan, plan.moves.contains(where: { ["completed", "running", "undoing"].contains($0.state) }) {
      message = "Undo the previous moves or explicitly forget that record before creating a new plan."; return
    }
    let files = NSOpenPanel(); files.allowsMultipleSelection = true; files.canChooseDirectories = false
    guard files.runModal() == .OK else { return }
    let folder = NSOpenPanel(); folder.canChooseFiles = false; folder.canChooseDirectories = true
    folder.message = "Choose the destination folder for the reviewed files."
    guard folder.runModal() == .OK, let target = folder.url else { return }
    do { plan = try FileMovePlan.preview(files: files.urls, folder: target); try persist(plan!); message = "Review the exact paths below. Dropping or selecting files does not authorize a move." }
    catch { message = error.localizedDescription }
  }
  private func persist(_ plan: FileMovePlan) throws { try JSONEncoder().encode(plan).write(to: url, options: .atomic) }
  func execute(undo: Bool) {
    guard !blocked, var current = plan else { return }
    do {
      if undo { try current.undo(persist: persist) } else { try current.execute(persist: persist) }
      message = undo ? "Undo finished." : "Moves completed. Undo remains available unless files change."
    } catch { message = error.localizedDescription }
    plan = current
  }
  func forget() {
    guard !blocked else { return }
    do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; plan = nil; message = "Record forgotten. No files changed." }
    catch { message = error.localizedDescription }
  }
}
struct FileOrganizerView: View {
  @ObservedObject var organizer: FileOrganizer
  @State private var confirmForget = false
  var body: some View {
    MoltCard(title: "Reviewed file organization") {
      Text(organizer.message).font(.caption)
      Button("Choose files and destination", action: organizer.preview)
      if let plan = organizer.plan {
        ForEach(plan.moves) { move in
          VStack(alignment: .leading) {
            Text(move.source); Text("→ \(move.destination)"); Text(move.state).foregroundStyle(.secondary)
          }.font(.caption).textSelection(.enabled)
        }
        HStack {
          Button("Approve these moves") { organizer.execute(undo: false) }.disabled(!plan.moves.allSatisfy { $0.state == "awaiting review" })
          Button("Undo completed moves") { organizer.execute(undo: true) }.disabled(!plan.moves.contains { $0.state == "completed" })
          Button("Forget record…") { confirmForget = true }
        }
        Text("Interrupted operations never replay. If a row says running or undoing after restart, inspect both paths before forgetting the record.").font(.caption)
      }
    }.confirmationDialog("Forget the undo record? Files will stay where they are.", isPresented: $confirmForget) {
      Button("Forget record", role: .destructive, action: organizer.forget)
    }
  }
}
