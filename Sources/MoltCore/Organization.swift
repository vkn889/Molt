import Foundation
import SQLite3

public struct ChecklistItem: Codable, Identifiable {
  public var id = UUID()
  public var text: String
  public var done = false
  public init(_ text: String) { self.text = text }
}
public struct WorkTask: Codable, Identifiable {
  public var id = UUID()
  public var title: String
  public var created = Date()
  public var due: Date?
  public var completed: Date?
  public var recurrenceParentID: UUID?
  public var priority = 0, estimate = 25
  public var project = "Inbox", tags = "", recurrence = "none"
  public var today = false
  public var checklist: [ChecklistItem] = []
  public var history: [String] = []
  public init(_ title: String) { self.title = title }
}
public struct Note: Codable, Identifiable {
  public var id = UUID()
  public var title: String
  public var body = "", tags = "", link = ""
  public var pinned = false
  public var taskID: UUID?
  public var modified = Date()
  public init(_ title: String, body: String = "") {
    self.title = title
    self.body = body
  }
}
public struct Reminder: Codable, Identifiable {
  public var id = UUID()
  public var title: String
  public var due: Date
  public var recurrence = "none"
  public var timeZone = TimeZone.current.identifier
  public var completed = false
  public var schedulingError: String?
  public init(_ title: String, due: Date) {
    self.title = title
    self.due = due
  }
  public mutating func complete() {
    if let next = Recurrence.next(after: due, rule: recurrence, zone: timeZone) {
      due = next
    } else {
      completed = true
    }
  }
}
public enum Recurrence {
  public static func next(
    after date: Date, rule: String, zone: String = TimeZone.current.identifier
  ) -> Date? {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone) ?? .current
    switch rule {
    case "daily": return c.date(byAdding: .day, value: 1, to: date)
    case "weekly": return c.date(byAdding: .day, value: 7, to: date)
    case "monthly": return c.date(byAdding: .month, value: 1, to: date)
    default: return nil
    }
  }
}
public struct Routine: Codable, Identifiable {
  public var id = UUID()
  public var title: String
  public var steps: [ChecklistItem] = []
  public var weeklyTarget = 5
  public var checkIns: [Date] = []
  public init(_ title: String) { self.title = title }
}
public struct FocusSession: Codable, Identifiable {
  public var petRewardDelivered: Bool?
  public var id = UUID()
  public var started: Date
  public var lastResumed: Date?
  public var elapsed: Double = 0
  public var target: Double
  public var finished: Date?
  public var taskID: UUID?
  public var note = ""
  public init(now: Date, minutes: Int, taskID: UUID? = nil) {
    started = now
    lastResumed = now
    target = Double(minutes) * 60
    self.taskID = taskID
  }
  public func duration(at now: Date) -> Double {
    elapsed + (lastResumed.map { max(0, now.timeIntervalSince($0)) } ?? 0)
  }
  public mutating func pause(at now: Date) {
    elapsed = duration(at: now)
    lastResumed = nil
  }
  public mutating func stop(at now: Date) {
    pause(at: now)
    finished = now
  }
}
public struct ActivityInterval: Codable, Identifiable {
  public var id = UUID()
  public var app: String
  public var name: String
  public var start: Date
  public var end: Date
  public var category = "uncategorized"
  public init(app: String, name: String, start: Date, end: Date, category: String) {
    self.app = app
    self.name = name
    self.start = start
    self.end = end
    self.category = category
  }
}
public struct ConsentPreferences: Codable {
  public var tracking = false, paused = false, notifications = false, calendar = false
  public var excludedApps = "", categories: [String: String] = [:], selectedCalendars: [String] = []
  public var retentionDays = 7
  public var quickCaptureKey = "k"
  public init() {}
}
public struct Organization: Codable {
  public var tasks: [WorkTask] = [], notes: [Note] = [], reminders: [Reminder] = [],
    routines: [Routine] = [], sessions: [FocusSession] = [], intervals: [ActivityInterval] = []
  public var consent = ConsentPreferences()
  public init() {}
  public mutating func completeTask(_ id: UUID, now: Date) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    if tasks[index].completed != nil {
      tasks[index].completed = nil
      tasks[index].history.append("Completion undone on \(now.formatted())")
      return
    }
    tasks[index].completed = now
    tasks[index].history.append("Completed on \(now.formatted())")
    if !tasks.contains(where: { $0.recurrenceParentID == id }),
      let due = tasks[index].due,
      let next = Recurrence.next(after: due, rule: tasks[index].recurrence)
    {
      var following = tasks[index]
      following.id = UUID()
      following.recurrenceParentID = id
      following.created = now
      following.due = next
      following.completed = nil
      following.today = false
      following.history = []
      following.checklist = following.checklist.map { ChecklistItem($0.text) }
      tasks.append(following)
    }
  }
}

