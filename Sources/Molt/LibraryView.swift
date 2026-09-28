import MoltCore
import SwiftUI

struct LibraryView: View {
  @ObservedObject var controller: PetController
  @State private var search = ""
  @State private var title = ""
  @State private var noteTitle = ""
  @State private var reminderTitle = ""
  @State private var filter = "Inbox"
  @State private var reminderDate = Date().addingTimeInterval(3600)
  @State private var recurrence = "none"
  var body: some View {
    MoltCard(title: "A place for your thoughts") {
      TextField("Search tasks, notes, tags and projects", text: $search).textFieldStyle(
        .roundedBorder)
      HStack {
        TextField("A task to remember", text: $title).onSubmit(addTask)
        Button("Add task", action: addTask)
      }
      Picker("View", selection: $filter) {
        ForEach(["Inbox", "Today", "Upcoming", "Completed", "All"], id: \.self) { Text($0) }
      }.pickerStyle(.segmented)
      ForEach(tasks) { task in TaskRow(controller: controller, taskID: task.id) }
      if tasks.isEmpty {
        Text("Nothing here yet. Leave some room for possibility.").foregroundStyle(.secondary)
          .padding(.vertical)
      }
    }
    MoltCard(title: "Notes and saved links") {
      HStack {
        TextField("Note title", text: $noteTitle)
        Button("New note") {
          controller.updateOrganization {
            $0.notes.append(Note(noteTitle.isEmpty ? "Untitled note" : noteTitle))
          }
          noteTitle = ""
        }
      }
      ForEach(
        controller.organization.notes.filter {
          search.isEmpty
            || "\($0.title) \($0.body) \($0.tags)".localizedCaseInsensitiveContains(search)
        }.sorted { $0.pinned && !$1.pinned }
      ) { note in NoteRow(controller: controller, noteID: note.id) }
    }
    MoltCard(title: "Reminders") {
      Text(
        "Choose an exact date before saving. Notification delivery depends on macOS permission and settings; due reminders always remain here."
      ).font(.caption).foregroundStyle(.secondary)
      TextField("Remind me to…", text: $reminderTitle)
      HStack {
        DatePicker("When", selection: $reminderDate)
        Picker("Repeat", selection: $recurrence) {
          ForEach(["none", "daily", "weekly", "monthly"], id: \.self) { Text($0.capitalized) }
        }
        Button("Save reminder") {
          guard !reminderTitle.isEmpty else { return }
          controller.updateOrganization {
            var r = Reminder(reminderTitle, due: reminderDate)
            r.recurrence = recurrence
            $0.reminders.append(r)
          }
          controller.configureContext()
          reminderTitle = ""
        }
      }
      ForEach(controller.organization.reminders.filter { !$0.completed }.sorted { $0.due < $1.due })
      { r in
        HStack {
          VStack(alignment: .leading) {
            Text(r.title)
            Text("\(r.due.formatted()) · \(r.recurrence) · \(r.timeZone)").font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Snooze 10m") { updateReminder(r.id) { $0.due = Date().addingTimeInterval(600) } }
          Button("Done") { updateReminder(r.id) { $0.complete() } }
          Button("Dismiss") { updateReminder(r.id) { $0.completed = true } }
        }
      }
    }
  }
  var tasks: [WorkTask] {
    controller.organization.tasks.filter { t in
      let matches =
        search.isEmpty
        || "\(t.title) \(t.tags) \(t.project)".localizedCaseInsensitiveContains(search)
      let included =
        filter == "All"
        || (filter == "Completed"
          ? t.completed != nil
          : t.completed == nil
            && (filter == "Today" ? t.today : filter == "Upcoming" ? t.due != nil : true))
      return matches && included
    }.sorted { $0.priority > $1.priority }
  }
  func addTask() {
    controller.capture(title, kind: "task")
    title = ""
  }
  func updateReminder(_ id: UUID, change: (inout Reminder) -> Void) {
    controller.updateOrganization { o in
      if let i = o.reminders.firstIndex(where: { $0.id == id }) { change(&o.reminders[i]) }
    }
    controller.configureContext()
  }
}
struct TaskRow: View {
  @ObservedObject var controller: PetController
  var taskID: UUID
  @State private var expanded = false
  @State private var step = ""
  var task: WorkTask { controller.organization.tasks.first { $0.id == taskID } ?? WorkTask("") }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button {
          controller.updateOrganization { $0.completeTask(taskID, now: Date()) }
        } label: {
          Image(systemName: task.completed == nil ? "circle" : "checkmark.circle.fill")
        }.buttonStyle(.plain).accessibilityLabel(
          task.completed == nil ? "Complete \(task.title)" : "Undo completion")
        Text(task.title).strikethrough(task.completed != nil)
        Spacer()
        if let due = task.due {
          Text(due.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(
            .secondary)
        }
        Button {
          edit { t in
            if !t.today
              && controller.organization.tasks.filter({ $0.today && $0.completed == nil }).count
                >= 3
            {
              controller.error = "Today has three priorities. Unpin one before adding another."
            } else {
              t.today.toggle()
            }
          }
        } label: {
          Image(systemName: task.today ? "star.fill" : "star")
        }.help("Choose as a Today priority")
        Button {
          expanded.toggle()
        } label: {
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
        }.help("Task details")
      }
      if expanded {
        TextField("Title", text: binding(\.title))
        HStack {
          TextField("Project", text: binding(\.project))
          TextField("Tags", text: binding(\.tags))
          Stepper("\(task.estimate)m", value: intBinding(\.estimate), in: 5...480, step: 5)
        }
        HStack {
          Picker("Priority", selection: intBinding(\.priority)) {
            Text("Normal").tag(0)
            Text("Important").tag(1)
            Text("High").tag(2)
          }
          Toggle(
            "Due date",
            isOn: Binding(
              get: { task.due != nil }, set: { on in edit { $0.due = on ? Date() : nil } }))
          if task.due != nil {
            DatePicker(
              "Due",
              selection: Binding(
                get: { task.due ?? Date() }, set: { value in edit { $0.due = value } }))
          }
        }
        Picker("Repeat", selection: binding(\.recurrence)) {
          ForEach(["none", "daily", "weekly", "monthly"], id: \.self) { Text($0.capitalized) }
        }
        ForEach(task.checklist) { item in
          Toggle(
            item.text,
            isOn: Binding(
              get: { item.done },
              set: { on in
                edit { t in
                  if let i = t.checklist.firstIndex(where: { $0.id == item.id }) {
                    t.checklist[i].done = on
                  }
                }
              }))
        }
        HStack {
          TextField("Next small step", text: $step)
          Button("Add step") {
            if !step.isEmpty {
              edit { $0.checklist.append(ChecklistItem(step)) }
              step = ""
            }
          }
          Button("Use three-step template") {
            edit {
              $0.checklist += [
                ChecklistItem("Prepare"), ChecklistItem("Make progress"), ChecklistItem("Review"),
              ]
            }
          }
        }
        HStack {
          Button("Postpone one day") {
            edit {
              $0.due = Calendar.current.date(byAdding: .day, value: 1, to: $0.due ?? Date())
              $0.history.append("Postponed by choice on \(Date().formatted())")
            }
          }
          Button("Archive as completed") {
            controller.updateOrganization { $0.completeTask(taskID, now: Date()) }
          }
        }
        ForEach(Array(task.history.suffix(4).enumerated()), id: \.offset) { _, text in
          Text(text).font(.caption2).foregroundStyle(.secondary)
        }
      }
    }.padding(12).background(MoltTheme.green.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
  }
  func edit(_ change: (inout WorkTask) -> Void) {
    controller.updateOrganization { o in
      if let i = o.tasks.firstIndex(where: { $0.id == taskID }) { change(&o.tasks[i]) }
    }
  }
  func binding(_ key: WritableKeyPath<WorkTask, String>) -> Binding<String> {
    Binding(get: { task[keyPath: key] }, set: { v in edit { $0[keyPath: key] = v } })
  }
  func intBinding(_ key: WritableKeyPath<WorkTask, Int>) -> Binding<Int> {
    Binding(get: { task[keyPath: key] }, set: { v in edit { $0[keyPath: key] = v } })
  }
}
struct NoteRow: View {
  @ObservedObject var controller: PetController
  var noteID: UUID
  @State private var expanded = false
  var note: Note { controller.organization.notes.first { $0.id == noteID } ?? Note("") }
  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading) {
        TextField("Title", text: binding(\.title))
        TextEditor(text: binding(\.body)).font(.body).frame(minHeight: 130).border(
          .gray.opacity(0.15))
        HStack {
          TextField("Tags", text: binding(\.tags))
          TextField("Explicitly saved link", text: binding(\.link))
        }
        Picker(
          "Related task",
          selection: Binding(get: { note.taskID }, set: { id in edit { $0.taskID = id } })
        ) {
          Text("None").tag(nil as UUID?)
          ForEach(controller.organization.tasks) { Text($0.title).tag(Optional($0.id)) }
        }
        Toggle("Pinned", isOn: Binding(get: { note.pinned }, set: { v in edit { $0.pinned = v } }))
        if let url = URL(string: note.link), ["https", "http"].contains(url.scheme) {
          Link("Open saved link", destination: url)
        }
      }.padding(.vertical, 8)
    } label: {
      Label(note.title, systemImage: note.pinned ? "pin.fill" : "note.text")
    }
  }
  func edit(_ change: (inout Note) -> Void) {
    controller.updateOrganization { o in
      if let i = o.notes.firstIndex(where: { $0.id == noteID }) {
        change(&o.notes[i])
        o.notes[i].modified = Date()
      }
    }
  }
  func binding(_ key: WritableKeyPath<Note, String>) -> Binding<String> {
    Binding(get: { note[keyPath: key] }, set: { v in edit { $0[keyPath: key] = v } })
  }
}
struct RoutineView: View {
  @ObservedObject var controller: PetController
  @State private var title = ""
  var body: some View {
    MoltCard(title: "Routines, without streak pressure") {
      HStack {
        TextField("A routine, such as morning reset", text: $title)
        Button("Add") {
          guard !title.isEmpty else { return }
          controller.updateOrganization {
            var r = Routine(title)
            r.steps = [ChecklistItem("Take a breath"), ChecklistItem("Choose one small next step")]
            $0.routines.append(r)
          }
          title = ""
        }
      }
      ForEach(controller.organization.routines) { routine in
        VStack(alignment: .leading) {
          HStack {
            Text(routine.title).font(.headline)
            Spacer()
            let count = routine.checkIns.filter { $0 >= Date().addingTimeInterval(-7 * 86400) }
              .count
            Text("\(count) / \(routine.weeklyTarget) this week").font(.caption)
          }
          ForEach(routine.steps) { step in
            Toggle(
              step.text,
              isOn: Binding(
                get: { step.done },
                set: { value in
                  edit(routine.id) { r in
                    if let i = r.steps.firstIndex(where: { $0.id == step.id }) {
                      r.steps[i].done = value
                    }
                  }
                }))
          }
          Stepper(
            "Weekly target: \(routine.weeklyTarget)",
            value: Binding(
              get: { routine.weeklyTarget }, set: { v in edit(routine.id) { $0.weeklyTarget = v } }),
            in: 1...7)
          Button("Check in for today") {
            edit(routine.id) { r in
              if !r.checkIns.contains(where: { Calendar.current.isDateInToday($0) }) {
                r.checkIns.append(Date())
                r.checkIns = Array(r.checkIns.suffix(366))
                r.steps = r.steps.map { ChecklistItem($0.text) }
              }
            }
          }.disabled(routine.checkIns.contains { Calendar.current.isDateInToday($0) })
        }.padding(.vertical, 8)
      }
    }
  }
  func edit(_ id: UUID, change: (inout Routine) -> Void) {
    controller.updateOrganization { o in
      if let i = o.routines.firstIndex(where: { $0.id == id }) { change(&o.routines[i]) }
    }
  }
}
