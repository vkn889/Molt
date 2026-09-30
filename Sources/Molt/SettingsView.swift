import MoltCore
import ServiceManagement
import SwiftUI

/// Everything adjustable, in three short columns.
struct SettingsView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var coordinator: IslandCoordinator
  @ObservedObject var sessions: SessionsController
  @ObservedObject var spotify: SpotifyAccount
  @ObservedObject var appleMusic: AppleMusicLibrary
  @Binding var accent: String
  init(controller: PetController, coordinator: IslandCoordinator, accent: Binding<String>) {
    self.controller = controller
    self.coordinator = coordinator
    self.sessions = controller.hub.sessions
    self.spotify = controller.hub.library.spotify
    self.appleMusic = controller.hub.library.appleMusic
    _accent = accent
  }
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      column("Molt") {
        HStack(spacing: 8) {
          CreatureView(appearance: controller.companion.appearance, mood: "happy", moving: false)
            .frame(width: 28, height: 26)
          TextField("Name", text: Binding(
            get: { controller.companion.name },
            set: { value in controller.changeCompanion { $0.name = String(value.prefix(40)) } }))
            .textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
        }
        row("Color") {
          ForEach(["sage", "ocean", "sunset", "violet"], id: \.self) { palette in
            swatch(MoltTheme.body(palette), selected: controller.companion.appearance.palette == palette, label: palette) {
              controller.changeCompanion { $0.appearance.palette = palette }
            }
          }
        }
        row("Accent") {
          ForEach(["blue", "mint", "violet", "amber", "rose"], id: \.self) { value in
            swatch(MoltTheme.accent(value), selected: accent == value, label: "\(value) accent") { accent = value }
          }
        }
        toggle("Reduce motion", pref(\.reducedMotion))
      }
      column("Notch") {
        toggle("Open on hover", $coordinator.hoverToOpen)
        toggle("Mac health", $controller.healthEnabled)
        toggle("Launch at login", Binding(
          get: { SMAppService.mainApp.status == .enabled }, set: { controller.setLogin($0) }))
        HStack {
          Text("Display").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8))
          Spacer()
          Picker("Display", selection: $coordinator.displayChoice) {
            Text("Automatic").tag(-1)
            Text("Active").tag(-2)
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
              Text(screen.localizedName).tag(index)
            }
          }.labelsHidden().controlSize(.small).frame(width: 110)
        }
        Text(coordinator.shortcutMessage).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
      }
      column("Connections") {
        toggle("Calendar", Binding(get: { controller.organization.consent.calendar }, set: setCalendar))
        toggle("App usage", Binding(
          get: { controller.organization.consent.tracking },
          set: { value in controller.updateOrganization { $0.consent.tracking = value }; controller.configureContext() }))
        toggle("Claude Code & Codex", $sessions.enabled)
        toggle("Keep copies of chats", $sessions.archive).disabled(!sessions.enabled)
        connection("Spotify", connected: spotify.connected, detail: spotify.userName,
          connect: { controller.tab = "Notch"; controller.hub.library.source = .spotify },
          disconnect: spotify.disconnect)
        connection("Apple Music", connected: appleMusic.connected, detail: nil,
          connect: appleMusic.connect, disconnect: appleMusic.disconnect)
      }
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
  }

  private func column<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      content()
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 16))
  }
  private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: 7) {
      Text(title).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8))
      Spacer(minLength: 4)
      content()
    }
  }
  private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
    HStack {
      Text(title).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
      Spacer(minLength: 4)
      Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }
  }
  private func swatch(_ color: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Circle().fill(color).frame(width: 13, height: 13)
        .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 1.5).padding(-3))
    }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func connection(_ title: String, connected: Bool, detail: String?, connect: @escaping () -> Void, disconnect: @escaping () -> Void) -> some View {
    HStack(spacing: 6) {
      Circle().fill(connected ? Color.green : Color.white.opacity(0.25)).frame(width: 6, height: 6)
      Text(detail.map { "\(title) · \($0)" } ?? title).font(.system(size: 11)).lineLimit(1)
        .foregroundStyle(Color.white.opacity(0.8))
      Spacer(minLength: 4)
      Button(connected ? "Disconnect" : "Connect", action: connected ? disconnect : connect)
        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
    }
  }
  private func pref<T>(_ key: WritableKeyPath<PetPreferences, T>) -> Binding<T> {
    Binding(
      get: { controller.companion.preferences[keyPath: key] },
      set: { value in controller.changeCompanion { $0.preferences[keyPath: key] = value } })
  }
  /// Turning the calendar on shows every calendar; there is no separate picker to manage.
  private func setCalendar(_ value: Bool) {
    guard value else {
      controller.updateOrganization { $0.consent.calendar = false }
      controller.configureContext()
      return
    }
    controller.contexts.enableCalendar { granted in
      controller.updateOrganization { $0.consent.calendar = granted }
      controller.configureContext()
      let all = controller.contexts.calendars.map(\.calendarIdentifier)
      controller.updateOrganization { $0.consent.selectedCalendars = all }
      controller.configureContext()
    }
  }
}
