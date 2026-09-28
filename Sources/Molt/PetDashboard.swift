import MoltCore
import SwiftUI

struct PetDashboard: View {
  @ObservedObject var controller: PetController
  @State private var easy = true
  @State private var practice = true
  @State private var lesson = "sit"
  @State private var location = "Circuit garden"
  var body: some View {
    HStack(alignment: .top) {
      MoltCard(title: "Feeling at home") {
        ForEach(controller.definition.statDefinitions, id: \.id) { stat in
          HStack {
            Text(stat.id == "hunger" ? "Nourishment" : stat.name)
            Spacer()
            Text("\(Int(controller.state.stats[stat.id] ?? 0))").monospacedDigit().foregroundStyle(
              .secondary)
          }.font(.callout)
          ProgressView(value: controller.state.stats[stat.id] ?? 0, total: 100).tint(
            MoltTheme.green)
        }
        Text("Care average: \(Int(controller.score)) / 100").font(.caption).foregroundStyle(
          .secondary)
      }
      MoltCard(title: "Getting to know you") {
        Text(
          "\(controller.companion.familiarity) familiarity · \(controller.companion.experience) experience"
        ).font(.callout)
        ForEach(controller.companion.traits.keys.sorted(), id: \.self) { key in
          HStack {
            Text(key.capitalized).font(.caption)
            ProgressView(value: controller.companion.traits[key] ?? 0.5).tint(MoltTheme.green)
          }
        }
        Text("Shaped by spaced care and exploration. Missed days never erase skills or keepsakes.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    if let active = controller.companion.active {
      MoltCard(title: active.title) {
        Text(
          active.kind.hasPrefix("game") || active.kind.hasPrefix("lesson")
            ? "Waiting for your game. Your tools remain available."
            : "Returns at \(active.end.formatted(date: .omitted, time: .shortened))")
        HStack {
          if controller.companion.game != nil { Button("Resume game") { controller.resumeGame() } }
          Button("Stop activity, no completion reward") { controller.stopActivity() }
        }
      }
    }
    MoltCard(title: "Small acts of care") {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], spacing: 12) {
          ForEach(controller.definition.interactions, id: \.id) { action in
            VStack(alignment: .leading, spacing: 6) {
              Button {
                controller.interact(action)
              } label: {
                Label(action.name, systemImage: action.symbol).frame(
                  maxWidth: .infinity, alignment: .leading)
              }.disabled(controller.blockReason(action, at: context.date) != nil)
              Text(controller.cooldownLabel(action, at: context.date)).font(.caption)
                .monospacedDigit().foregroundStyle(.secondary)
              if let reason = controller.blockReason(action, at: context.date) {
                Text(reason).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(
                  horizontal: false, vertical: true)
              }
            }.padding(10).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
              .background(MoltTheme.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
          }
        }
      }
    }
    MoltCard(title: "A playful pause") {
      HStack {
        Toggle("Practice, no rewards or cooldown", isOn: $practice)
        Toggle("Gentle difficulty", isOn: $easy)
      }
      HStack {
        gameButton("Memory Meadow", kind: "memory", icon: "square.grid.3x3")
        gameButton(
          "Molt Fetch", kind: "fetch", icon: "point.topleft.down.curvedto.point.bottomright.up")
        gameButton("Rhythm Steps", kind: "rhythm", icon: "arrow.up.arrow.down")
      }
      Text(
        "Every game works without sound or timing. Use Tab and Space, number keys, or arrow keys. Difficulty never changes cosmetic rewards."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "The training book") {
      HStack {
        Picker("Trick", selection: $lesson) {
          ForEach(["sit", "spin", "wave", "fetch", "hide", "pose", "carry", "settle"], id: \.self) {
            Text($0.capitalized)
          }
        }
        Button("Begin matching lesson") {
          controller.startGame("lesson:\(lesson)", practice: false, easy: true)
        }
        Button("Perform") {
          controller.mood = lesson == "settle" ? "sitting" : "celebrating"
          controller.message = "\(controller.petName) shows you \(lesson)."
        }.disabled(controller.companion.skills[lesson, default: 0] < 100)
      }
      ProgressView(value: Double(controller.companion.skills[lesson, default: 0]), total: 100).tint(
        MoltTheme.green)
      Text(
        "\(controller.companion.skills[lesson, default: 0]) / 100 mastery. A completed lesson adds 20. Lessons share a 20-minute cooldown."
      ).font(.caption).foregroundStyle(.secondary)
    }
    MoltCard(title: "Out into the little world") {
      Picker("Destination", selection: $location) {
        ForEach(["Circuit garden", "Moonlit cache", "Desktop meadow"], id: \.self) { Text($0) }
      }
      Text(
        "A five-minute fictional adventure. Discover a keepsake and grow curiosity. No files are inspected. Two-hour cooldown after return."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Explore") {
          controller.startActivity(
            kind: "explore:\(location)", title: "Exploring \(location)", seconds: 300,
            group: "exploration", cooldown: 7200, energy: 8)
        }
        Button("Create a keepsake · 2 minutes") {
          controller.startActivity(
            kind: "creative", title: "Making a little garden keepsake", seconds: 120,
            group: "creative", cooldown: 1800, energy: 2)
        }
      }
    }
    MoltCard(title: "The discovery book") {
      if let id = controller.companion.pendingEvolution {
        Text(
          "Ready to grow into \(controller.definition.evolutionTree.first { $0.id == id }?.displayName ?? id). Your history and identity stay with you."
        )
        HStack {
          Button("Welcome this form") { controller.evolve() }
          Text("Or leave it here until you’re ready.").font(.caption)
        }
      }
      ForEach(controller.definition.evolutionTree, id: \.id) { stage in
        HStack {
          Image(
            systemName: controller.companion.unlockedForms.contains(stage.id) ? "leaf.fill" : "leaf"
          )
          Text(stage.displayName)
          Spacer()
          Text("Day \(Int(stage.minAgeDays))+").font(.caption)
          if let score = stage.minCareScore { Text("Care \(Int(score))+").font(.caption) }
        }
      }
    }
    MoltCard(title: "Our little journal") {
      HStack {
        Text("Firsts, discoveries, and time together.").foregroundStyle(.secondary)
        Spacer()
        Button("Export memories") { controller.export("journal") }
      }
      ForEach(controller.companion.memories.reversed().prefix(20)) { memory in
        VStack(alignment: .leading, spacing: 4) {
          Text(memory.text)
          Text(memory.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
            .foregroundStyle(.secondary)
        }
        Divider()
      }
    }
  }
  func gameButton(_ name: String, kind: String, icon: String) -> some View {
    Button {
      controller.startGame(kind, practice: practice, easy: easy)
    } label: {
      Label(name, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 8)
    }
  }
}

struct HomeView: View {
  @ObservedObject var controller: PetController
  @State private var outfitName = "Everyday"
  let items = ["bed", "lamp", "plant", "toy box", "trophy shelf", "flowers"]
  var body: some View {
    MoltCard(title: "A tiny place of our own") {
      ZStack {
        RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.85, green: 0.90, blue: 0.80))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 30) {
          ForEach(0..<6) { slot in
            let item = controller.companion.home.first {
              controller.companion.homePositions[$0] == slot
            }
            VStack {
              Image(systemName: symbol(item ?? "")).font(.system(size: 30))
              Text(item ?? "Empty nook").font(.caption)
            }.frame(height: 60).foregroundStyle(
              item == nil ? MoltTheme.green.opacity(0.2) : MoltTheme.green)
          }
        }.padding(25)
        CreatureView(
          appearance: controller.companion.appearance, atlasURL: controller.atlasURL,
          mood: controller.mood,
          moving: controller.dashboardVisible && !controller.companion.preferences.reducedMotion
            && controller.mood != "sweating"
        ).frame(width: 140, height: 140).offset(y: 20)
      }.frame(height: 230)
      ForEach(items, id: \.self) { item in
        HStack {
          Toggle(
            item.capitalized,
            isOn: Binding(
              get: { controller.companion.home.contains(item) },
              set: { on in
                controller.changeCompanion { c in
                  if on {
                    c.home.append(item)
                    c.homePositions[item] = items.firstIndex(of: item)!
                  } else {
                    c.home.removeAll { $0 == item }
                  }
                }
              }))
          Picker(
            "Place",
            selection: Binding(
              get: { controller.companion.homePositions[item] ?? 0 },
              set: { value in controller.changeCompanion { $0.homePositions[item] = value } })
          ) { ForEach(0..<6) { Text("Nook \($0 + 1)").tag($0) } }.frame(width: 150)
          Button("Visit") {
            controller.mood = item == "bed" ? "sleeping" : item == "plant" ? "drinking" : "happy"
            controller.message = "\(controller.petName) enjoys the \(item)."
          }
        }
      }
    }
    CreativeView(controller: controller)
    MoltCard(title: "The wardrobe") {
      HStack {
        Picker("Palette", selection: binding(\.palette)) {
          ForEach(["sage", "ocean", "sunset", "violet"], id: \.self) { Text($0.capitalized) }
        }
        Picker("Accessory", selection: binding(\.accessory)) {
          ForEach(controller.companion.inventory, id: \.self) { Text($0.capitalized) }
        }
      }
      HStack {
        Picker("Body", selection: binding(\.body)) {
          ForEach(["round", "wide", "tall"], id: \.self) { Text($0.capitalized) }
        }
        Picker("Markings", selection: binding(\.markings)) {
          Text("Plain").tag("plain")
          Text("Freckles").tag("freckles")
        }
      }
      HStack {
        TextField("Outfit name", text: $outfitName)
        Button("Save outfit") {
          controller.changeCompanion { $0.outfits[outfitName] = $0.appearance }
        }
        Button("Shuffle preview") {
          controller.changeCompanion {
            $0.appearance.palette = ["sage", "ocean", "sunset", "violet"].randomElement()!
            $0.appearance.accessory = $0.inventory.randomElement()!
          }
        }
      }
      ForEach(controller.companion.outfits.keys.sorted(), id: \.self) { name in
        Button("Wear \(name)") { controller.changeCompanion { $0.appearance = $0.outfits[name]! } }
      }
      Text(
        "Glasses: 20 XP · Hat: 60 XP · Star: 120 XP · Backpack: exploration · Flower: creative activity. No random purchases."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Export outfit") { controller.export("outfit") }
        Button("Import outfit") { controller.importOutfit() }
        Button("Save portrait…") { controller.savePortrait() }
      }
    }
  }
  func binding(_ key: WritableKeyPath<Appearance, String>) -> Binding<String> {
    Binding(
      get: { controller.companion.appearance[keyPath: key] },
      set: { value in controller.changeCompanion { $0.appearance[keyPath: key] = value } })
  }
  func symbol(_ item: String) -> String {
    [
      "bed": "bed.double.fill", "lamp": "lamp.desk.fill", "plant": "leaf.fill",
      "toy box": "shippingbox.fill", "trophy shelf": "trophy.fill", "flowers": "camera.macro",
    ][item] ?? "plus"
  }
}
extension PetController {
  func savePortrait() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "\(petName)-portrait.png"
    panel.message = "Save a portrait of your companion only. No desktop screenshot is captured."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let renderer = ImageRenderer(
      content: CreatureView(
        appearance: companion.appearance, atlasURL: atlasURL, mood: mood, moving: false,
        stage: state.stageID
      ).frame(width: 512, height: 512))
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:])
    else {
      error = "Could not render the portrait."
      return
    }
    do { try data.write(to: url, options: .atomic) } catch {
      self.error = error.localizedDescription
    }
  }
}
