import Foundation

public enum ActivityPolicy {
  public static func permits(app: String, preferences: ConsentPreferences) -> Bool {
    let exclusions = preferences.excludedApps.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return preferences.tracking && !preferences.paused && !exclusions.contains(app)
  }
  public static func retained(
    _ records: [ActivityInterval], preferences: ConsentPreferences, now: Date
  ) -> [ActivityInterval] {
    let cutoff = now.addingTimeInterval(-Double(min(30, max(1, preferences.retentionDays))) * 86400)
    let exclusions = preferences.excludedApps.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return records.filter { $0.end >= cutoff && $0.end >= $0.start && !exclusions.contains($0.app) }
  }
}
