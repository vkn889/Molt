import AppKit
import MoltCore
import SwiftUI

extension Appearance {
  /// The same look with one wardrobe item on, replacing whatever was in its slot. Only for
  /// drawing: nothing is saved or unlocked.
  func wearing(_ id: String) -> Appearance {
    var copy = self
    let slot = WardrobeItem.find(id)?.slot
    copy.outfit = outfit.filter { WardrobeItem.find($0)?.slot != slot } + [id]
    return copy
  }
}

extension PetController {
  var openFocus: FocusSession? { organization.sessions.first { $0.finished == nil } }
  /// The battery is nearly empty and not charging, and Molt is allowed to notice.
  var lowBattery: Bool {
    let values = health.values
    guard UserDefaults.standard.object(forKey: "notchPetReacts") as? Bool ?? true,
      let level = values["batteryLevel"], values["isCharging"] != 1
    else { return false }
    return level <= 0.15
  }
  /// Seconds left in a focus session (or seconds so far, for one with no end).
  func focusClock(_ session: FocusSession, at date: Date) -> Double {
    let elapsed = session.duration(at: date)
    return session.target > 0 ? max(0, session.target - elapsed) : elapsed
  }
}

/// Focus: drag the ruler to choose a length, and Molt puts on its glasses and works with you.
struct FocusPage: View {
  @ObservedObject var controller: PetController
  @AppStorage("focusMinutes") private var minutes = 25
  var body: some View {
    let session = controller.openFocus
    let today = FocusMath.today(controller.organization.sessions, now: Date())
    HStack(alignment: .center, spacing: 22) {
      ZStack(alignment: .bottom) {
        Ellipse().fill(MoltTheme.body(controller.companion.appearance.palette).opacity(0.16)).frame(width: 92, height: 12)
        CreatureView(
          appearance: controller.companion.appearance.wearing("glasses"),
          mood: session?.lastResumed != nil ? "working" : "idle", followsPointer: session == nil)
          .frame(width: 84, height: 78).padding(.bottom, 4)
      }
      .frame(width: 100)
      VStack(alignment: .leading, spacing: 10) {
        if let session {
          running(session, today: today)
        } else {
          setup(today: today)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private func setup(today: (count: Int, minutes: Int)) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(FocusTile.clock(Double(minutes * 60))).font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
      Text("\(controller.petName) will sit and work with you").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
    }
    FocusRuler(minutes: $minutes, tint: MoltTheme.body(controller.companion.appearance.palette))
    HStack(spacing: 6) {
      ForEach([15, 25, 50], id: \.self) { value in
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { minutes = value } } label: {
          Text("\(value) min").font(.system(size: 11, weight: .semibold)).fixedSize()
            .foregroundStyle(minutes == value ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(minutes == value ? 0.16 : 0.06)))
        }.buttonStyle(.plain)
      }
      Spacer(minLength: 8)
      Text("\(today.count) done today · +\(FocusMath.reward(seconds: Double(minutes * 60))) energy each")
        .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4)).lineLimit(1).fixedSize()
      Button { controller.focus(minutes: minutes) } label: {
        Label("Start", systemImage: "play.fill").font(.system(size: 13.5, weight: .bold)).fixedSize()
          .foregroundStyle(Color(red: 0.04, green: 0.14, blue: 0.09))
          .padding(.horizontal, 18).frame(height: 32)
          .background(Capsule().fill(MoltTheme.body(controller.companion.appearance.palette)))
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.defaultAction)
    }
  }

  @ViewBuilder private func running(_ session: FocusSession, today: (count: Int, minutes: Int)) -> some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let left = controller.focusClock(session, at: context.date)
      let progress = session.target > 0 ? min(1, session.duration(at: context.date) / session.target) : 0
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(FocusTile.clock(left)).font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
          Text(session.lastResumed == nil ? "Paused" : left == 0 && session.target > 0 ? "Done. Nice work." : "\(controller.petName) is working with you")
            .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.1))
            Capsule().fill(MoltTheme.body(controller.companion.appearance.palette)).frame(width: max(6, proxy.size.width * progress))
          }
        }.frame(height: 6)
      }
    }
    HStack(spacing: 6) {
      Button { controller.changeFocus(session.lastResumed == nil ? "resume" : "pause") } label: {
        Label(session.lastResumed == nil ? "Resume" : "Pause", systemImage: session.lastResumed == nil ? "play.fill" : "pause.fill").fixedSize()
      }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
      Button { controller.changeFocus("extend") } label: { Label("5 min", systemImage: "plus").fixedSize() }
        .buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
      Spacer(minLength: 8)
      Text("\(today.count) done today · +\(FocusMath.reward(seconds: session.target > 0 ? session.target : session.duration(at: Date()))) energy")
        .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4)).lineLimit(1).fixedSize()
      Button { controller.changeFocus("stop") } label: { Label("Stop", systemImage: "stop.fill").fixedSize() }
        .buttonStyle(PillButtonStyle(tint: .red.opacity(0.75)))
    }
  }
}

