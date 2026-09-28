import MoltCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var contexts: ContextAdapters
  var body: some View {
    MoltCard(title: "Your companion’s identity") {
      TextField("Name", text: companionString(\.name))
      TextField("Nickname", text: companionString(\.nickname))
      TextField("A little profile", text: companionString(\.profile))
      DatePicker(
        "Birthday",
        selection: Binding(
          get: { controller.companion.birthday },
          set: { value in controller.changeCompanion { $0.birthday = value } }),
        displayedComponents: .date)
      Text(
        "Adopted \(controller.companion.adopted.formatted(date: .abbreviated, time: .omitted)). Renaming never resets progress."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "A comfortable rhythm") {
      Toggle(
        "Vacation: freeze care decay",
        isOn: Binding(
          get: { controller.companion.preferences.vacation },
          set: { value in
            controller.tick()
            controller.changeCompanion { $0.preferences.vacation = value }
            if value { controller.stopActivity() }
          }))
      Toggle("Adaptive personality", isOn: pref(\.adaptivePersonality))
      Picker(
        "Companion mode",
        selection: Binding(
          get: { controller.companion.preferences.mode },
          set: { value in
            controller.changeCompanion { c in
              c.preferences.mode = value
              c.preferences.talkativeness = value == "quiet coworker" ? "silent" : "gentle"
              c.preferences.animationIntensity = value == "playful friend" ? 1 : 0.4
            }
          })
      ) {
        ForEach(["quiet coworker", "playful friend", "focus partner", "custom"], id: \.self) {
          Text($0.capitalized)
        }
      }
      HStack {
        Stepper(
          "Sleep from \(controller.companion.preferences.sleepStart):00", value: pref(\.sleepStart),
          in: 0...23)
        Stepper(
          "Until \(controller.companion.preferences.sleepEnd):00", value: pref(\.sleepEnd),
          in: 0...23)
      }
      HStack {
        Stepper(
          "Quiet from \(controller.companion.preferences.quietStart):00", value: pref(\.quietStart),
          in: 0...23)
        Stepper(
          "Until \(controller.companion.preferences.quietEnd):00", value: pref(\.quietEnd),
          in: 0...23)
      }
      Toggle("Optional soft interaction sounds", isOn: pref(\.sound))
      Text(
        "Sound is off by default and stays silent during quiet hours. Every cue also appears visually."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "Desktop and accessibility") {
      Toggle("Reduce motion", isOn: pref(\.reducedMotion))
      Toggle("High-contrast creature outline", isOn: pref(\.highContrast))
      HStack {
        Text("Creature size")
        Slider(value: pref(\.size), in: 0.75...1.5)
      }
      HStack {
        Text("Animation intensity")
        Slider(value: pref(\.animationIntensity), in: 0...1)
      }
      Picker("Speech bubbles", selection: pref(\.talkativeness)) {
        Text("Gentle").tag("gentle")
        Text("Silent").tag("silent")
      }
      Picker("Movement", selection: pref(\.movement)) {
        Text("Stationary").tag("stationary")
        Text("Bounded wandering").tag("bounded")
        Text("Hide pet").tag("hide")
      }
      Picker("Preferred display", selection: pref(\.preferredDisplay)) {
        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { i, screen in
          Text(screen.localizedName).tag(i)
        }
      }
      Toggle("Show alongside full-screen apps where supported", isOn: pref(\.fullScreen))
      Toggle("Click-through pet. Restore interaction in the menu bar.", isOn: pref(\.clickThrough))
      Button("Bring Molt back") { controller.onRecoverPet?() }
      Toggle(
        "Launch at login",
        isOn: Binding(
          get: { SMAppService.mainApp.status == .enabled }, set: { controller.setLogin($0) }))
      Text(
        "Command-Shift-K opens quick capture while Molt is active. No system-wide keys are captured."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "Permissions, one choice at a time") {
      Toggle("Local system health", isOn: $controller.healthEnabled)
      Toggle(
        "macOS notifications",
        isOn: Binding(
          get: { controller.organization.consent.notifications },
          set: { value in
            if value {
              contexts.requestNotifications { granted in
                controller.updateOrganization { $0.consent.notifications = granted }
                controller.configureContext()
              }
            } else {
              controller.updateOrganization { $0.consent.notifications = false }
              controller.configureContext()
            }
          }))
      Text(contexts.notificationStatus).font(.caption).foregroundStyle(.secondary)
      Toggle(
        "Read selected calendars",
        isOn: Binding(
          get: { controller.organization.consent.calendar },
          set: { value in
            if value {
              contexts.enableCalendar { granted in
                controller.updateOrganization { $0.consent.calendar = granted }
                controller.configureContext()
              }
            } else {
              controller.updateOrganization { $0.consent.calendar = false }
              controller.configureContext()
            }
          }))
      Text(
        "Calendar access only reads the calendars you select below. Molt never edits events. macOS may describe the permission as full access."
      ).font(.caption).foregroundStyle(.secondary)
      if let error = contexts.calendarError { Text(error).font(.caption).foregroundStyle(.orange) }
      ForEach(contexts.calendars, id: \.calendarIdentifier) { calendar in
        Toggle(
          calendar.title,
          isOn: Binding(
            get: {
              controller.organization.consent.selectedCalendars.contains(
                calendar.calendarIdentifier)
            },
            set: { value in
              controller.updateOrganization { o in
                if value {
                  o.consent.selectedCalendars.append(calendar.calendarIdentifier)
                } else {
                  o.consent.selectedCalendars.removeAll { $0 == calendar.calendarIdentifier }
                }
              }
              controller.configureContext()
            }))
      }
    }
    MoltCard(title: "Your data and creator tools") {
      HStack {
        Button("Export pet") { controller.export("pet") }
        Button("Import pet") { controller.importPet() }
        Button("Export organization") { controller.export("organization") }
        Button("Restore previous pet save") { controller.restoreBackup() }
      }
      HStack {
        Button("Import species…") { controller.importDefinition() }
        Button("Export species") { controller.export("species") }
        Button("Open data folder") { NSWorkspace.shared.open(controller.store.directory) }
      }
      DefinitionEditor(controller: controller)
      Text(
        "Pet snapshots and utility records are separate. Raw computer readings and calendar events are not included in pet exports."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  func pref<T>(_ key: WritableKeyPath<PetPreferences, T>) -> Binding<T> {
    Binding(
      get: { controller.companion.preferences[keyPath: key] },
      set: { value in controller.changeCompanion { $0.preferences[keyPath: key] = value } })
  }
  func companionString(_ key: WritableKeyPath<CompanionState, String>) -> Binding<String> {
    Binding(
      get: { controller.companion[keyPath: key] },
      set: { value in
        controller.changeCompanion {
          $0[keyPath: key] = String(value.prefix(key == \.profile ? 500 : 40))
        }
      })
  }
}
struct ActivityDashboard: View {
  @ObservedObject var controller: PetController
  @ObservedObject var contexts: ContextAdapters
  var body: some View {
    MoltCard(title: "How your Mac is feeling") {
      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16
      ) {
        ForEach(
          [
            "batteryLevel", "isCharging", "cpuLoad", "memoryPressure", "diskFreeRatio",
            "thermalState", "uptimeHours",
          ], id: \.self
        ) { key in
          VStack(alignment: .leading, spacing: 4) {
            Text(label(key)).font(.caption).foregroundStyle(.secondary)
            Text(reading(key)).font(MoltTheme.display(19))
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Text(
        "Sampled about once a minute. Missing readings are unavailable, not zero. Raw readings stay in memory."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "Optional app awareness") {
      Toggle(
        "Estimate time in the frontmost app",
        isOn: Binding(
          get: { controller.organization.consent.tracking },
          set: { value in
            controller.updateOrganization { $0.consent.tracking = value }
            controller.configureContext()
          }))
      Text(contexts.currentApp).font(.headline)
      Text(
        "App names and estimated intervals only. No keystrokes, window titles, clipboard, browser history, or document contents. Private browser windows cannot be detected. Exclude the browser to avoid recording it."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Button(controller.organization.consent.paused ? "Resume tracking" : "Pause tracking") {
          controller.updateOrganization { $0.consent.paused.toggle() }
          controller.configureContext()
        }
        Button("Forget activity history") { controller.confirmForgetActivity() }
      }
      TextField(
        "Excluded bundle IDs, separated by commas",
        text: Binding(
          get: { controller.organization.consent.excludedApps },
          set: { value in
            controller.updateOrganization { o in
              o.consent.excludedApps = value
              let ids = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
              o.intervals.removeAll { ids.contains($0.app) }
            }
            controller.configureContext()
          }))
      Text(
        "Tracking pauses on observed sleep and session changes. Intervals are estimates, not a measure of productivity, and idle time may remain included."
      ).font(.caption).foregroundStyle(.secondary)
      ForEach(totals, id: \.0) { app, minutes in
        HStack {
          Text(app)
          Spacer()
          Text("\(Int(minutes)) min").monospacedDigit()
          Picker(
            "Category",
            selection: Binding(
              get: { controller.organization.consent.categories[app] ?? "uncategorized" },
              set: { category in
                controller.updateOrganization { $0.consent.categories[app] = category }
                controller.configureContext()
              })
          ) {
            ForEach(
              ["uncategorized", "work", "creativity", "communication", "leisure"], id: \.self
            ) { Text($0.capitalized) }
          }.frame(width: 170)
        }
      }
      Text(
        "Raw intervals are retained for seven days. Turning tracking off stops collection; Forget removes only app history."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "Recorded focus") {
      ForEach(controller.organization.sessions.sorted { $0.started > $1.started }.prefix(15)) { s in
        HStack {
          Text(s.started.formatted(date: .abbreviated, time: .shortened))
          Spacer()
          Text("\(Int(s.elapsed / 60)) min")
          Text(s.finished == nil ? "Open" : "Finished").foregroundStyle(.secondary)
        }
      }
    }
  }
  var totals: [(String, Double)] {
    Dictionary(grouping: controller.organization.intervals, by: \.app).map {
      ($0.key, $0.value.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
    }.sorted { $0.1 > $1.1 }
  }
  func label(_ key: String) -> String {
    [
      "batteryLevel": "Battery", "isCharging": "Charging", "cpuLoad": "CPU load",
      "memoryPressure": "Memory pressure", "diskFreeRatio": "Disk space free",
      "thermalState": "Thermal state", "uptimeHours": "Uptime",
    ][key] ?? key
  }
  func reading(_ key: String) -> String {
    guard controller.healthEnabled, let value = controller.health.values[key] else {
      return "Unavailable"
    }
    if key == "thermalState" {
      return ["Nominal", "Fair", "Serious", "Critical"][min(3, max(0, Int(value)))]
    }
    if key == "isCharging" { return value > 0 ? "Yes" : "No" }
    if key == "uptimeHours" { return "\(Int(value)) hours" }
    return "\(Int(value * 100))%"
  }
}
extension PetController {
  func confirmForgetActivity() {
    let alert = NSAlert()
    alert.messageText = "Forget recorded app activity?"
    alert.informativeText =
      "This removes app-time intervals only. Your pet, tasks, notes, and focus sessions are kept."
    alert.addButton(withTitle: "Forget activity")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      updateOrganization { $0.intervals = [] }
      configureContext()
    }
  }
}
struct DefinitionEditor: View {
  @ObservedObject var controller: PetController
  @State private var editing = false
  @State private var draft = ""
  @State private var result = ""
  var body: some View {
    DisclosureGroup("Species editor and validation sandbox", isExpanded: $editing) {
      Text(
        "Edit data only. Validation never changes your active pet. Export a validated file, then import it to start a separate companion."
      ).font(.caption)
      if let d = draftDefinition {
        TextField(
          "Species name",
          text: Binding(get: { d.name }, set: { value in editDefinition { $0.name = value } }))
        ForEach(d.statDefinitions, id: \.id) { stat in
          Stepper(
            "\(stat.name): \(stat.decayPerHour, specifier: "%.1f") decay per hour",
            value: Binding(
              get: { stat.decayPerHour },
              set: { value in
                editDefinition { d in
                  if let i = d.statDefinitions.firstIndex(where: { $0.id == stat.id }) {
                    d.statDefinitions[i].decayPerHour = value
                  }
                }
              }), in: 0...20, step: 0.5)
        }
      }
      TextEditor(text: $draft).font(.system(.caption, design: .monospaced)).frame(height: 230)
      HStack {
        Button("Load current definition") {
          let e = JSONEncoder()
          e.outputFormatting = [.prettyPrinted, .sortedKeys]
          draft = (try? String(data: e.encode(controller.definition), encoding: .utf8)) ?? ""
        }
        Button("Validate and preview") {
          do {
            let d = try JSONDecoder().decode(PetDefinition.self, from: Data(draft.utf8))
            try d.validate()
            var state = PetState(definition: d)
            Simulation.advance(
              &state, definition: d, to: state.lastUpdated.addingTimeInterval(3600))
            result =
              "Valid: \(d.name), \(d.statDefinitions.count) needs, \(d.evolutionTree.count) forms. After one hour: \(state.stats.sorted { $0.key < $1.key }.map { "\($0.key): \(Int($0.value))" }.joined(separator: ", "))"
          } catch { result = error.localizedDescription }
        }
        Button("Save draft…") {
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.json]
          panel.nameFieldStringValue = "species.json"
          if panel.runModal() == .OK, let url = panel.url {
            do {
              let d = try JSONDecoder().decode(PetDefinition.self, from: Data(draft.utf8))
              try d.validate()
              try Data(draft.utf8).write(to: url, options: .atomic)
            } catch { result = error.localizedDescription }
          }
        }
      }
      Text(result).font(.caption).textSelection(.enabled)
    }
  }
  var draftDefinition: PetDefinition? {
    try? JSONDecoder().decode(PetDefinition.self, from: Data(draft.utf8))
  }
  func editDefinition(_ change: (inout PetDefinition) -> Void) {
    guard var d = draftDefinition else { return }
    change(&d)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    draft = (try? String(data: encoder.encode(d), encoding: .utf8)) ?? draft
  }

}
