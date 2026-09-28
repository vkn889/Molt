import MoltCore
import SwiftUI

struct CompanionView: View {
  @ObservedObject var controller: PetController
  var compact = false
  @State private var capture = ""
  @State private var captureKind = "task"
  var body: some View {
    HStack(spacing: 0) {
      if !compact {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Image(systemName: "leaf.fill")
            Text("molt").font(MoltTheme.display(30))
          }.padding(.bottom, 28)
          ForEach(
            [
              ("Today", "sun.max"), ("Ask Molt", "bubble.left"), ("Activity", "waveform.path.ecg"),
              ("Molt", "heart"),
              ("Home", "house"), ("Library", "books.vertical"), ("Settings", "slider.horizontal.3"),
            ], id: \.0
          ) { name, icon in
            Button {
              controller.tab = name
            } label: {
              Label(name, systemImage: icon).font(.system(size: 14, weight: .medium)).frame(
                maxWidth: .infinity, alignment: .leading
              ).padding(12).background(
                controller.tab == name ? MoltTheme.green.opacity(0.13) : .clear,
                in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
          }
          Spacer()
          CreatureView(
            appearance: controller.companion.appearance, atlasURL: controller.atlasURL,
            mood: controller.mood,
            moving: controller.dashboardVisible && !controller.companion.preferences.reducedMotion
              && controller.mood != "sweating",
            intensity: controller.companion.preferences.animationIntensity,
            stage: controller.state.stageID
          ).frame(height: 130)
          Text(controller.petName).font(MoltTheme.display(20))
          Text("Day \(controller.age + 1) together").font(.caption).foregroundStyle(.secondary)
          Label("Local by nature", systemImage: "lock.shield").font(.caption2).foregroundStyle(
            .secondary
          ).padding(.top, 20)
        }.padding(22).frame(width: 205).background(Color(red: 0.88, green: 0.92, blue: 0.85))
      }
      VStack(spacing: 0) {
        if compact {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(
                [
                  "Today", "Ask Molt", "Activity", "Molt", "Home", "Library", "Play", "Capture",
                  "Settings",
                ], id: \.self
              ) { name in
                Button(name) { controller.tab = name }.buttonStyle(.bordered).tint(
                  controller.tab == name ? .green : .gray)
              }
            }.padding(10)
          }
        }
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(
              controller.tab == "Today"
                ? "A little room for today."
                : controller.tab == "Molt" ? "Meet \(controller.petName)." : controller.tab
            ).font(MoltTheme.display(28))
            Text(
              controller.tab == "Today"
                ? Date().formatted(date: .complete, time: .omitted) : "Your companion. Your pace."
            ).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            controller.onCapture?()
          } label: {
            Label("Quick capture", systemImage: "plus")
          }.keyboardShortcut("k", modifiers: [.command, .shift])
        }.padding(26)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if !controller.companion.adoptionComplete { AdoptionView(controller: controller) }
            if let error = controller.error {
              HStack {
                Text(error).font(.callout)
                Spacer()
                Button("Dismiss") { controller.error = nil }
              }.padding().background(
                Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = controller.organizationError { Text(error).foregroundStyle(.red) }
            if controller.companion.clockCorrected {
              Text("Your clock moved backward. Timers are continuing from the last reliable time.")
                .font(.caption).foregroundStyle(.secondary)
            }
            switch controller.tab {
            case "Ask Molt": AssistantView(assistant: controller.assistant, controller: controller)
            case "Play": GameView(controller: controller)
            case "Capture": QuickCaptureView(controller: controller)
            case "Today": TodayView(controller: controller)
            case "Activity":
              ActivityDashboard(controller: controller, contexts: controller.contexts)
            case "Molt": PetDashboard(controller: controller)
            case "Home": HomeView(controller: controller)
            case "Library": LibraryView(controller: controller)
            default: SettingsView(controller: controller, contexts: controller.contexts)
            }
          }.padding(26)
        }
      }
    }.frame(minWidth: compact ? 0 : 930, minHeight: compact ? 0 : 720).background(MoltTheme.paper)
      .foregroundStyle(
        MoltTheme.ink
      ).preferredColorScheme(.light)
  }
}
struct AdoptionView: View {
  @ObservedObject var controller: PetController
  @State private var name = "Molt"
  @State private var palette = "sage"
  var body: some View {
    MoltCard(title: "A small beginning") {
      HStack {
        CreatureView(appearance: preview, mood: "happy", moving: false).frame(width: 90, height: 90)
        VStack(alignment: .leading) {
          Text("Choose a name and a look. Everything can change later.").font(.callout)
          TextField("Companion name", text: $name)
          Picker("Palette", selection: $palette) {
            ForEach(["sage", "ocean", "sunset", "violet"], id: \.self) { Text($0.capitalized) }
          }
        }
        Button("Meet \(name.isEmpty ? "Molt" : name)") {
          controller.changeCompanion {
            $0.name = name.isEmpty ? "Molt" : String(name.prefix(40))
            $0.appearance.palette = palette
            $0.adoptionComplete = true
            $0.remember("Our first day together.", kind: "adoption", at: Date())
          }
        }.buttonStyle(.borderedProminent).tint(MoltTheme.green)
      }
      Button("Skip for now") { controller.changeCompanion { $0.adoptionComplete = true } }.font(
        .caption)
    }
  }
  var preview: Appearance {
    var a = Appearance()
    a.palette = palette
    return a
  }
}
struct TodayView: View {
  @ObservedObject var controller: PetController
  @State private var minutes = 25
  @State private var selectedTask: UUID?
  var body: some View {
    MoltCard(title: "What’s next?") {
      let priorities = controller.organization.tasks.filter { $0.today && $0.completed == nil }
        .prefix(3)
      if priorities.isEmpty {
        Text("Choose up to three priorities in Library. There’s no rush to fill the day.")
          .foregroundStyle(.secondary)
      }
      ForEach(Array(priorities)) { task in
        HStack {
          Button {
            controller.updateOrganization { $0.completeTask(task.id, now: Date()) }
          } label: {
            Image(systemName: "circle")
          }
          Text(task.title)
          Spacer()
          Text("\(task.estimate)m").font(.caption).foregroundStyle(.secondary)
        }
      }
      if let reminder = controller.organization.reminders.filter({ !$0.completed }).min(by: {
        $0.due < $1.due
      }) {
        Divider()
        Label(
          "\(reminder.title) · \(reminder.due.formatted(date: .abbreviated, time: .shortened))",
          systemImage: "bell")
      }
      ForEach(Array(controller.contexts.events.prefix(2)), id: \.eventIdentifier) { event in
        Label(
          "\(event.title ?? "Calendar event") · \(event.startDate.formatted(date: .omitted, time: .shortened))",
          systemImage: "calendar")
      }
    }
    MoltCard(title: "Settle in together") {
      if let session = controller.organization.sessions.first(where: { $0.finished == nil }) {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(duration(session.duration(at: context.date))).font(
            .system(size: 38, weight: .medium, design: .monospaced))
          Text(
            session.lastResumed == nil
              ? "Paused. Resume whenever you’re ready." : "A little focus, a little company."
          ).foregroundStyle(.secondary)
        }
        HStack {
          Button(session.lastResumed == nil ? "Resume" : "Pause") {
            controller.changeFocus(session.lastResumed == nil ? "resume" : "pause")
          }
          Button("Add 5 minutes") { controller.changeFocus("extend") }
          Button("Stop focus") { controller.changeFocus("stop") }
        }
      } else {
        HStack {
          Picker("Duration", selection: $minutes) {
            Text("Count up").tag(0)
            Text("15 minutes").tag(15)
            Text("Pomodoro · 25 minutes").tag(25)
            Text("50 minutes").tag(50)
          }
          Button("Start focus") { controller.focus(minutes: minutes, task: selectedTask) }
            .buttonStyle(.borderedProminent).tint(MoltTheme.green)
        }
        Picker("Work on", selection: $selectedTask) {
          Text("Open focus").tag(nil as UUID?)
          ForEach(controller.organization.tasks.filter { $0.completed == nil }) {
            Text($0.title).tag(Optional($0.id))
          }
        }
        Text(
          "You can pause or stop at any time. Sleep pauses focus. Rewards reflect recorded minutes, with a daily cap."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
    HStack(alignment: .top) {
      MoltCard(title: "Your day, gently") {
        Text(
          "\(controller.organization.tasks.filter { $0.completed.map { Calendar.current.isDateInToday($0) } ?? false }.count) tasks completed"
        )
        Text(
          "\(Int(controller.organization.sessions.filter { Calendar.current.isDateInToday($0.started) }.reduce(0) { $0 + $1.elapsed } / 60)) focus minutes"
        )
        Text(controller.companion.memories.last?.text ?? "A new memory is waiting to happen.").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      MoltCard(title: "A little check-in") {
        Text(controller.message).font(.callout)
        Button("Spend a moment with \(controller.petName)") { controller.tab = "Molt" }
        Button("Open scratchpad") {
          controller.capture("Scratchpad", kind: "note")
          controller.tab = "Library"
        }
      }
    }
    RoutineView(controller: controller)
  }
  func duration(_ seconds: Double) -> String {
    let s = Int(seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
  }
}