/// A pixel ruler from 5 to 90 minutes: a tick a minute, taller every 15, and a pixel leaf to drag.
struct FocusRuler: View {
  @Binding var minutes: Int
  var tint: Color
  @State private var dragging = false
  private static let leaf = ["..####..", ".######.", "########", "########", ".######.", "...##...", "...##...", "...##..."]
  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let x = width * FocusMath.fraction(for: minutes)
      ZStack(alignment: .topLeading) {
        Canvas { context, size in
          for minute in 0...FocusMath.scale {
            let px = (size.width - 4) * Double(minute) / Double(FocusMath.scale)
            let major = minute % 5 == 0
            let height: CGFloat = major ? 26 : 14
            let on = minute <= minutes
            let color = on ? tint.opacity(0.55 + 0.45 * Double(minute) / Double(max(1, minutes))) : Color.white.opacity(0.18)
            context.fill(Path(CGRect(x: px.rounded(), y: 30 - height, width: 4, height: height)), with: .color(color))
          }
        }
        .frame(height: 30)
        .padding(.top, 10)
        // The handle: a pixel leaf above the chosen minute.
        Canvas { context, _ in
          for (y, row) in Self.leaf.enumerated() {
            for (column, character) in row.enumerated() where character == "#" {
              context.fill(Path(CGRect(x: column * 2, y: y * 2, width: 2, height: 2)), with: .color(y > 4 ? tint.opacity(0.7) : tint))
            }
          }
        }
        .frame(width: 16, height: 16)
        .scaleEffect(dragging ? 1.25 : 1, anchor: .bottom)
        .offset(x: x - 8, y: -6)
        ZStack {
          ForEach([0, 10, 20, 30, 40, 50, 60], id: \.self) { mark in
            Text("\(mark)").font(.system(size: 9, weight: .semibold, design: .rounded))
              .foregroundStyle(Color.white.opacity(mark == (minutes / 10) * 10 ? 0.6 : 0.3))
              .fixedSize()
              .position(x: min(width - 6, max(6, width * FocusMath.fraction(for: mark))), y: 5)
          }
        }
        .frame(width: width, height: 10)
        .offset(y: 46)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            dragging = true
            let next = FocusMath.minutes(at: value.location.x / max(1, width))
            if next != minutes {
              minutes = next
              NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
          }
          .onEnded { _ in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { dragging = false } })
      .animation(.spring(response: 0.22, dampingFraction: 0.85), value: minutes)
    }
    .frame(height: 56)
    .accessibilityElement()
    .accessibilityLabel("Focus length")
    .accessibilityValue("\(minutes) minutes")
    .accessibilityAdjustableAction { direction in
      minutes = min(FocusMath.scale, max(FocusMath.minimum, minutes + (direction == .increment ? 5 : -5)))
    }
  }
}

