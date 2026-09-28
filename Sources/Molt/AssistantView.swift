import MoltCore
import SwiftUI

struct AssistantView: View {
  @ObservedObject var assistant: AssistantController
  @ObservedObject var controller: PetController
  @State private var ritualName = "Work with Molt"
  @State private var ritualMinutes = 25
  @State private var scheduleRitual = false
  @State private var ritualDate = Date().addingTimeInterval(3600)
  @FocusState private var inputFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("Ask Molt", systemImage: "bubble.left.and.text.bubble.right").font(
          MoltTheme.display(24))
        Spacer()
        Text("LOCAL · SUGGEST").font(.caption.monospaced()).foregroundStyle(.secondary)
      }
      Text(
        "Your words stay on this Mac. Only the text and project memory you select below are supplied to the model."
      ).font(.callout)
      Picker("AI provider", selection: $assistant.providerKind) {
        Text("Managed local").tag("managed")
        Text("Ollama (advanced)").tag("ollama")
      }.disabled(assistant.running).onChange(of: assistant.providerKind) { _ in
        assistant.models = []
        assistant.selectedModel = ""
      }
      if assistant.providerKind == "managed" {
        ManagedModelView(manager: assistant.modelManager, inferenceRunning: assistant.running)
      }
      HStack {
        Button("Connect / refresh", action: assistant.refresh).disabled(assistant.running)
        Picker("Local model", selection: $assistant.selectedModel) {
          Text("Choose model").tag("")
          ForEach(assistant.models) { model in
            Text(
              "\(model.id) · \(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))"
            ).tag(model.id)
          }
        }.disabled(assistant.running)
        Button("Unload", action: assistant.unload).disabled(
          assistant.running || assistant.selectedModel.isEmpty)
      }
      Text(assistant.status).font(.caption).accessibilityLabel("AI status: \(assistant.status)")
      if let error = assistant.storageError { Text(error).foregroundStyle(.red) }
      TextField(
        "Ask, rewrite, explain an error, or plan your next step…", text: $assistant.draft,
        axis: .vertical
      )
      .lineLimit(3...7).textFieldStyle(.roundedBorder).focused($inputFocused)
      HStack {
        Button("Attach text file", action: assistant.chooseFile)
        Button("Paste once", action: assistant.clipboard)
        Spacer()
        if assistant.running {
          Button("Stop", action: assistant.cancel)
        } else {
          Button("Interpret as action", action: assistant.interpret).disabled(
            assistant.selectedModel.isEmpty || assistant.draft.isEmpty)
          Button("Send", action: assistant.send).disabled(
            assistant.selectedModel.isEmpty || assistant.draft.isEmpty)
        }
      }
      if !assistant.attachment.isEmpty {
        DisclosureGroup("Supplied source: \(assistant.attachmentName)") {
          Text(String(assistant.attachment.prefix(12000))).font(.caption.monospaced())
            .textSelection(.enabled)
          Button("Remove attachment") {
            assistant.attachment = ""
            assistant.attachmentName = ""
          }
        }
      }
      if !assistant.reply.isEmpty {
        MoltCard(title: "Molt's response") {
          Text(assistant.reply).textSelection(.enabled).frame(
            maxWidth: .infinity, alignment: .leading)
          HStack {
            Button("Review saving as note") { assistant.propose(.saveNote, text: assistant.reply) }
              .disabled(assistant.running)
            Button("Clear response") { assistant.reply = "" }.disabled(assistant.running)
          }
        }
      }
      HStack {
        Button("Preview daily wrap-up context") {
          assistant.handoffSummary(controller: controller, meeting: false)
        }
        Button("Preview meeting context") {
          assistant.handoffSummary(controller: controller, meeting: true)
        }
      }
      projectPanel
      ritualPanel
      FileOrganizerView(organizer: assistant.fileOrganizer)
      MoltCard(title: "Explicit actions") {
        Text(
          "These controls create a concrete proposal. Nothing happens until you review and approve it."
        ).font(.caption)
        HStack {
          Button("Propose task from input") {
            assistant.propose(.createTask, text: assistant.draft)
          }.disabled(assistant.draft.isEmpty)
          Button("Propose 25-minute focus") {
            assistant.propose(.startFocus, text: "Focus together", minutes: 25)
          }
        }
      }
      ForEach(assistant.workspace.jobs.reversed()) { job in
        MoltCard(title: "\(job.proposal.tool.rawValue) · \(job.status)") {
          Text(
            job.proposal.tool == .openWorkspace
              ? (assistant.workspace.projects.first { $0.id.uuidString == job.proposal.text }?
                .folder ?? "Removed project") : job.proposal.text
          )
          .textSelection(.enabled)
          if let minutes = job.proposal.minutes { Text("Duration: \(minutes) minutes") }
          if !job.detail.isEmpty { Text(job.detail).font(.caption) }
          if job.status == "completed", job.resultSnapshot != nil {
            Button("Undo creation if unchanged") { assistant.undo(job.id, controller: controller) }
          }
          if job.status == "awaiting review" {
            HStack {
              Button("Approve and execute") { assistant.execute(job.id, controller: controller) }
                .disabled(assistant.storageError != nil)
              Button("Cancel") { assistant.dismiss(job.id) }
            }
          }
        }
      }
      Text(
        "Ollama is an optional advanced provider. Managed local uses a packaged worker and a separately downloaded compact model. Clean-install and Intel qualification remain release gates. No cloud fallback, shell execution, screen capture, or background clipboard collection is enabled."
      ).font(.caption).foregroundStyle(.secondary)
    }.onAppear { inputFocused = true }
  }
  private var ritualPanel: some View {
    MoltCard(title: "Workspace rituals") {
      Toggle(
        "Pause all rituals",
        isOn: Binding(
          get: { assistant.workspace.ritualsPaused ?? false },
          set: {
            assistant.workspace.ritualsPaused = $0
            _ = assistant.save()
          }))
      TextField("Ritual name", text: $ritualName)
      Stepper("Focus: \(ritualMinutes) minutes", value: $ritualMinutes, in: 1...180)
      Toggle("Schedule a one-time review", isOn: $scheduleRitual)
      if scheduleRitual { DatePicker("Review at", selection: $ritualDate) }
      Text(
        "Uses the selected project folder and focus duration. Manual and scheduled triggers prepare review cards; they never open apps or start focus without approval. Scheduled reviews appear while Molt is running or after it wakes."
      ).font(.caption)
      Button("Save ritual") {
        if assistant.workspace.rituals == nil { assistant.workspace.rituals = [] }
        assistant.workspace.rituals?.append(
          WorkspaceRitual(
            name: String(ritualName.prefix(100)), projectID: assistant.projectID,
            focusMinutes: ritualMinutes, scheduled: scheduleRitual ? ritualDate : nil))
        _ = assistant.save()
      }.disabled(ritualName.trimmingCharacters(in: .whitespaces).isEmpty)
      ForEach(assistant.workspace.rituals ?? []) { ritual in
        HStack {
          Text(ritual.name)
          if let date = ritual.scheduled { Text(date.formatted()).font(.caption) }
          Spacer()
          Button("Prepare") { assistant.prepareRitual(ritual) }
          Button("Delete") {
            assistant.workspace.rituals?.removeAll { $0.id == ritual.id }
            _ = assistant.save()
          }
        }
      }
    }
  }
  private var projectPanel: some View {
    MoltCard(title: "Projects and approved memory") {
      HStack {
        Picker("Project", selection: $assistant.projectID) {
          Text("None").tag(nil as UUID?)
          ForEach(assistant.workspace.projects) { project in
            Text(project.name).tag(Optional(project.id))
          }
        }
        Button("Choose folder", action: assistant.addProject)
      }
      if let index = assistant.workspace.projects.firstIndex(where: { $0.id == assistant.projectID }
      ) {
        Text(assistant.workspace.projects[index].folder).font(.caption).textSelection(.enabled)
        Toggle("Enable this project's scope", isOn: $assistant.workspace.projects[index].enabled)
        TextField(
          "Facts you want Molt to remember", text: $assistant.workspace.projects[index].facts,
          axis: .vertical)
        TextField(
          "Next step / resume checkpoint", text: $assistant.workspace.projects[index].nextStep,
          axis: .vertical)
        HStack {
          Button("Save memory") { _ = assistant.save() }
          Button("Review opening folder") {
            assistant.propose(
              .openWorkspace, text: assistant.workspace.projects[index].id.uuidString)
          }
          Button("Forget project") {
            assistant.workspace.projects.remove(at: index)
            assistant.projectID = nil
            assistant.searchResults = []
            _ = assistant.save()
          }
        }
        Toggle("Include this approved memory in my next request", isOn: $assistant.shareMemory)
        HStack {
          TextField("Find filenames in selected folder", text: $assistant.searchQuery).onSubmit(
            assistant.search)
          Button("Search", action: assistant.search)
        }
        Text(
          "Search visits at most 2,000 entries and returns 40 matches. Hidden files and dependency folders are excluded. Contents are read only when attached."
        ).font(.caption)
        ForEach(assistant.searchResults, id: \.path) { file in
          Button(file.path) { assistant.attach(file) }.font(.caption).lineLimit(2)
        }
      }
    }
  }
}

struct ManagedModelView: View {
  @ObservedObject var manager: ModelManager
  var inferenceRunning: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(manager.message).font(.caption)
      if manager.busy {
        ProgressView(value: manager.progress)
        Button("Cancel download", action: manager.cancel)
      } else {
        HStack {
          Button(
            manager.installed ? "Reinstall verified model" : "Download compact model",
            action: manager.install
          )
          .disabled(!manager.runtimeAvailable || inferenceRunning)
          if manager.installed {
            Button("Remove model", action: manager.uninstall).disabled(inferenceRunning)
          }
          Link(
            "Model and license",
            destination: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF")!)
        }
      }
      if !manager.runtimeAvailable {
        Text(
          "Managed worker is absent from this development build. Packaged builds include it; Ollama is available under Advanced."
        ).font(.caption)
      }
    }
  }
}
