import AppKit
import CoreGraphics
import EventKit
import MoltCore
import UserNotifications

@MainActor final class ContextAdapters: ObservableObject {
  @Published var calendars: [EKCalendar] = []
  @Published var events: [EKEvent] = []
  @Published var calendarError: String?
  @Published var notificationStatus = "Notifications are off. Reminders remain available in Today."
  @Published var currentApp = "Tracking is off"
  private let eventStore = EKEventStore()
  private var observed: (id: String, name: String, start: Date)?
  private var consent = ConsentPreferences()
  private var suspended = false
  var interval: ((ActivityInterval) -> Void)?
  var onWake: (() -> Void)?
  var onSleep: (() -> Void)?
  init() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(activated), name: NSWorkspace.didActivateApplicationNotification,
      object: nil)
    for name in [
      NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ] { center.addObserver(self, selector: #selector(sleeping), name: name, object: nil) }
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] { center.addObserver(self, selector: #selector(waking), name: name, object: nil) }
  }
  func configure(_ preferences: ConsentPreferences) {
    // Discard an in-progress interval when consent changes. Exclusions apply before storage.
    observed = nil
    consent = preferences
    currentApp =
      !preferences.tracking
      ? "Tracking is off" : preferences.paused ? "Tracking paused" : "Waiting for an application"
    if preferences.tracking && !preferences.paused { beginCurrent() }
    if !preferences.calendar {
      calendars = []
      events = []
    }
  }
  private func beginCurrent() {
    guard !suspended, consent.tracking, !consent.paused,
      let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier
    else { return }
    guard ActivityPolicy.permits(app: id, preferences: consent) else {
      currentApp = "Excluded application"
      return
    }
    observed = (id, app.localizedName ?? id, Date())
    currentApp =
      "\(app.localizedName ?? id) · observed \(Date().formatted(date: .omitted, time: .shortened))"
  }
  func flush() {
    guard let old = observed else { return }
    let now = Date()
    observed = nil
    if consent.tracking && !consent.paused && now > old.start {
      // Bound a missed lifecycle callback instead of attributing an entire sleep gap.
      let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
      let activeEnd = idle > 120 ? now.addingTimeInterval(-(idle - 120)) : now
      let end = max(old.start, min(activeEnd, old.start.addingTimeInterval(90)))
      interval?(
        ActivityInterval(
          app: old.id, name: old.name, start: old.start, end: end,
          category: consent.categories[old.id] ?? "uncategorized"))
    }
    beginCurrent()
  }
  @objc private func activated() {
    flush()
    observed = nil
    beginCurrent()
  }
  @objc private func sleeping() {
    flush()
    suspended = true
    observed = nil
    currentApp = "Tracking suspended"
    onSleep?()
  }
  @objc private func waking() {
    suspended = false
    observed = nil
    beginCurrent()
    onWake?()
  }
  func enableCalendar(completion: @escaping (Bool) -> Void) {
    let done: @Sendable (Bool, Error?) -> Void = { [weak self] granted, error in
      Task { @MainActor [weak self] in
        self?.calendarError =
          error?.localizedDescription
          ?? (granted ? nil : "Calendar access was not granted. All other tools still work.")
        completion(granted)
        if granted { self?.refreshCalendar(selected: []) }
      }
    }
    if #available(macOS 14, *) {
      eventStore.requestFullAccessToEvents(completion: done)
    } else {
      eventStore.requestAccess(to: .event, completion: done)
    }
  }
  func refreshCalendar(selected: [String]) {
    guard consent.calendar else { return }
    let status = EKEventStore.authorizationStatus(for: .event)
    guard
      status == .authorized
        || {
          if #available(macOS 14, *) { return status == .fullAccess }
          return false
        }()
    else {
      events = []
      calendars = []
      calendarError = "Calendar access is unavailable or revoked."
      return
    }
    calendars = eventStore.calendars(for: .event)
    let allowed = calendars.filter { selected.contains($0.calendarIdentifier) }
    guard !allowed.isEmpty else {
      events = []
      return
    }
    let predicate = eventStore.predicateForEvents(
      withStart: Date(), end: Date().addingTimeInterval(7 * 86400), calendars: allowed)
    events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(
      30
    ).map { $0 }
  }
  func requestNotifications(completion: @escaping (Bool) -> Void) {
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      notificationStatus = "Run the packaged Molt.app to enable notifications."
      completion(false)
      return
    }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      [weak self] granted, error in
      Task { @MainActor in
        self?.notificationStatus =
          error?.localizedDescription
          ?? (granted
            ? "Enabled. Delivery depends on macOS settings and Focus."
            : "Permission denied. Reminders remain in Today.")
        completion(granted)
      }
    }
  }
  func schedule(
    _ reminders: [Reminder], enabled: Bool, quiet: PetPreferences, name: String = "Molt"
  ) {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    guard enabled else { return }
    let now = Date()
    var occurrences: [(Reminder, Date)] = []
    for reminder in reminders.filter({ !$0.completed }) {
      var date = reminder.due
      // A stale reminder stays visible in Today; do not replay old alerts.
      var count = 0
      while date < now && reminder.recurrence != "none" && count < 5000 {
        guard
          let next = Recurrence.next(
            after: date, rule: reminder.recurrence, zone: reminder.timeZone)
        else { break }
        date = next
        count += 1
      }
      for _ in 0..<16 {
        if date > now { occurrences.append((reminder, date)) }
        guard
          let next = Recurrence.next(
            after: date, rule: reminder.recurrence, zone: reminder.timeZone)
        else { break }
        date = next
      }
    }
    for (reminder, date) in occurrences.sorted(by: { $0.1 < $1.1 }).prefix(60) {
      let content = UNMutableNotificationContent()
      content.title = "\(name) reminder"
      content.body = reminder.title
      if quiet.sound && !quiet.quiet(at: date) { content.sound = .default }
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
      center.add(
        UNNotificationRequest(
          identifier: "\(reminder.id.uuidString)-\(Int(date.timeIntervalSince1970))",
          content: content, trigger: trigger)
      ) { [weak self] error in
        if let error {
          Task { @MainActor in
            self?.notificationStatus =
              "Scheduling failed: \(error.localizedDescription). Reminder remains in Today."
          }
        }
      }
    }
  }
}
