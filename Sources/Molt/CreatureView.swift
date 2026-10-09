import AppKit
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
  /// The color an agent paints Molt's shell while it works.
  static func agent(_ id: String) -> Color {
    Color(hue: AgentKind.find(id)?.hue ?? 0.06, saturation: 0.5, brightness: 0.96)
  }
}

extension Color {
  init(rgb: UInt32) {
    self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
  }
}

/// Molt, drawn as a small block of pixels: a wide body, two dot eyes, stubby arms, four legs
/// and a leaf sprout. Every pose is a variation of the same 14 by 11 grid, with two rows of
/// headroom. The pixels stay crisp; the motion between them is smooth: Molt breathes, squashes
/// when it lands, follows your pointer with its eyes, blinks at its own pace and gives off little
/// pixel sparkles, hearts and z's.
struct CreatureView: View {
  var appearance: Appearance
  var mood: String
  var moving = true
  var walking = false
  var facingLeft = false
  /// While an agent works, Molt's shell takes on that agent's color.
  var shell: Color? = nil
  /// The last time Molt was clicked or given something; it squishes and blushes.
  var poked: Date? = nil
  var followsPointer = true
  /// A fixed time for rendering frames offline, such as for videos.
  var clock: Double? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.moltReducedMotion) private var moltReduced
  @State private var anchor = WindowAnchor()
  private var still: Bool { clock == nil && (reduceMotion || moltReduced || !moving) }

  var body: some View {
    GeometryReader { proxy in
      TimelineView(.animation(minimumInterval: 1 / 30, paused: still || clock != nil)) { context in
        let t = clock ?? (still ? 0 : context.date.timeIntervalSinceReferenceDate)
        let poke = clock.map { _ in poked.map { $0.timeIntervalSinceReferenceDate } }.flatMap { $0 }.map { t - $0 }
          ?? poked.map { context.date.timeIntervalSince($0) }.flatMap { $0 >= 0 && $0 < 1.4 ? $0 : nil }
        let state = frameState(t: t, poke: poke, look: still ? (0, 0) : look(proxy.frame(in: .global), t: t))
        Canvas { canvas, size in draw(state, in: &canvas, size: size) }
          .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
          .frame(width: proxy.size.width, height: proxy.size.height)
          .overlay {
            // Particles drift outside Molt's frame without changing its size.
            if !still {
              Canvas { canvas, size in particles(state, in: &canvas, size: size, base: proxy.size) }
                .frame(width: proxy.size.width * 2.2, height: proxy.size.height * 2.2)
                .allowsHitTesting(false)
            }
          }
      }
    }
    .background(WindowReader(anchor: anchor))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Molt, \(mood)")
  }

  // MARK: Poses

  enum Pose { case idle, walk, sleep, eat, happy, celebrate, love, work, alert, worried, tired, wave }
  enum Kind: Equatable { case body, eye, leaf, stem, mouth, blush, paint(UInt32) }
  struct Pixel { var x: Int; var y: Int; var kind: Kind }

  private var pose: Pose {
    if walking { return .walk }
    switch mood {
    case "sleeping": return .sleep
    case "sleepy", "tired": return .tired
    case "eating", "hungry", "drinking": return .eat
    case "happy", "playing", "evolving": return .happy
    case "celebrating", "done": return .celebrate
    case "love": return .love
    case "working", "thinking": return .work
    case "alert": return .alert
    case "worried", "sweating", "failed": return .worried
    case "waving": return .wave
    case "walking": return .walk
    default: return .idle
    }
  }

  /// Everything that changes from frame to frame.
  struct FrameState {
    var pose: Pose
    var t: Double
    var tick: Int
    var blink: Bool
    var look: (x: Int, y: Int)
    var lift: CGFloat
    var squash: CGSize
    var sway: CGFloat
    var blush: Bool
    var poke: Double?
  }

  private func frameState(t: Double, poke: Double?, look: (Int, Int)) -> FrameState {
    let pose = self.pose
    var lift: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, sway: CGFloat = 0
    func hop(period: Double, height: CGFloat) {
      let p = t.truncatingRemainder(dividingBy: period) / period
      let h = CGFloat(sin(p * .pi))
      lift = -h * height
      if p < 0.1 || p > 0.9 { sx = 1.1; sy = 0.86 } else { sx = 1 - 0.04 * h; sy = 1 + 0.07 * h }
    }
    let breathe = CGFloat(sin(t * 2 * .pi / 2.8))
    switch pose {
    case .idle, .eat, .wave: sy = 1 + 0.035 * breathe; sx = 1 - 0.02 * breathe
    case .walk:
      lift = -CGFloat(abs(sin(t * .pi * 4))) * 0.6
      sy = 1 + 0.03 * CGFloat(cos(t * .pi * 8))
    case .happy: hop(period: 0.62, height: 2.2)
    case .celebrate: hop(period: 0.5, height: 3)
    case .love: sy = 1 + 0.05 * CGFloat(sin(t * 5)); sx = 1 - 0.03 * CGFloat(sin(t * 5)); sway = CGFloat(sin(t * 2.4)) * 0.35
    case .alert:
      let p = t.truncatingRemainder(dividingBy: 1.6)
      if p < 0.36 { let h = CGFloat(sin(p / 0.36 * .pi)); lift = -h * 1.6; sy = 1 + 0.06 * h } else if p < 0.44 { sx = 1.08; sy = 0.9 }
    case .worried: sway = CGFloat(sin(t * 19)) * 0.22; sy = 1 + 0.02 * breathe
    case .tired: sy = 0.95 + 0.02 * CGFloat(sin(t * 1.3)); sx = 1.02
    case .sleep: sy = 1 + 0.05 * CGFloat(sin(t * 1.6)); sx = 1 - 0.025 * CGFloat(sin(t * 1.6))
    case .work: lift = -CGFloat(max(0, sin(t * 9))) * 0.15
    }
    if let poke, poke < 0.75 {
      let e = poke / 0.75
      let wave = CGFloat(sin(e * .pi * 3) * (1 - e))
      sy -= 0.24 * wave
      sx += 0.18 * wave
    }
    // Blinks come at an uneven pace, like a living thing's.
    let cycle = floor(t / 3.1)
    let period = 3.1, offset = Self.random(Int(cycle), 7) * 2.4
    let blink = (pose == .idle || pose == .walk || pose == .work || pose == .wave || pose == .alert)
      && abs(t - cycle * period - offset) < 0.09
    let tick = Int(t / 0.16)
    let blushing = [.happy, .celebrate, .love].contains(pose) || (poke ?? 9) < 1.2
    return FrameState(
      pose: pose, t: t, tick: tick, blink: blink, look: look, lift: lift, squash: CGSize(width: sx, height: sy),
      sway: sway, blush: blushing, poke: poke)
  }

  /// Where the eyes point: toward the pointer when it's close, otherwise a glance around now and then.
  private func look(_ frame: CGRect, t: Double) -> (Int, Int) {
    if [.sleep, .tired, .celebrate, .love, .happy].contains(pose) { return (0, 0) }
    if pose == .work { return (0, 1) }
    if followsPointer, let window = anchor.window {
      let center = CGPoint(x: window.frame.minX + frame.midX, y: window.frame.maxY - frame.midY)
      let mouse = NSEvent.mouseLocation
      var dx = mouse.x - center.x
      let dy = mouse.y - center.y
      if facingLeft { dx = -dx }
      if hypot(dx, dy) < 420 {
        return (abs(dx) < frame.width * 0.4 ? 0 : dx > 0 ? 1 : -1, dy > frame.height * 0.6 ? -1 : dy < -frame.height * 0.6 ? 1 : 0)
      }
    }
    let phase = t.truncatingRemainder(dividingBy: 7)
    if phase > 5.2 && phase < 5.9 { return (-1, 0) }
    if phase > 5.9 && phase < 6.6 { return (1, 0) }
    return (0, 0)
  }

  // MARK: Drawing

  private func draw(_ s: FrameState, in canvas: inout GraphicsContext, size: CGSize) {
    let cell = floor(min(size.width / 14, size.height / 13))
    guard cell > 0 else { return }
    let origin = CGPoint(x: (size.width - cell * 14) / 2, y: (size.height - cell * 13) / 2)
    let ground = origin.y + 13 * cell
    // A soft shadow that shrinks as Molt leaves the ground.
    let height = max(0, -s.lift)
    let shadowWidth = cell * (9 - height * 1.2)
    canvas.fill(
      Path(ellipseIn: CGRect(x: size.width / 2 - shadowWidth / 2, y: ground - cell * 0.55, width: shadowWidth, height: cell * 0.7)),
      with: .color(.black.opacity(0.32 - Double(height) * 0.04)))
    // Squash and stretch around the feet.
    var body = canvas
    body.translateBy(x: size.width / 2 + s.sway * cell, y: ground + s.lift * cell)
    body.scaleBy(x: s.squash.width, y: s.squash.height)
    body.translateBy(x: -size.width / 2, y: -ground)
    for pixel in Self.sprite(s, outfit: appearance.outfit) {
      let rect = CGRect(
        x: origin.x + CGFloat(pixel.x) * cell, y: origin.y + CGFloat(pixel.y + 2) * cell, width: cell + 0.3, height: cell + 0.3)
      body.fill(Path(rect), with: .color(color(pixel.kind)))
    }
  }

  private func color(_ kind: Kind) -> Color {
    switch kind {
    case .body:
      guard let shell else { return MoltTheme.body(appearance.palette) }
      // Molt molts into the working agent's color, keeping a hint of its own.
      return Self.mix(MoltTheme.body(appearance.palette), shell, 0.92)
    case .eye, .mouth: return Color(white: 0.07)
    case .leaf: return Color(red: 0.49, green: 0.88, blue: 0.42)
    case .stem: return Color(red: 0.2, green: 0.55, blue: 0.3)
    case .blush: return Color(red: 1, green: 0.55, blue: 0.62).opacity(0.85)
    case .paint(let rgb): return Color(rgb: rgb)
    }
  }
  static func mix(_ a: Color, _ b: Color, _ amount: Double) -> Color {
    let x = NSColor(a).usingColorSpace(.deviceRGB) ?? .gray, y = NSColor(b).usingColorSpace(.deviceRGB) ?? .gray
    return Color(
      red: x.redComponent + (y.redComponent - x.redComponent) * amount,
      green: x.greenComponent + (y.greenComponent - x.greenComponent) * amount,
      blue: x.blueComponent + (y.blueComponent - x.blueComponent) * amount)
  }

  /// The resting pose, for the app and menu bar icons.
  static func pixels(pose: Pose, tick: Int) -> [Pixel] {
    sprite(
      FrameState(pose: pose, t: 0, tick: tick, blink: false, look: (0, 0), lift: 0, squash: CGSize(width: 1, height: 1), sway: 0, blush: false, poke: nil),
      outfit: [])
  }

  static func sprite(_ s: FrameState, outfit: [String]) -> [Pixel] {
    var out: [Pixel] = []
    let pose = s.pose, tick = s.tick
    let sink = pose == .sleep ? 1 : 0
    func add(_ x: Int, _ y: Int, _ kind: Kind = .body) { out.append(Pixel(x: x, y: y + sink, kind: kind)) }
    let hides = outfit.contains { ["hat", "beanie", "hardhat", "pumpkin", "santa"].contains($0) }
    // Behind the body.
    if outfit.contains("cape") {
      let flutter = tick % 4 < 2 ? 0 : 1
      for y in 4...9 { add(1, y, .paint(0xC8323C)); add(12, y, .paint(0xC8323C)) }
      for x in 2...11 where (x + flutter) % 2 == 0 { add(x, 9, .paint(0xA82830)) }
    }
    // Sprout, swaying.
    if !hides {
      let sway = pose == .sleep || pose == .tired ? 0 : (sin(s.t * (pose == .celebrate ? 9 : 2.2)) > 0.25 ? 1 : 0)
      add(7 + sway, 0, .leaf); add(8 + sway, 0, .leaf); add(7, 1, .leaf); add(7, 2, .stem)
    }
    for y in 3...8 {
      for x in 2...11 where !((x == 2 || x == 11) && (y == 3 || y == 8)) { add(x, y) }
    }
    // Eyes.
    let lx = 4 + s.look.x, rx = 9 + s.look.x, ey = 5 + s.look.y
    switch pose {
    case .sleep: for x in [4, 5, 8, 9] { add(x, 6, .eye) }
    case .tired: add(4, 6, .eye); add(9, 6, .eye); add(5, 6, .eye); add(8, 6, .eye)
    case .celebrate, .love:
      // Happy arcs: ^ ^
      add(3, 6, .eye); add(4, 5, .eye); add(5, 6, .eye); add(8, 6, .eye); add(9, 5, .eye); add(10, 6, .eye)
    case .happy: add(4, 5, .eye); add(9, 5, .eye); add(4, 6, .eye); add(9, 6, .eye)
    case .worried:
      add(lx, ey, .eye); add(lx, ey + 1, .eye); add(rx, ey, .eye); add(rx, ey + 1, .eye)
    default:
      if s.blink {
        add(lx, 6, .eye); add(rx, 6, .eye)
      } else {
        add(lx, ey, .eye); add(lx, ey + 1, .eye); add(rx, ey, .eye); add(rx, ey + 1, .eye)
      }
    }
    if s.blush { add(3, 7, .blush); add(10, 7, .blush) }
    // Mouths.
    switch pose {
    case .eat where tick % 4 < 2: add(6, 7, .mouth); add(7, 7, .mouth)
    case .celebrate: add(6, 7, .mouth); add(7, 7, .mouth); add(6, 8, .paint(0xE8606A)); add(7, 8, .paint(0xE8606A))
    case .alert: add(6, 7, .mouth); add(7, 7, .mouth); add(6, 8, .mouth); add(7, 8, .mouth)
    case .worried: add(6, 8, .mouth); add(7, 8, .mouth)
    default: break
    }
    // Arms.
    switch pose {
    case .happy: let row = tick % 2 == 0 ? 3 : 4; add(1, row); add(12, row)
    case .celebrate: let row = tick % 2 == 0 ? 2 : 3; add(1, row); add(12, row); add(1, row + 1); add(12, row + 1)
    case .wave: add(1, 6); add(12, tick % 3 == 0 ? 2 : 3); add(12, 4)
    case .alert: add(1, 4); add(12, 4)
    case .love: add(1, 5); add(12, 5)
    case .work: add(tick % 2 == 0 ? 2 : 1, 7); add(tick % 2 == 0 ? 12 : 11, 7)
    case .tired, .sleep: add(1, 7); add(12, 7)
    default: add(1, 6); add(12, 6)
    }
    // Legs; alternate pairs step while walking.
    for (index, x) in [3, 5, 8, 10].enumerated() {
      let raised = pose == .walk && index % 2 == tick % 2
      add(x, 9)
      if !raised { add(x, 10) }
    }
    // A laptop while working.
    if pose == .work {
      for x in 4...9 { for y in 7...8 { add(x, y, .paint(0xB9BEC6)) } }
      add(6, 7, .paint(0xE6E9EE)); add(7, 7, .paint(0xE6E9EE))
      for x in 3...10 { add(x, 9, .paint(0x8C929B)) }
    }
    out += accessories(outfit, tick: tick, t: s.t).map { Pixel(x: $0.x, y: $0.y + sink, kind: $0.kind) }
    return out
  }

  /// Wardrobe items, painted over the body.
  static func accessories(_ outfit: [String], tick: Int, t: Double) -> [Pixel] {
    var out: [Pixel] = []
    func p(_ x: Int, _ y: Int, _ rgb: UInt32) { out.append(Pixel(x: x, y: y, kind: .paint(rgb))) }
    func row(_ y: Int, _ xs: ClosedRange<Int>, _ rgb: UInt32) { for x in xs { p(x, y, rgb) } }
    for item in outfit {
      switch item {
      case "hat":
        row(2, 3...10, 0x1C1C22); row(-1, 5...8, 0x1C1C22); row(0, 5...8, 0x1C1C22); row(1, 5...8, 0xD8424A)
      case "beanie":
        row(2, 3...10, 0xF2E3C6); row(1, 3...10, 0xE0703A); row(0, 4...9, 0xE0703A); p(6, -1, 0xFFFFFF); p(7, -1, 0xFFFFFF)
        p(5, 1, 0xC85A28); p(8, 1, 0xC85A28)
      case "hardhat":
        row(2, 2...11, 0xF5C518); row(1, 4...9, 0xF5C518); row(0, 5...8, 0xF5C518); p(6, 1, 0xFFE27A)
      case "pumpkin":
        row(2, 3...10, 0xF08A24); row(1, 3...10, 0xF08A24); row(0, 4...9, 0xF08A24); row(-1, 5...8, 0xE57A16)
        p(6, -2, 0x3E8E3E); p(5, 1, 0x3A1D08); p(8, 1, 0x3A1D08); p(6, 2, 0x3A1D08); p(7, 2, 0x3A1D08)
      case "santa":
        row(2, 3...10, 0xFFFFFF); row(1, 4...9, 0xD8323C); row(0, 5...9, 0xD8323C); row(-1, 8...10, 0xD8323C); p(11, -1, 0xFFFFFF)
      case "bunny":
        for y in -2...2 { p(4, y, 0xF4F4F4); p(9, y, 0xF4F4F4) }
        p(4, -1, 0xF7A8B8); p(4, 0, 0xF7A8B8); p(9, -1, 0xF7A8B8); p(9, 0, 0xF7A8B8)
      case "headphones":
        row(1, 3...10, 0x2A2D34); p(2, 2, 0x2A2D34); p(11, 2, 0x2A2D34)
        for y in 4...5 { p(1, y, 0x4F8CFF); p(12, y, 0x4F8CFF) }
      case "halo":
        let bob = sin(t * 2.5) > 0 ? 0 : 1
        row(-2 + bob, 5...9, 0xFFD95A)
      case "flower":
        p(10, 2, 0xFFD23F); p(9, 2, 0xFF7EB6); p(11, 2, 0xFF7EB6); p(10, 1, 0xFF7EB6); p(10, 3, 0xFF7EB6)
      case "star":
        let twinkle: UInt32 = tick % 6 < 3 ? 0xFFE066 : 0xFFF4B8
        p(3, 0, twinkle); p(2, 1, twinkle); p(3, 1, 0xFFFFFF); p(4, 1, twinkle); p(3, 2, twinkle)
      case "glasses":
        row(4, 3...5, 0x22252B); row(4, 8...10, 0x22252B); p(6, 5, 0x22252B); p(7, 5, 0x22252B); p(3, 5, 0x22252B); p(10, 5, 0x22252B)
      case "shades":
        for y in 5...6 { row(y, 3...5, 0x14161A); row(y, 8...10, 0x14161A) }
        p(6, 5, 0x14161A); p(7, 5, 0x14161A); p(3, 5, 0x5A6170); p(8, 5, 0x5A6170)
      case "scarf":
        row(8, 3...10, 0xD8424A); p(4, 8, 0xF2E3C6); p(8, 8, 0xF2E3C6); p(10, 9, 0xD8424A)
      case "bowtie":
        p(5, 7, 0x3A5BD9); p(5, 8, 0x3A5BD9); p(8, 7, 0x3A5BD9); p(8, 8, 0x3A5BD9); p(6, 8, 0x2A44A8); p(7, 8, 0x2A44A8)
      case "backpack":
        for y in 4...7 { p(13, y, 0x9C6B3C) }
        p(12, 4, 0x7A5028); p(12, 7, 0x7A5028)
      default: break
      }
    }
    return out
  }

  // MARK: Particles

  private enum Effect { case sparkle, heart, z, sweat, bits, crumbs, confetti }

  private func effects(_ s: FrameState) -> [Effect] {
    var list: [Effect] = []
    switch s.pose {
    case .happy: list = [.sparkle]
    case .celebrate: list = [.sparkle, .confetti]
    case .love: list = [.heart]
    case .sleep: list = [.z]
    case .worried: list = [.sweat]
    case .work: list = [.bits]
    case .eat: list = [.crumbs]
    default: break
    }
    if let poke = s.poke, poke < 1.4 { list.append(.heart) }
    return list
  }

  private func particles(_ s: FrameState, in canvas: inout GraphicsContext, size: CGSize, base: CGSize) {
    let cell = floor(min(base.width / 14, base.height / 13))
    guard cell > 0 else { return }
    // The particle canvas is larger than Molt; this is where Molt's grid starts inside it.
    let origin = CGPoint(x: (size.width - cell * 14) / 2, y: (size.height - cell * 13) / 2 + s.lift * cell)
    let unit = max(1, (cell * 0.6).rounded())
    func blit(_ rows: [String], at point: CGPoint, color: Color, opacity: Double) {
      let snapped = CGPoint(x: (point.x / unit).rounded() * unit, y: (point.y / unit).rounded() * unit)
      for (y, line) in rows.enumerated() {
        for (x, char) in line.enumerated() where char == "X" {
          canvas.fill(
            Path(CGRect(x: snapped.x + CGFloat(x) * unit, y: snapped.y + CGFloat(y) * unit, width: unit, height: unit)),
            with: .color(color.opacity(opacity)))
        }
      }
    }
    if s.pose == .alert {
      let bob = CGFloat(sin(s.t * 8)) * unit
      for y in 0..<3 { blit(["X"], at: CGPoint(x: origin.x + 7 * cell, y: origin.y - CGFloat(4 - y) * cell * 0.8 + bob), color: Color(rgb: 0xFFD23F), opacity: 1) }
      blit(["X"], at: CGPoint(x: origin.x + 7 * cell, y: origin.y + 0.4 * cell + bob), color: Color(rgb: 0xFFD23F), opacity: 1)
    }
    for effect in effects(s) {
      let (rate, life): (Double, Double)
      switch effect {
      case .sparkle: (rate, life) = (3.2, 1.1)
      case .confetti: (rate, life) = (9, 1.4)
      case .heart: (rate, life) = (2.4, 1.3)
      case .z: (rate, life) = (0.7, 2.6)
      case .sweat: (rate, life) = (0.9, 0.9)
      case .bits: (rate, life) = (4, 1.0)
      case .crumbs: (rate, life) = (3, 0.6)
      }
      let newest = Int(floor(s.t * rate))
      let oldest = Int(floor((s.t - life) * rate))
      guard newest - oldest < 40 else { continue }
      for index in max(oldest, newest - 30)...newest {
        let born = Double(index) / rate
        let age = s.t - born
        guard age >= 0, age < life else { continue }
        let r1 = Self.random(index, effect.hashValue), r2 = Self.random(index, effect.hashValue + 11)
        let progress = age / life
        let fade = min(1, age / 0.12) * (1 - progress * progress)
        var x = origin.x, y = origin.y
        let rows: [String]
        var tint: Color
        switch effect {
        case .sparkle:
          x += CGFloat(1 + r1 * 12) * cell; y += CGFloat(1 + r2 * 4) * cell - CGFloat(progress) * cell * 3
          rows = progress < 0.5 ? [".X.", "XXX", ".X."] : ["X"]
          tint = r2 > 0.5 ? Color(rgb: 0xFFE066) : .white
        case .confetti:
          x += CGFloat(r1 * 18 - 2) * cell + CGFloat(sin(age * 6 + r2 * 6)) * cell * 0.6
          y += -CGFloat(2) * cell + CGFloat(progress * progress) * cell * 10 - CGFloat(1 - progress) * cell * 2
          rows = ["X"]
          tint = [Color(rgb: 0xFF6B6B), Color(rgb: 0x4F8CFF), Color(rgb: 0xFFD23F), Color(rgb: 0x5AD18B), Color(rgb: 0xC77DFF)][Int(r2 * 5) % 5]
        case .heart:
          x += CGFloat(3 + r1 * 7) * cell + CGFloat(sin(age * 4 + r2 * 5)) * cell * 0.7
          y += CGFloat(1) * cell - CGFloat(progress) * cell * 4.5
          rows = [".X.X.", "XXXXX", ".XXX.", "..X.."]
          tint = Color(rgb: r2 > 0.6 ? 0xFF8FB1 : 0xFF5E8A)
        case .z:
          x += CGFloat(10) * cell + CGFloat(progress) * cell * 2.5 + CGFloat(sin(age * 2)) * cell * 0.4
          y += CGFloat(2) * cell - CGFloat(progress) * cell * 4
          rows = progress < 0.5 ? ["XXX", "..X", ".X.", "XXX"] : ["XXXX", "..X.", ".X..", "XXXX"]
          tint = .white
        case .sweat:
          x += CGFloat(r1 > 0.5 ? 11.5 : 1.5) * cell
          y += CGFloat(3) * cell + CGFloat(progress * progress) * cell * 4
          rows = [".X.", "XXX", ".X."]
          tint = Color(rgb: 0x7CC6FF)
        case .bits:
          x += CGFloat(4.5 + r1 * 5) * cell
          y += CGFloat(7) * cell - CGFloat(progress) * cell * 4
          rows = ["X"]
          tint = Color(rgb: r2 > 0.5 ? 0x5AD18B : 0xA9F5C4)
        case .crumbs:
          x += CGFloat(5.5 + r1 * 3) * cell
          y += CGFloat(9) * cell + CGFloat(progress) * cell * 2.5
          rows = ["X"]
          tint = Color(rgb: 0xC8955A)
        }
        blit(rows, at: CGPoint(x: x, y: y), color: tint, opacity: fade)
      }
    }
  }

  /// A stable pseudo-random number in 0..<1 for a particle index.
  static func random(_ index: Int, _ salt: Int) -> Double {
    var value = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ salt &* 40_503))
    value ^= value >> 33
    value = value &* 0xff51afd7ed558ccd
    value ^= value >> 33
    return Double(value % 10_000) / 10_000
  }
}

/// Lets a view find the window it's in, so Molt's eyes can follow the pointer across the screen.
final class WindowAnchor { weak var window: NSWindow? }
struct WindowReader: NSViewRepresentable {
  let anchor: WindowAnchor
  func makeNSView(context: Context) -> NSView {
    let view = AnchorView()
    view.anchor = anchor
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
  final class AnchorView: NSView {
    weak var anchor: WindowAnchor?
    override func viewDidMoveToWindow() { anchor?.window = window }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
