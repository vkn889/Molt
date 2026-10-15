import AppKit
import EventKit
import MoltCore
import SwiftUI

/// The notch's home: music with Molt bopping along underneath, what's next today, and how the
/// Mac and Molt are doing.
struct NotchHomeView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var media: NowPlayingController
  @State private var showLibrary = CommandLine.arguments.contains("--playlists")
  var body: some View {
    HStack(alignment: .top, spacing: 18) {
      HomeMusic(controller: controller, media: media, showLibrary: $showLibrary).frame(width: 300, alignment: .topLeading)
      if showLibrary {
        PlaylistShelf(library: controller.hub.library, close: { showLibrary = false })
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      } else {
        WeekCard(controller: controller, contexts: controller.contexts).frame(width: 176, alignment: .topLeading)
        Button { controller.tab = "Health" } label: {
          HomeHealth(controller: controller).frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("See what's using your Mac")
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.86), value: showLibrary)
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

/// Now playing, as in the mockup: the cover with Molt dancing beneath it in headphones, the song,
/// a scrubber, the controls and what's up next.
struct HomeMusic: View {
  @ObservedObject var controller: PetController
  @ObservedObject var media: NowPlayingController
  @Binding var showLibrary: Bool
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(spacing: 0) {
        Button { showLibrary.toggle() } label: { artwork }.buttonStyle(.plain).help("Your playlists")
        molt.padding(.top, -2)
      }
      .frame(width: 96)
      VStack(alignment: .leading, spacing: 0) {
        if let track = media.track {
          Text(track.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
          Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 13)).lineLimit(1)
            .foregroundStyle(Color.white.opacity(0.55)).padding(.top, 2)
          ProgressScrubber(media: media).padding(.top, 10)
        } else if media.permissionNeeded {
          Text("Allow music control").font(.system(size: 16, weight: .semibold))
          Text("Molt needs Automation access to follow Spotify or Apple Music.").font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.5)).lineLimit(2).padding(.top, 2)
          Button("Open Settings", action: media.openAutomationSettings).padding(.top, 6)
        } else {
          Text("Not playing").font(.system(size: 16, weight: .semibold))
          Text("Pick a playlist, or play something in Spotify or Apple Music.").font(.system(size: 11.5))
            .foregroundStyle(Color.white.opacity(0.5)).lineLimit(2).padding(.top, 2)
        }
        HStack(spacing: 22) {
          Button(action: media.previous) { Image(systemName: "backward.fill").font(.system(size: 17)) }
            .accessibilityLabel("Previous track").disabled(media.track == nil).foregroundStyle(Color.white.opacity(0.65))
          Button(action: media.playPause) { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)) }
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
          Button(action: media.next) { Image(systemName: "forward.fill").font(.system(size: 17)) }
            .accessibilityLabel("Next track").disabled(media.track == nil).foregroundStyle(Color.white.opacity(0.65))
        }
        .buttonStyle(.plain).padding(.top, 6).padding(.leading, 2)
        if let next = media.upNext.first {
          HStack(spacing: 6) {
            Text("Up next").foregroundStyle(Color.white.opacity(0.3))
            Text(next.title).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
          }
          .font(.system(size: 11.5)).padding(.top, 10)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }
  private var artwork: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
      if let image = media.artwork {
        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill).transition(.opacity)
      } else {
        Image(systemName: "music.note").font(.system(size: 28, weight: .medium)).foregroundStyle(Color.white.opacity(0.3))
      }
    }
    .frame(width: 96, height: 96)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(alignment: .bottomTrailing) {
      if let icon = media.appIcon {
        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 24, height: 24)
          .shadow(color: .black.opacity(0.5), radius: 3, y: 1).offset(x: 6, y: 6).accessibilityHidden(true)
      }
    }
    .scaleEffect(media.isPlaying || reduced ? 1 : 0.95)
    .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: media.isPlaying)
    .animation(reduced ? nil : .easeOut(duration: 0.25), value: media.artwork)
    .accessibilityLabel(media.track.map { "Artwork for \($0.title)" } ?? "No artwork")
  }
  /// Molt under the cover: dancing in headphones while music plays, with notes floating up.
  private var molt: some View {
    let playing = media.isPlaying && !reduced && (UserDefaults.standard.object(forKey: "moltDances") as? Bool ?? true)
    let base = controller.displayMood
    let dancing = playing && ["idle", "happy"].contains(base)
    return ZStack {
      CreatureView(
        appearance: playing ? controller.companion.appearance.wearing("headphones") : controller.companion.appearance,
        mood: dancing ? "dancing" : base, shell: controller.shellColor, poked: controller.poked)
        .frame(width: 46, height: 43)
      if dancing { MusicNotes(tint: MoltTheme.body(controller.companion.appearance.palette)).frame(width: 110, height: 50).allowsHitTesting(false) }
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { controller.tab = "Play" }
    .onTapGesture { controller.poked = Date() }
    .help("Say hi to \(controller.petName). Double-click to play.")
  }
}

