import CoreText
import MoltCore
import SwiftUI

struct MoltTheme {
  static let ink = Color.primary
  static let green = Color.accentColor
  static let paper = Color(
    nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.09, green: 0.075, blue: 0.16, alpha: 1) : NSColor(red: 0.98, green: 0.94, blue: 0.82, alpha: 1)
    })
  static func accent(_ name: String) -> Color {
    switch name {
    case "violet": return .purple
    case "blue": return .blue
    case "amber": return .orange
    case "rose": return .pink
    default: return .mint
    }
  }
  static func display(_ size: CGFloat) -> Font { .custom("Shrikhand-Regular", size: size) }
  static func registerFont() {
    if let url = resource("Fonts/Shrikhand-Regular", extension: "ttf") {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
  static func resource(_ name: String, extension ext: String) -> URL? {
    if Bundle.main.bundleURL.pathExtension == "app", let root = Bundle.main.resourceURL,
      let bundle = Bundle(url: root.appendingPathComponent("Molt_Molt.bundle"))
    {
      return bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
    return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
  }
}
private enum SpriteAtlas {
  static let frames: [NSImage] = load(nil)
  static var cache: [URL: [NSImage]] = [:]
  static func images(_ url: URL?) -> [NSImage] {
    guard let url else { return frames }
    if let cached = cache[url] { return cached }
    let result = load(url)
    cache[url] = result
    return result.isEmpty ? frames : result
  }
  private static func load(_ custom: URL?) -> [NSImage] {
    guard let url = custom ?? MoltTheme.resource("Art/molt-atlas", extension: "png"),
      let image = NSImage(contentsOf: url),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return [] }
    let w = cg.width / 4
    let h = cg.height / 4
    return (0..<16).compactMap { i in
      cg.cropping(to: CGRect(x: (i % 4) * w, y: (i / 4) * h, width: w, height: h)).map {
        NSImage(cgImage: $0, size: NSSize(width: w, height: h))
      }
    }
  }
}
struct CreatureView: View {
  var appearance: Appearance
  var atlasURL: URL? = nil
  var mood: String
  var moving = true
  var intensity = 0.6
  var highContrast = false
  var stage = "seed"
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var visible = true
  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 0.25, paused: !moving || reduceMotion || !visible || intensity == 0)
    ) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      let frame = frame(at: moving && !reduceMotion ? time : 0)
      ZStack {
        if SpriteAtlas.images(atlasURL).indices.contains(frame) {
          Image(nsImage: SpriteAtlas.images(atlasURL)[frame]).resizable().interpolation(.none)
            .scaledToFit()
            .hueRotation(
              .degrees(
                ["sage": 0, "ocean": 80, "sunset": -65, "violet": 160][appearance.palette] ?? 0)
            )
            .scaleEffect(
              x: appearance.body == "wide" ? 1.08 : 1, y: appearance.body == "tall" ? 1.08 : 1
            )
            .shadow(color: highContrast ? .black : .clear, radius: 1)
        } else {
          ZStack {
            Ellipse().fill(MoltTheme.green)
            HStack {
              Circle()
              Circle()
            }.padding(40)
          }.accessibilityLabel("Molt’s resting pose")
        }
        if appearance.accessory != "none" {
          Image(
            systemName: [
              "scarf": "waveform.path", "hat": "graduationcap.fill", "glasses": "eyeglasses",
              "backpack": "backpack.fill", "flower": "leaf.fill", "star": "star.fill",
            ][appearance.accessory] ?? "star.fill"
          )
          .font(.system(size: appearance.accessory == "glasses" ? 36 : 25)).foregroundStyle(
            appearance.accessory == "scarf" ? Color.orange : MoltTheme.ink
          )
          .offset(
            x: appearance.accessory == "backpack" ? 38 : 0,
            y: appearance.accessory == "hat" ? -55 : appearance.accessory == "glasses" ? -12 : 23)
        }
        if appearance.markings == "freckles" {
          Text("·   ·").font(.title).foregroundStyle(.orange).offset(y: 10)
        }
        if stage == "radiant" {
          Image(systemName: "sparkles").foregroundStyle(.yellow).offset(x: 50, y: -40)
        }
      }
      .offset(
        y: moving && !reduceMotion && mood != "sleeping" ? sin(time * 1.6) * 2 * intensity : 0
      )
      .animation(.easeInOut(duration: reduceMotion ? 0 : 0.25), value: frame)
    }.onAppear { visible = true }.onDisappear { visible = false }
      .accessibilityElement(children: .ignore).accessibilityLabel(
        "Fin-eared Molt creature, \(mood)")
  }
  private func frame(at time: Double) -> Int {
    switch mood {
    case "sleeping", "sleepy": return 8
    case "walking": return Int(time * 2) % 2 == 0 ? 4 : 5
    case "eating", "hungry": return 10
    case "drinking": return 11
    case "thinking": return 13
    case "celebrating", "evolving": return 14
    case "sweating": return 15
    case "happy", "playing": return Int(time) % 8 < 2 ? 12 : 0
    case "stretching": return 6
    case "yawning": return 7
    case "waking": return 9
    default:
      let phase = Int(time) % 20
      return phase == 0 ? 1 : phase == 5 ? 2 : phase > 16 ? 3 : 0
    }
  }
}
struct PetView: View {
  @ObservedObject var controller: PetController
  var body: some View {
    VStack(spacing: 0) {
      if controller.companion.preferences.talkativeness != "silent" {
        Text(controller.message).font(.system(size: 11, weight: .medium)).multilineTextAlignment(
          .center
        ).lineLimit(3)
          .padding(9).frame(maxWidth: 215).background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      }
      CreatureView(
        appearance: controller.companion.appearance, atlasURL: controller.atlasURL,
        mood: controller.mood,
        moving: controller.petVisible && !controller.companion.preferences.reducedMotion
          && controller.mood != "sweating",
        intensity: controller.companion.preferences.animationIntensity,
        highContrast: controller.companion.preferences.highContrast, stage: controller.state.stageID
      ).frame(width: 145, height: 145)
      HStack(spacing: 12) {
        ForEach(Array(controller.definition.interactions.prefix(3)), id: \.id) { action in
          Button {
            controller.interact(action)
          } label: {
            Image(systemName: action.symbol).frame(width: 28, height: 26)
          }.buttonStyle(.borderless).disabled(controller.blockReason(action) != nil).help(
            controller.blockReason(action) ?? action.name
          ).accessibilityLabel(action.name)
        }
        Button {
          controller.onBringBack?()
        } label: {
          Image(systemName: "square.grid.2x2").frame(width: 28, height: 26)
        }.buttonStyle(.borderless).help("Open dashboard")
      }.padding(5).background(.regularMaterial, in: Capsule())
    }.padding(8).frame(width: 250, height: 280)
      .scaleEffect(controller.companion.preferences.size)
      .frame(
        width: 250 * controller.companion.preferences.size,
        height: 280 * controller.companion.preferences.size)
  }
}
struct MoltCard<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !title.isEmpty { Text(title).font(MoltTheme.display(18)) }
      content
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
      RetroSurface(radius: 18)
    )
  }
}
