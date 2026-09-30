import AppKit
import MoltCore
import SwiftUI
import UniformTypeIdentifiers

extension PetController {
  /// 0 to 1. Well-cared-for, recently played-with Molt runs around more.
  var liveliness: Double {
    let values = Array(state.stats.values)
    let mean = values.isEmpty ? 50 : values.reduce(0, +) / Double(values.count)
    let recent = recentCare.filter { $0 > Date().addingTimeInterval(-6 * 3600) }.count
    return min(1, max(0, mean / 100 * 0.5 + min(1, Double(recent) / 8) * 0.5))
  }
  var isResting: Bool {
    mood == "sleeping" || (state.stats["energy"] ?? 100) < 20 || companion.preferences.sleeping(at: Date())
  }
}

/// Wandering state for one on-screen Molt. A class so the timeline can advance it without
/// invalidating the view on every step.
final class WalkState {
  var x: CGFloat = 60
  var target: CGFloat = 60
  var pauseUntil = Date()
  var last = Date()
  var walking = false
  var facingLeft = false
  func step(now: Date, width: CGFloat, liveliness: Double, resting: Bool) {
    let dt = min(0.1, now.timeIntervalSince(last))
    last = now
    x = min(max(0, x), max(0, width))
    guard !resting, width > 0 else { walking = false; return }
    if now < pauseUntil { walking = false; return }
    let distance = target - x
    if abs(distance) < 1.5 {
      walking = false
      // Lively Molt barely stops; a neglected one mostly sits still.
      let pause = Double.random(in: 0.4...2.2) * (1.8 - liveliness * 1.5) + (liveliness < 0.2 ? 6 : 0)
      pauseUntil = now.addingTimeInterval(pause)
      let reach = width * CGFloat(0.25 + liveliness * 0.75)
      target = min(width, max(0, x + CGFloat.random(in: -reach...reach)))
      return
    }
    walking = true
    facingLeft = distance < 0
    let speed = CGFloat(16 + liveliness * 70)
    x += (distance < 0 ? -1 : 1) * min(abs(distance), speed * CGFloat(dt))
  }
}

/// The strip along the bottom of Home where Molt scurries about, or sleeps.
struct PetLane: View {
  @ObservedObject var controller: PetController
  @State private var walk = WalkState()
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    GeometryReader { proxy in
      let size = CGSize(width: 42, height: 39)
      TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced)) { context in
        let resting = controller.isResting
        let _ = walk.step(now: context.date, width: proxy.size.width - size.width, liveliness: controller.liveliness, resting: resting)
        CreatureView(
          appearance: controller.companion.appearance, mood: resting ? "sleeping" : controller.mood,
          moving: !reduced, walking: walk.walking, facingLeft: walk.facingLeft
        )
        .frame(width: size.width, height: size.height)
        .position(x: walk.x + size.width / 2, y: proxy.size.height - size.height / 2)
        .onTapGesture { controller.tab = "Play" }
        .help("Play with \(controller.petName)")
      }
    }
  }
}

// MARK: Play

struct PlayItem: Identifiable {
  var id: String
  var title: String
  var symbol: String
  var tint: Color
  static let all: [PlayItem] = [
    PlayItem(id: "feed", title: "Meal", symbol: "fork.knife", tint: .orange),
    PlayItem(id: "snack", title: "Snack", symbol: "carrot.fill", tint: Color(red: 1, green: 0.6, blue: 0.2)),
    PlayItem(id: "water", title: "Water", symbol: "drop.fill", tint: .cyan),
    PlayItem(id: "play", title: "Ball", symbol: "tennisball.fill", tint: .yellow),
    PlayItem(id: "rest", title: "Nap", symbol: "bed.double.fill", tint: .indigo),
    PlayItem(id: "groom", title: "Brush", symbol: "comb.fill", tint: .pink),
    PlayItem(id: "pet", title: "Pat", symbol: "hand.raised.fill", tint: Color(red: 0.95, green: 0.8, blue: 0.6)),
    PlayItem(id: "story", title: "Story", symbol: "book.fill", tint: .brown),
  ]
}

/// A small tamagotchi: drag something from the tray onto Molt, or click it.
struct PlayView: View {
  @ObservedObject var controller: PetController
  @State private var walk = WalkState()
  @State private var targeted = false
  @State private var reaction: PlayItem?
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    HStack(spacing: 14) {
      playground
      tray.frame(width: 236)
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
  }