/// Little notes drifting up and fading, on both sides of Molt.
struct MusicNotes: View {
  var tint: Color
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      Canvas { canvas, size in
        for i in 0..<3 {
          let phase = (t / 2.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
          let side: Double = i == 1 ? 1 : -1
          let x = size.width / 2 + side * (24 + 10 * Double(i)) + sin(phase * 6 + Double(i)) * 4
          let y = size.height - phase * size.height
          let symbol = canvas.resolve(Image(systemName: i == 2 ? "music.note.list" : "music.note"))
          canvas.opacity = (1 - phase) * 0.9
          canvas.draw(symbol, in: CGRect(x: x, y: y, width: 10 - Double(i), height: 11 - Double(i)))
        }
      }
      .foregroundStyle(tint)
    }
  }
}

// MARK: Now playing

struct NowPlayingCard: View {
  @ObservedObject var media: NowPlayingController
  @Binding var showLibrary: Bool
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack(alignment: .bottomTrailing) {
        Button { showLibrary.toggle() } label: { artwork }.buttonStyle(.plain)
          .help("Your playlists")
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
          Text("Pick a playlist, or play something in Spotify or Apple Music.")
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
      Spacer(minLength: 0)
      Button { showLibrary.toggle() } label: {
        Image(systemName: "music.note.list").font(.system(size: 13, weight: .semibold))
      }
      .buttonStyle(NotchIconButtonStyle(size: 28, prominent: showLibrary))
      .help("Your playlists").accessibilityLabel(showLibrary ? "Hide playlists" : "Show playlists")
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
    let days = (-1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 6) {
        Text(today, format: .dateTime.month(.abbreviated))
          .font(.system(size: 26, weight: .heavy)).foregroundStyle(.white).fixedSize()
        ForEach(days, id: \.self) { day in dayCell(day, today: today) }
      }
      agenda(today: today)
    }
  }
  private func dayCell(_ day: Date, today: Date) -> some View {
    let isToday = day == today
    let past = day < today
    let hasEvents = contexts.events.contains { calendar.isDate($0.startDate, inSameDayAs: day) }
    return VStack(spacing: 1) {
      Text(day, format: .dateTime.weekday(.abbreviated))
        .font(.system(size: 8.5, weight: .semibold)).textCase(.uppercase)
        .foregroundStyle(isToday ? Color.accentColor : Color.white.opacity(0.4))
      Text(day, format: .dateTime.day(.twoDigits))
        .font(.system(size: 15, weight: .semibold).monospacedDigit())
        .foregroundStyle(isToday ? Color.accentColor : Color.white.opacity(past ? 0.3 : 0.55))
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
      Button { controller.tab = "Hub" } label: {
        HStack(spacing: 8) {
          Image(systemName: "calendar.badge.checkmark").font(.system(size: 14))
          Text("Nothing for today").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.45))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
      }.buttonStyle(.plain).help("Open Hub")
    } else {
      // An event starting within the hour gets a card with a countdown and Join.
      let soon = events.first { !$0.isAllDay && $0.startDate.timeIntervalSinceNow < 3600 }
      let listed = Array(events.filter { $0.eventIdentifier != soon?.eventIdentifier }.prefix(soon == nil ? 2 : 1))
      VStack(alignment: .leading, spacing: 6) {
        if let soon { SoonCard(event: soon) }
        ForEach(listed, id: \.eventIdentifier) { event in
          row(
            color: Color(nsColor: event.calendar?.color ?? .systemBlue), title: event.title ?? "Event",
            detail: event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
        }
        ForEach(Array(tasks.prefix(max(0, 2 - min(2, listed.count + (soon == nil ? 0 : 1)))))) { task in
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

/// The next event, when it starts within the hour: a countdown, its name and when, and Join.
struct SoonCard: View {
  var event: EKEvent
  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let minutes = Int(ceil(event.startDate.timeIntervalSince(context.date) / 60))
      HStack(alignment: .top, spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(minutes <= 0 ? "NOW" : "IN \(minutes) MIN").font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color(red: 0.39, green: 0.82, blue: 1))
          Text(event.title ?? "Event").font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
          Text(Self.when(event)).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        }
        Spacer(minLength: 0)
        if let link = UpNextTile.callLink(event) {
          Button("Join") { NSWorkspace.shared.open(link) }.buttonStyle(PillButtonStyle(tint: .accentColor))
        }
      }
      .padding(.horizontal, 11).padding(.vertical, 9)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.16)))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.3)))
    }
    .accessibilityElement(children: .combine)
  }
  static func when(_ event: EKEvent) -> String {
    let span = event.startDate.formatted(date: .omitted, time: .shortened) + " – " + event.endDate.formatted(date: .omitted, time: .shortened)
    let place = UpNextTile.callLink(event)?.host.map(UpNextTile.service) ?? event.location
    return [span, place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

/// The Mac and Molt, as in the mockup: battery, CPU, memory, today's focus, and Molt's mood.
struct HomeHealth: View {
  @ObservedObject var controller: PetController
  var body: some View {
    let values = controller.health.values
    let focus = FocusMath.today(controller.organization.sessions, now: Date()).minutes
    let tint = MoltTheme.body(controller.companion.appearance.palette)
    VStack(alignment: .leading, spacing: 9) {
      if !controller.healthEnabled {
        Text("Mac health").font(.system(size: 12, weight: .semibold))
        Text("Battery, CPU and memory at a glance.").font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.45))
          .fixedSize(horizontal: false, vertical: true)
        Button("Turn on") { controller.healthEnabled = true; controller.refreshHealth() }
      } else {
        if let battery = values["batteryLevel"] {
          meter("Battery", "\(Int((battery * 100).rounded()))%", battery, battery < 0.2 && values["isCharging"] != 1 ? .orange : .white)
        }
        meter("CPU", values["cpuLoad"].map { "\(Int(($0 * 100).rounded()))%" } ?? "…", values["cpuLoad"] ?? 0, (values["cpuLoad"] ?? 0) > 0.85 ? .orange : .white)
        meter("Memory", values["memoryUsed"].map { "\(Int(($0 * 100).rounded()))%" } ?? "…", values["memoryUsed"] ?? 0, (values["memoryPressure"] ?? 0) >= 0.5 ? .orange : .white)
      }
      if NotchPrefs.shared.has("focus") {
        meter("Focus today", focus >= 60 ? "\(focus / 60)h \(focus % 60)m" : "\(focus) min", min(1, Double(focus) / 120), tint)
      }
      meter(controller.petName, Self.word(controller), controller.score / 100, tint)
    }
  }
  static func word(_ controller: PetController) -> String {
    switch controller.displayMood {
    case "sleeping": return "Asleep"
    case "tired": return "Sleepy"
    case "hungry", "eating": return "Hungry"
    case "worried", "sweating": return "Worried"
    case "alert": return "Needs you"
    case "working", "thinking": return "Working"
    default: return controller.score >= 70 ? "Happy" : controller.score >= 40 ? "Okay" : "Lonely"
    }
  }
  private func meter(_ title: String, _ label: String, _ value: Double, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        Spacer(minLength: 4)
        Text(label).fontWeight(.semibold).monospacedDigit()
      }
      .font(.system(size: 12))
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.12))
          Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, value)))
        }
      }.frame(height: 3)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(label)")
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

