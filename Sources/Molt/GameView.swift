import MoltCore
import SwiftUI

struct GameView: View {
  @ObservedObject var controller: PetController
  @State private var paused = false
  private let symbols = [
    "leaf.fill", "star.fill", "moon.fill", "sun.max.fill", "drop.fill", "heart.fill", "bolt.fill",
    "cloud.fill",
  ]
  var body: some View {
    VStack(spacing: 20) {
      if let game = controller.game {
        HStack {
          Text(
            game.kind == "memory"
              ? "Memory Meadow" : game.kind == "fetch" ? "Molt Fetch" : "Rhythm Steps"
          ).font(MoltTheme.display(26))
          Spacer()
          Text(game.practice ? "Practice" : "Rewarded").font(.caption).padding(8).background(
            MoltTheme.green.opacity(0.1), in: Capsule())
        }
        Text(
          game.kind == "memory"
            ? "Find the matching pairs. No timer, just curiosity."
            : game.kind == "fetch"
              ? "Guide Molt to the star. Take any route around the stones."
              : "Copy the direction sequence below, at your own pace."
        ).font(.callout).foregroundStyle(.secondary)
        if paused {
          Text("Paused while you’re away.").font(.title2)
          Button("Resume") { paused = false }
        } else if game.won {
          Image(systemName: "sparkles").font(.system(size: 50)).foregroundStyle(MoltTheme.green)
          Text("A lovely little adventure.").font(MoltTheme.display(22))
          Text(
            game.practice
              ? "Practice is always here for you."
              : "Completion recorded. Reopening cannot claim it again.")
          Button("Close game") { controller.tab = "Molt" }
        } else if game.kind == "memory" {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ForEach(game.memory.cards.indices, id: \.self) { index in
              let faceUp =
                game.memory.matched.contains(index) || game.memory.revealed.contains(index)
              Button {
                mutate { $0.memory.choose(index) }
              } label: {
                Image(systemName: faceUp ? symbols[game.memory.cards[index]] : "questionmark").font(
                  .title
                ).frame(maxWidth: .infinity, minHeight: 70).background(
                  faceUp ? MoltTheme.green.opacity(0.18) : Color.primary.opacity(0.08),
                  in: RoundedRectangle(cornerRadius: 10))
              }.buttonStyle(.plain).accessibilityLabel(
                faceUp ? symbols[game.memory.cards[index]] : "Hidden card \(index + 1)")
            }
          }
          Text("\(game.memory.moves) turns").font(.caption).monospacedDigit()
        } else if game.kind == "fetch" {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
            ForEach(0..<25) { cell in
              Image(
                systemName: cell == game.fetch.position
                  ? "leaf.fill"
                  : cell == 24
                    ? "star.fill"
                    : game.fetch.obstacles.contains(cell) ? "mountain.2.fill" : "circle.dotted"
              ).font(.title2).frame(maxWidth: .infinity, minHeight: 42).background(
                Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
          }
          directionButtons { direction in mutate { $0.fetch.move(direction) } }
        } else {
          HStack {
            ForEach(Array(game.rhythm.sequence.enumerated()), id: \.offset) { index, direction in
              Image(systemName: ["arrow.up", "arrow.right", "arrow.down", "arrow.left"][direction])
                .font(.title).foregroundStyle(
                  index < game.rhythm.entered.count ? MoltTheme.green : .secondary)
            }
          }
          directionButtons { direction in mutate { $0.rhythm.choose(direction) } }
          Text("A wrong step simply starts the sequence again.").font(.caption)
        }
        Spacer()
        HStack {
          Button(paused ? "Resume" : "Pause") { paused.toggle() }
          Spacer()
          Button("Save and exit") { controller.tab = "Molt" }
          Button("End round") {
            controller.stopActivity()
            controller.game = nil
            controller.tab = "Molt"
          }
        }
      } else {
        Text("Choose a game from Molt’s dashboard.")
      }
    }.padding(28).frame(width: 530, height: 540).background(MoltTheme.paper).foregroundStyle(
      MoltTheme.ink
    )
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
      paused = true
    }
  }
  private func mutate(_ change: (inout GameSession) -> Void) {
    guard !paused, var game = controller.game else { return }
    change(&game)
    controller.updateGame(game)
  }
  private func directionButtons(_ action: @escaping (Int) -> Void) -> some View {
    HStack {
      ForEach(0..<4) { d in
        Button {
          action(d)
        } label: {
          Image(systemName: ["arrow.up", "arrow.right", "arrow.down", "arrow.left"][d]).frame(
            width: 65, height: 35)
        }.keyboardShortcut(
          [KeyEquivalent.upArrow, .rightArrow, .downArrow, .leftArrow][d], modifiers: []
        ).accessibilityLabel(["Up", "Right", "Down", "Left"][d])
      }
    }
  }
}