  private var playground: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white.opacity(targeted ? 0.1 : 0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.07), lineWidth: targeted ? 1.5 : 0.5))
      GeometryReader { proxy in
        let size = CGSize(width: 70, height: 65)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced)) { context in
          let resting = controller.isResting && reaction == nil
          let _ = walk.step(now: context.date, width: proxy.size.width - size.width - 24, liveliness: controller.liveliness, resting: resting || reaction != nil)
          CreatureView(
            appearance: controller.companion.appearance, mood: resting ? "sleeping" : controller.mood,
            moving: !reduced, walking: walk.walking, facingLeft: walk.facingLeft
          )
          .frame(width: size.width, height: size.height)
          .overlay(alignment: .top) {
            if let reaction {
              Image(systemName: reaction.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(reaction.tint)
                .offset(y: -16).transition(.scale.combined(with: .opacity))
            }
          }
          .position(x: 12 + walk.x + size.width / 2, y: proxy.size.height - size.height / 2 - 8)
        }
      }
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 6) {
          Text(controller.petName).font(.system(size: 13, weight: .semibold))
          Text("Level \(controller.companion.experience / 100 + 1)").font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 10) {
          stat("Food", "hunger", .orange)
          stat("Energy", "energy", .yellow)
          stat("Love", "affection", .pink)
        }
        Text(controller.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      }.padding(12)
    }
    .contentShape(RoundedRectangle(cornerRadius: 16))
    .onDrop(of: [UTType.plainText], isTargeted: $targeted) { providers in
      guard let provider = providers.first else { return false }
      _ = provider.loadObject(ofClass: NSString.self) { value, _ in
        guard let text = value as? String, text.hasPrefix("molt:") else { return }
        let id = String(text.dropFirst(5))
        Task { @MainActor in give(id) }
      }
      return true
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Play area. Drop an item on \(controller.petName).")
  }

  private var tray: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 8), count: 4), spacing: 8) {
        ForEach(PlayItem.all) { item in
          let action = controller.definition.interactions.first { $0.id == item.id }
          let blocked = action.map { controller.blockReason($0, at: context.date) != nil } ?? true
          VStack(spacing: 3) {
            Image(systemName: item.symbol).font(.system(size: 18, weight: .medium))
              .foregroundStyle(item.tint)
            Text(blocked ? wait(action, context.date) : item.title)
              .font(.system(size: 9, weight: .medium).monospacedDigit())
              .foregroundStyle(Color.white.opacity(blocked ? 0.4 : 0.7))
          }
          .frame(width: 52, height: 52)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
          .opacity(blocked ? 0.45 : 1)
          .contentShape(RoundedRectangle(cornerRadius: 12))
          .onDrag { NSItemProvider(object: "molt:\(item.id)" as NSString) }
          .onTapGesture { give(item.id) }
          .help(action.flatMap { controller.blockReason($0, at: context.date) } ?? "Drag onto \(controller.petName), or click")
          .accessibilityElement().accessibilityLabel(item.title).accessibilityAddTraits(.isButton)
          .accessibilityAction { give(item.id) }
        }
      }
      .frame(maxHeight: .infinity)
    }
  }

  private func stat(_ title: String, _ key: String, _ tint: Color) -> some View {
    let value = controller.state.stats[key] ?? 0
    return VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.12))
          Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, value / 100)))
        }
      }.frame(width: 56, height: 4)
    }
    .accessibilityElement().accessibilityLabel("\(title) \(Int(value)) percent")
  }
  private func wait(_ action: Interaction?, _ date: Date) -> String {
    guard let action else { return "" }
    let label = controller.cooldownLabel(action, at: date)
    return label.replacingOccurrences(of: " wait", with: "")
  }
  private func give(_ id: String) {
    guard let action = controller.definition.interactions.first(where: { $0.id == id }),
      let item = PlayItem.all.first(where: { $0.id == id })
    else { return }
    if let reason = controller.blockReason(action) {
      controller.message = reason
      return
    }
    controller.interact(action)
    withAnimation(reduced ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { reaction = item }
    Task {
      try? await Task.sleep(nanoseconds: 2_200_000_000)
      withAnimation(reduced ? nil : .easeOut(duration: 0.3)) { reaction = nil }
      if controller.mood != "sleeping" || id != "rest" { controller.mood = id == "rest" ? "sleeping" : "idle" }
    }
  }
}
