import MoltCore
import SwiftUI

struct MoltTheme {
  static let ink = Color.primary
  static let green = Color.accentColor
  /// The notch is always black so it reads as part of the hardware.
  static let paper = Color.black
  static func accent(_ name: String) -> Color {
    switch name {
    case "violet": return .purple
    case "mint": return .mint
    case "amber": return .orange
    case "rose": return .pink
    default: return .blue
    }
  }
  /// Headings use San Francisco, matching macOS.
  static func display(_ size: CGFloat) -> Font { .system(size: size * 0.85, weight: .semibold) }
  static func resource(_ name: String, extension ext: String) -> URL? {
    if Bundle.main.bundleURL.pathExtension == "app", let root = Bundle.main.resourceURL,
      let bundle = Bundle(url: root.appendingPathComponent("Molt_Molt.bundle"))
    {
      return bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
    return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
  }
  /// Molt's body color for each palette choice.
  static func body(_ palette: String) -> Color {
    switch palette {
    case "ocean": return Color(red: 0.33, green: 0.62, blue: 0.96)
    case "sunset": return Color(red: 0.96, green: 0.68, blue: 0.27)
    case "violet": return Color(red: 0.66, green: 0.52, blue: 0.96)
    default: return Color(red: 0.36, green: 0.80, blue: 0.55)
    }
  }
}

/// Molt, drawn as a small block of pixels: a wide body, two dot eyes, stubby arms, four legs
/// and a leaf sprout. Every pose is a variation of the same 14 by 11 grid, with two rows of headroom for hops.
struct CreatureView: View {
  var appearance: Appearance
  var mood: String
  var moving = true
  var walking = false
  var facingLeft = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.moltReducedMotion) private var moltReduced
  private var still: Bool { reduceMotion || moltReduced || !moving }
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.16, paused: still)) { context in
      let tick = still ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.16)
      Canvas { canvas, size in
        let cell = floor(min(size.width / 14, size.height / 13))
        guard cell > 0 else { return }
        let origin = CGPoint(x: (size.width - cell * 14) / 2, y: (size.height - cell * 13) / 2)
        for pixel in Self.pixels(pose: pose, tick: tick) {
          let rect = CGRect(
            x: origin.x + CGFloat(pixel.x) * cell, y: origin.y + CGFloat(pixel.y + 2) * cell,
            width: cell, height: cell)
          canvas.fill(Path(rect), with: .color(color(pixel.kind)))
        }
      }
      .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
      .overlay(alignment: .topTrailing) {
        if pose == .sleep {
          Text("z").font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.7))
            .offset(y: still ? 0 : CGFloat(-(tick / 4 % 3)))
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Molt, \(mood)")
  }

  enum Pose { case idle, walk, sleep, eat, happy }
  enum Kind { case body, eye, leaf, stem, mouth }
  struct Pixel { var x: Int; var y: Int; var kind: Kind }

  private var pose: Pose {
    if walking { return .walk }
    switch mood {
    case "sleeping", "sleepy": return .sleep
    case "eating", "hungry", "drinking": return .eat
    case "happy", "celebrating", "playing", "evolving": return .happy
    case "walking": return .walk
    default: return .idle
    }
  }
  private func color(_ kind: Kind) -> Color {
    switch kind {
    case .body: return MoltTheme.body(appearance.palette)
    case .eye, .mouth: return Color(white: 0.07)
    case .leaf: return Color(red: 0.49, green: 0.88, blue: 0.42)
    case .stem: return Color(red: 0.2, green: 0.55, blue: 0.3)
    }
  }

  static func pixels(pose: Pose, tick: Int) -> [Pixel] {
    var out: [Pixel] = []
    // Walking bobs by one pixel; sleeping settles one pixel lower; happy hops.
    let lift: Int
    switch pose {
    case .walk: lift = tick % 2 == 0 ? 0 : -1
    case .sleep: lift = 1
    case .happy: lift = [0, -1, -2, -1][tick % 4]
    default: lift = 0
    }
    func add(_ x: Int, _ y: Int, _ kind: Kind = .body) { out.append(Pixel(x: x, y: y + lift, kind: kind)) }
    // Sprout, swaying gently.
    let sway = pose == .sleep ? 0 : (tick / 5 % 2)
    add(7 + sway, 0, .leaf); add(8 + sway, 0, .leaf); add(7, 1, .leaf); add(7, 2, .stem)
    // Body, 10 by 6. Features are painted over it afterwards.
    for y in 3...8 {
      for x in 2...11 where !((x == 2 || x == 11) && (y == 3 || y == 8)) { add(x, y) }
    }
    let blink = pose == .idle && tick % 28 == 0
    switch pose {
    case .sleep: for x in [4, 5, 8, 9] { add(x, 6, .eye) }
    case .happy: add(4, 5, .eye); add(9, 5, .eye)
    default:
      for y in blink ? [6] : [5, 6] { add(4, y, .eye); add(9, y, .eye) }
    }
    if pose == .eat && tick % 4 < 2 { add(6, 7, .mouth); add(7, 7, .mouth) }
    // Arms: resting at the sides, raised when happy.
    let armRow = pose == .happy ? (tick % 2 == 0 ? 3 : 4) : 6
    add(1, armRow); add(12, armRow)
    // Legs reach the ground from wherever the body is; a hop lifts everything,
    // and alternate pairs step while walking.
    for (index, x) in [3, 5, 8, 10].enumerated() {
      let top = 9 + lift, ground = pose == .happy ? 10 + lift : 10
      let raised = pose == .walk && index % 2 == tick % 2
      for y in top...max(top, raised ? ground - 1 : ground) { out.append(Pixel(x: x, y: y, kind: .body)) }
    }
    return out
  }
}

struct MoltCard<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !title.isEmpty {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      }
      content
    }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(
      NotchSurface(radius: 14)
    )
  }
}
