import MoltCore
import SwiftUI

/// Molt waking up, when you open the app after quitting it (and the first time): asleep, then
/// awake, a look left and right, a wave, and the wordmark built pixel by pixel. About four
/// seconds; a click skips it.
struct BootView: View {
  var appearance: Appearance
  var started: Date
  var top: CGFloat
  static let length = 4.6
  var body: some View {
    TimelineView(.animation) { context in
      let t = context.date.timeIntervalSince(started)
      let mood = t < 1.3 ? "sleeping" : t < 1.75 ? "tired" : t < 2.75 ? "idle" : t < 3.55 ? "waving" : "happy"
      let gaze: (Int, Int)? = (1.85..<2.3).contains(t) ? (-1, 0) : (2.3..<2.75).contains(t) ? (1, 0) : t < 2.75 ? nil : (0, 0)
      // Standing up: a little hop as Molt wakes.
      let hop = Self.bump(t, from: 1.3, to: 1.65)
      let slide = Self.ease(t, from: 3.3, to: 3.85)
      let word = Self.ease(t, from: 3.45, to: 4.15)
      ZStack {
        CreatureView(appearance: appearance, mood: mood, followsPointer: false, gaze: gaze)
          .frame(width: 92, height: 85)
          .offset(x: -78 * slide, y: -8 * hop)
        Wordmark(progress: word)
          .offset(x: 62 + 12 * (1 - word))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, top)
    }
    .contentShape(Rectangle())
    .accessibilityElement()
    .accessibilityLabel("Molt is waking up")
  }
  /// 0 before `from`, 1 after `to`, eased in between.
  static func ease(_ t: Double, from: Double, to: Double) -> CGFloat {
    let x = min(1, max(0, (t - from) / (to - from)))
    return CGFloat(x * x * (3 - 2 * x))
  }
  /// Up and back down between `from` and `to`.
  static func bump(_ t: Double, from: Double, to: Double) -> CGFloat {
    guard t > from, t < to else { return 0 }
    return CGFloat(sin((t - from) / (to - from) * .pi))
  }
}

/// "Molt" in the green gradient, appearing pixel by pixel from left to right.
struct Wordmark: View {
  var progress: CGFloat
  var size: CGFloat = 46
  var body: some View {
    Text("Molt").font(.system(size: size, weight: .heavy, design: .rounded))
      .foregroundStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.72, blue: 0.44), Color(red: 0.36, green: 0.8, blue: 0.55), Color(red: 0.5, green: 0.83, blue: 0.9)], startPoint: .leading, endPoint: .trailing))
      .fixedSize()
      .mask(PixelReveal(progress: progress, cell: 4))
      .accessibilityLabel("Molt")
  }
}

/// A mask that fills in square by square, sweeping left to right with a little noise.
struct PixelReveal: View {
  var progress: CGFloat
  var cell: CGFloat
  var body: some View {
    Canvas { context, size in
      let columns = Int(ceil(size.width / cell)), rows = Int(ceil(size.height / cell))
      for x in 0..<columns {
        for y in 0..<rows {
          let noise = CGFloat((x * 73 + y * 151) % 97) / 97
          let threshold = CGFloat(x) / CGFloat(max(1, columns)) * 0.75 + noise * 0.25
          if progress >= 1 || progress > threshold {
            context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)), with: .color(.black))
          }
        }
      }
    }
  }
}
