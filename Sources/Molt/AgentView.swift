import SwiftUI
import MoltCore

struct AgentView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var assistant: AssistantController
  @State private var memory = ""
  @State private var editingMemory: UUID?
  @State private var filter = "All"
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Task mode").font(MoltTheme.display(22))
      Text("Describe a goal. Molt can prepare independent tasks, notes and focus sessions. Review each step before it runs. File organization remains in AI & tools.").font(.caption)
      TextField("What would you like to accomplish?", text: $assistant.draft, axis: .vertical)
      HStack {
        Button("Prepare plan", action: assistant.planTask).disabled(assistant.running || assistant.selectedModel.isEmpty || assistant.draft.isEmpty)
        if assistant.running { Button("Stop", action: assistant.cancel) }
        Button("AI setup & file tools") { controller.tab = "AI & tools" }
      }
      Text(assistant.status).font(.caption)
      DisclosureGroup("Approved memory") {
        Text("Only facts you save here are remembered. Enabled memories are supplied to personal chat. Pause or forget them anytime. Transcripts are not saved automatically.").font(.caption)
        TextField("A preference or fact to remember", text: $memory, axis: .vertical)
        Button("Approve and remember") { if assistant.remember(memory, replacing: editingMemory) { memory = ""; editingMemory = nil } }.disabled(memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if editingMemory != nil { Button("Cancel edit") { memory = ""; editingMemory = nil } }
        ForEach(assistant.workspace.memories ?? []) { item in
          VStack(alignment: .leading) {
            Text(item.text).textSelection(.enabled)
            HStack {
              Button(item.enabled ? "Pause" : "Enable") { assistant.changeMemory(item.id, remove: false) }
              Button("Edit") { memory = item.text; editingMemory = item.id }
              Button("Forget") { assistant.changeMemory(item.id, remove: true) }
            }.font(.caption)
          }
        }
      }
      Divider()
      Text("Action history").font(.headline)
      Picker("Show", selection: $filter) {
        ForEach(["All", "Awaiting review", "Completed", "Failed", "Undone", "Canceled"], id: \.self) { Text($0).tag($0) }
      }
      Text("Actions are recorded before execution. Interrupted actions never replay. Completed records expire after 30 days or 100 entries. Undo is available for unchanged tasks and notes.").font(.caption)
      ForEach(assistant.workspace.jobs.reversed().filter { filter == "All" || $0.status == filter.lowercased() }) { job in
        VStack(alignment: .leading, spacing: 6) {
          Text("\(job.proposal.tool.rawValue) · \(job.status)").font(.headline)
          Text(job.proposal.text).textSelection(.enabled)
          if let minutes = job.proposal.minutes { Text("\(minutes) minutes") }
          Text(job.created.formatted()).font(.caption2)
          Text(job.detail).font(.caption)
          if job.status == "awaiting review" {
            HStack {
              Button("Approve and execute") { assistant.execute(job.id, controller: controller) }.disabled(assistant.storageError != nil)
              Button("Cancel step") { assistant.dismiss(job.id) }
            }
          }
          if job.status == "completed", job.resultSnapshot != nil {
            Button("Undo if unchanged") { assistant.undo(job.id, controller: controller) }
          }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
      }
      Button("Forget finished history", action: assistant.forgetFinishedJobs)
    }
  }
}