/// Separate transactional database keeps utility data out of pet exports and snapshots.
public final class OrganizationStore {
  private var db: OpaquePointer?
  public init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
      throw MoltError.invalid("Cannot open organization database.")
    }
    try execute(
      "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS records(kind TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(kind,id)); PRAGMA user_version=1;"
    )
  }
  deinit { sqlite3_close(db) }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw MoltError.invalid("Organization storage: \(String(cString: sqlite3_errmsg(db)))")
    }
  }
  public func load() throws -> Organization {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard
      sqlite3_prepare_v2(db, "SELECT kind,payload FROM records", -1, &statement, nil) == SQLITE_OK
    else { throw MoltError.invalid("Cannot read organization data.") }
    var o = Organization()
    let decoder = JSONDecoder()
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      let kind = String(cString: sqlite3_column_text(statement, 0))
      let count = Int(sqlite3_column_bytes(statement, 1))
      guard let bytes = sqlite3_column_blob(statement, 1) else {
        throw MoltError.invalid("Empty organization record.")
      }
      let data = Data(bytes: bytes, count: count)
      switch kind {
      case "task": o.tasks.append(try decoder.decode(WorkTask.self, from: data))
      case "note": o.notes.append(try decoder.decode(Note.self, from: data))
      case "reminder": o.reminders.append(try decoder.decode(Reminder.self, from: data))
      case "routine": o.routines.append(try decoder.decode(Routine.self, from: data))
      case "focus": o.sessions.append(try decoder.decode(FocusSession.self, from: data))
      case "interval": o.intervals.append(try decoder.decode(ActivityInterval.self, from: data))
      case "consent": o.consent = try decoder.decode(ConsentPreferences.self, from: data)
      default: throw MoltError.invalid("Unknown organization record version.")
      }
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else {
      throw MoltError.invalid("Organization database read failed.")
    }
    return o
  }
  public func save(_ o: Organization) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try execute("DELETE FROM records")
      for t in o.tasks { try insert(t, kind: "task", id: t.id.uuidString) }
      for t in o.notes { try insert(t, kind: "note", id: t.id.uuidString) }
      for t in o.reminders { try insert(t, kind: "reminder", id: t.id.uuidString) }
      for t in o.routines { try insert(t, kind: "routine", id: t.id.uuidString) }
      for t in o.sessions { try insert(t, kind: "focus", id: t.id.uuidString) }
      for t in o.intervals { try insert(t, kind: "interval", id: t.id.uuidString) }
      try insert(o.consent, kind: "consent", id: "preferences")
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  private func insert<T: Encodable>(_ value: T, kind: String, id: String) throws {
    let data = try JSONEncoder().encode(value)
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard
      sqlite3_prepare_v2(db, "INSERT INTO records VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK
    else { throw MoltError.invalid("Cannot prepare organization write.") }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, kind, -1, transient)
    sqlite3_bind_text(statement, 2, id, -1, transient)
    _ = data.withUnsafeBytes {
      sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), transient)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw MoltError.invalid("Organization write failed. Changes were rolled back.")
    }
  }
}