/// Beside the closed notch during focus: Molt in its glasses, and the time left.
struct FocusWings: View {
  @ObservedObject var controller: PetController
  var notchWidth: CGFloat
  var height: CGFloat
  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: 6) {
        CreatureView(appearance: controller.companion.appearance.wearing("glasses"), mood: "working", followsPointer: false)
          .frame(width: height - 8, height: height - 10)
        Text("Focus").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
      }
      .frame(maxWidth: .infinity)
      Color.clear.frame(width: notchWidth)
      if let session = controller.openFocus {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let left = controller.focusClock(session, at: context.date)
          let progress = session.target > 0 ? min(1, session.duration(at: context.date) / session.target) : 0
          let tint = MoltTheme.body(controller.companion.appearance.palette)
          HStack(spacing: 5) {
            Text(FocusTile.clock(left)).font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
              .foregroundStyle(session.lastResumed == nil ? Color.white.opacity(0.5) : tint)
            ZStack {
              Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.4)
              Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round)).rotationEffect(.degrees(-90))
            }.frame(width: 14, height: 14)
          }
        }
        .frame(maxWidth: .infinity)
      } else {
        Color.clear.frame(maxWidth: .infinity)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(controller.openFocus.map { "Focus, \(Int(controller.focusClock($0, at: Date()) / 60)) minutes left" } ?? "Focus")
  }
}

/// Beside the closed notch when the battery is nearly out: a sleepy Molt and the charge left.
struct BatteryWings: View {
  @ObservedObject var controller: PetController
  var notchWidth: CGFloat
  var height: CGFloat
  var body: some View {
    let level = controller.health.values["batteryLevel"] ?? 0
    HStack(spacing: 0) {
      HStack(spacing: 6) {
        CreatureView(appearance: controller.companion.appearance, mood: "tired", followsPointer: false)
          .frame(width: height - 8, height: height - 10)
        Text("Sleepy…").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
      }
      .frame(maxWidth: .infinity)
      Color.clear.frame(width: notchWidth)
      HStack(spacing: 5) {
        Text("\(Int((level * 100).rounded()))%").font(.system(size: 12.5, weight: .bold).monospacedDigit()).foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
        Image(systemName: "battery.25").font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.8))
      }
      .frame(maxWidth: .infinity)
    }
    .help("\(controller.petName) is getting sleepy. Plug in your Mac.")
    .accessibilityElement()
    .accessibilityLabel("Battery low, \(Int((level * 100).rounded())) percent. \(controller.petName) is getting sleepy.")
  }
}

/// Which of several live activities is showing, under the closed notch; swipe for the others.
struct LiveDots: View {
  var count: Int
  var index: Int
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<min(count, 5), id: \.self) { i in
        Capsule().fill(Color.black.opacity(i == index ? 0.78 : 0.32))
          .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
          .frame(width: i == index ? 14 : 5, height: 5)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
    .accessibilityHidden(true)
  }
}

/// An approval as a pill beside the closed notch: who's asking, and Allow or Deny. Hover over it
/// for the full card with what it wants to do.
struct CompactApproval: View {
  @ObservedObject var agents: AgentController
  var appearance: Appearance
  var notchWidth: CGFloat
  var height: CGFloat
  var body: some View {
    if let item = agents.pending.first {
      let name = AgentKind.find(item.event.agent)?.name ?? "An agent"
      HStack(spacing: 0) {
        HStack(spacing: 7) {
          CreatureView(appearance: appearance, mood: "alert", shell: MoltTheme.agent(item.event.agent), followsPointer: false)
            .frame(width: height - 6, height: height - 8)
          Text("\(name.split(separator: " ").first.map(String.init) ?? name) needs you").font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.orange).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        Color.clear.frame(width: notchWidth)
        HStack(spacing: 6) {
          if item.isQuestion {
            Text("Hover to answer").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
          } else {
            Button("Allow") { agents.allow(item.id) }.buttonStyle(PillButtonStyle(tint: .green)).help("Allow (⌃⌥Y)")
            Button("Deny") { agents.deny(item.id) }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.16))).help("Deny (⌃⌥N)")
          }
        }
        .frame(maxWidth: .infinity)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(name) needs you")
    }
  }
}