/// Shown beside the hardware notch while music plays or the screen is recording and Molt is
/// closed. Clicking it stops a recording, or opens Home.
struct NotchLiveActivity: View {
  @ObservedObject var media: NowPlayingController
  @ObservedObject var actions: QuickActions
  var notchWidth: CGFloat
  var height: CGFloat
  /// Recording and music can both be going; this shows the one picked beside the notch.
  var showRecording = true
  @Environment(\.moltReducedMotion) private var reduced
  private var recording: Date? { showRecording ? actions.recording : nil }
  var body: some View {
    HStack(spacing: 0) {
      Group {
        if recording != nil {
          Circle().fill(Color.red).frame(width: 10, height: 10)
            .opacity(reduced ? 1 : 0.85)
        } else if let image = media.artwork {
          Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            .frame(width: height - 14, height: height - 14)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
          Color(white: 0.2).overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)))
            .frame(width: height - 14, height: height - 14)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
      }
      .frame(maxWidth: .infinity)
      Color.clear.frame(width: notchWidth)
      Group {
        if let started = recording {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(HangoutView.clock(context.date.timeIntervalSince(started)))
              .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.red)
          }
        } else {
          AudioBars(playing: media.isPlaying && !reduced).frame(width: 16, height: 12)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .help(recording != nil ? "Click to stop recording" : "Open Molt")
    .accessibilityElement()
    .accessibilityLabel(recording != nil ? "Recording screen. Click to stop." : media.track.map { "Now playing \($0.title) by \($0.artist)" } ?? "Now playing")
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
