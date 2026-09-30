import AppKit
import EventKit
import MoltCore
import SwiftUI

/// The notch's home: now playing, the week at a glance, and how the Mac is doing.
struct NotchHomeView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var media: NowPlayingController
  var body: some View {
    HStack(alignment: .top, spacing: 22) {
      NowPlayingCard(media: media).frame(width: 290, alignment: .leading)
      WeekCard(controller: controller, contexts: controller.contexts).frame(maxWidth: .infinity, alignment: .leading)
      MacHealthCard(controller: controller).frame(width: 150, alignment: .leading)
    }
    .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

// MARK: Now playing

struct NowPlayingCard: View {
  @ObservedObject var media: NowPlayingController
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack(alignment: .bottomTrailing) {
        Button(action: media.openPlayerApp) { artwork }.buttonStyle(.plain)
          .help(media.player.map { "Open \($0.displayName)" } ?? "Open Music")
        if let icon = media.appIcon {
          Image(nsImage: icon).resizable().interpolation(.high).frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .offset(x: 7, y: 7).accessibilityHidden(true)
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        if let track = media.track {
          Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            .foregroundStyle(.white)
          Text(track.album.isEmpty ? " " : track.album).font(.system(size: 12, weight: .medium)).lineLimit(1)
            .foregroundStyle(Color.white.opacity(0.62)).padding(.top, 2)
          Text(track.artist).font(.system(size: 12)).lineLimit(1)
            .foregroundStyle(Color.white.opacity(0.45))
        } else if media.permissionNeeded {
          Text("Allow music control").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
          Text("Molt needs Automation access to follow Spotify or Apple Music.")
            .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(2).padding(.top, 2)
          Button("Open Settings", action: media.openAutomationSettings).padding(.top, 6)
        } else {
          Text("Not playing").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
          Text("Play something in Spotify or Apple Music.")
            .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(2).padding(.top, 2)
        }
        Spacer(minLength: 6)
        if media.track != nil { ProgressScrubber(media: media).padding(.bottom, 4) }
        transport
      }.frame(height: 100, alignment: .topLeading)
    }
  }
  private var artwork: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
      if let image = media.artwork {
        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
          .transition(.opacity)
      } else {
        Image(systemName: "music.note").font(.system(size: 30, weight: .medium)).foregroundStyle(Color.white.opacity(0.3))
      }
    }
    .frame(width: 100, height: 100)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .scaleEffect(media.isPlaying || reduced ? 1 : 0.94)
    .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: media.isPlaying)
    .animation(reduced ? nil : .easeOut(duration: 0.25), value: media.artwork)
    .accessibilityLabel(media.track.map { "Artwork for \($0.title)" } ?? "No artwork")
  }
  private var transport: some View {
    HStack(spacing: 10) {
      Button(action: media.previous) { Image(systemName: "backward.fill").font(.system(size: 14)) }
        .accessibilityLabel("Previous track").disabled(media.track == nil)
      Button(action: media.playPause) {
        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20))
          .contentTransition(.identity)
      }.buttonStyle(NotchIconButtonStyle(size: 34, prominent: true))
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
      Button(action: media.next) { Image(systemName: "forward.fill").font(.system(size: 14)) }
        .accessibilityLabel("Next track").disabled(media.track == nil)
    }.buttonStyle(NotchIconButtonStyle(size: 30)).padding(.leading, -6)
  }
}

struct ProgressScrubber: View {
  @ObservedObject var media: NowPlayingController
  @State private var dragging: Double?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { context in
      let duration = max(1, media.track?.duration ?? 1)
      let value = dragging ?? media.elapsed(at: context.date)
      HStack(spacing: 8) {
        Text(Self.time(value)).frame(width: 30, alignment: .leading)
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule().fill(Color.white.opacity(0.85)).frame(width: max(4, proxy.size.width * value / duration))
          }
          .frame(height: dragging == nil ? 4 : 6).frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { dragging = min(duration, max(0, Double($0.location.x / proxy.size.width) * duration)) }
              .onEnded { _ in
                if let dragging { media.seek(to: dragging) }
                dragging = nil
              })
        }.frame(height: 10)
        Text("-" + Self.time(max(0, duration - value))).frame(width: 34, alignment: .trailing)
      }
      .font(.system(size: 9, weight: .medium).monospacedDigit())
      .foregroundStyle(Color.white.opacity(0.45))
      .animation(.easeOut(duration: 0.12), value: dragging == nil)
    }
    .accessibilityElement()
    .accessibilityLabel("Playback position")
    .accessibilityValue(Self.time(media.elapsed(at: Date())))
  }
  static func time(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.down))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
  }
}

// MARK: Week

struct WeekCard: View {
  @ObservedObject var controller: PetController
  @ObservedObject var contexts: ContextAdapters
  private var calendar: Calendar { .current }
  var body: some View {
    let today = calendar.startOfDay(for: Date())
    let days = (-2...2).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 0) {
        Text(today, format: .dateTime.month(.abbreviated))
          .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
          .frame(width: 58, alignment: .leading)
        ForEach(days, id: \.self) { day in dayCell(day, today: today) }
      }
      agenda(today: today)
    }
  }
  private func dayCell(_ day: Date, today: Date) -> some View {
    let isToday = day == today
    let past = day < today
    let hasEvents = contexts.events.contains { calendar.isDate($0.startDate, inSameDayAs: day) }
    return VStack(spacing: 3) {
      Text(day, format: .dateTime.weekday(.abbreviated))
        .font(.system(size: 9, weight: .semibold)).textCase(.uppercase)
        .foregroundStyle(isToday ? Color.accentColor : Color.white.opacity(0.35))
      Text(day, format: .dateTime.day(.twoDigits))
        .font(.system(size: 16, weight: isToday ? .bold : .semibold).monospacedDigit())
        .foregroundStyle(isToday ? Color.accentColor : Color.white.opacity(past ? 0.3 : 0.7))
      Circle().fill(hasEvents ? (isToday ? Color.accentColor : Color.white.opacity(0.5)) : .clear)
        .frame(width: 4, height: 4)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (hasEvents ? ", has events" : ""))
  }
  @ViewBuilder private func agenda(today: Date) -> some View {
    let events = contexts.events.filter { calendar.isDate($0.startDate, inSameDayAs: today) && $0.endDate > Date() }
    let tasks = controller.organization.tasks.filter { $0.today && $0.completed == nil }
    if events.isEmpty && tasks.isEmpty {
      Button { controller.tab = "Today" } label: {
        HStack(spacing: 8) {
          Image(systemName: "calendar.badge.checkmark").font(.system(size: 14))
          Text("Nothing for today").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.45))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
      }.buttonStyle(.plain).help("Open Today")
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(events.prefix(2)), id: \.eventIdentifier) { event in
          row(
            color: Color(nsColor: event.calendar?.color ?? .systemBlue), title: event.title ?? "Event",
            detail: event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
        }
        ForEach(Array(tasks.prefix(max(0, 2 - min(2, events.count))))) { task in
          Button {
            controller.updateOrganization { $0.completeTask(task.id, now: Date()) }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
              Text(task.title).font(.system(size: 12)).lineLimit(1).foregroundStyle(Color.white.opacity(0.85))
              Spacer(minLength: 0)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain).help("Mark done")
        }
      }
    }
  }
  private func row(color: Color, title: String, detail: String) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.white)
        Text(detail).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
      }
    }
  }
}

// MARK: Mac health

struct MacHealthCard: View {
  @ObservedObject var controller: PetController
  var body: some View {
    let values = controller.health.values
    VStack(alignment: .leading, spacing: 4) {
      if !controller.healthEnabled {
        Text("Mac health").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        Text("Battery, CPU, memory and storage at a glance.").font(.system(size: 10))
          .foregroundStyle(Color.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
        Button("Turn on") { controller.healthEnabled = true; controller.refreshHealth() }
      } else {
        if let battery = values["batteryLevel"] {
          let charging = values["isCharging"] == 1
          meter(charging ? "battery.100.bolt" : batterySymbol(battery), "Battery", battery,
            label: "\(Int((battery * 100).rounded()))%", warn: charging ? nil : battery < 0.2)
        }
        meter("cpu", "CPU", values["cpuLoad"], label: values["cpuLoad"].map { "\(Int(($0 * 100).rounded()))%" } ?? "…",
          warn: (values["cpuLoad"] ?? 0) > 0.85)
        meter("memorychip", "Memory", values["memoryUsed"],
          label: values["memoryUsed"].map { "\(Int(($0 * 100).rounded()))%" } ?? "…",
          warn: (values["memoryPressure"] ?? 0) >= 0.5)
        if let free = values["diskFreeRatio"] {
          meter("internaldrive", "Storage", 1 - free, label: "\(Int((free * 100).rounded()))% free", warn: free < 0.1)
        }
        let care = controller.score
        meter("heart.fill", controller.petName, care / 100, label: "\(Int(care))", warn: care < 40)
      }
    }
  }
  private func batterySymbol(_ level: Double) -> String {
    level > 0.87 ? "battery.100" : level > 0.62 ? "battery.75" : level > 0.37 ? "battery.50" : level > 0.12 ? "battery.25" : "battery.0"
  }
  private func meter(_ icon: String, _ title: String, _ value: Double?, label: String, warn: Bool?) -> some View {
    let tint: Color = warn == true ? .orange : warn == nil ? .green : Color.white.opacity(0.85)
    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: 9, weight: .semibold)).frame(width: 14)
        Text(title).lineLimit(1)
        Spacer(minLength: 4)
        Text(label).monospacedDigit().foregroundStyle(Color.white.opacity(0.85))
      }
      .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.12))
          Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, value ?? 0)))
        }
      }.frame(height: 3)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(label)")
  }
}

// MARK: Collapsed live activity

/// Shown beside the hardware notch while music plays and Molt is closed.
struct NotchLiveActivity: View {
  @ObservedObject var media: NowPlayingController
  var notchWidth: CGFloat
  var height: CGFloat
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    HStack(spacing: 0) {
      Group {
        if let image = media.artwork {
          Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
          Color(white: 0.2).overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)))
        }
      }
      .frame(width: height - 14, height: height - 14)
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      .frame(maxWidth: .infinity)
      Color.clear.frame(width: notchWidth)
      AudioBars(playing: media.isPlaying && !reduced).frame(width: 16, height: 12).frame(maxWidth: .infinity)
    }
    .accessibilityElement()
    .accessibilityLabel(media.track.map { "Now playing \($0.title) by \($0.artist)" } ?? "Now playing")
  }
}

struct AudioBars: View {
  var playing: Bool
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 12, paused: !playing)) { context in
      bars(at: context.date.timeIntervalSinceReferenceDate)
    }
  }
  private func bars(at time: Double) -> some View {
    HStack(alignment: .center, spacing: 2) {
      ForEach(0..<4, id: \.self) { index in
        Capsule().fill(Color.accentColor).frame(width: 2.5, height: barHeight(index, time))
      }
    }
  }
  private func barHeight(_ index: Int, _ time: Double) -> CGFloat {
    guard playing else { return 3 }
    let phase = time * (5 + Double(index) * 1.7) + Double(index) * 1.3
    return CGFloat(3 + 9 * (sin(phase) + 1) / 2)
  }
}
