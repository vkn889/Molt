import Foundation

public struct HubScene: Codable, Identifiable {
  public var id = UUID()
  public var name: String
  public var minutes: Int
  public var playlist: String
  public var wallpaper: String
  public var apps: [String]
  public init(name: String, minutes: Int = 25, playlist: String = "", wallpaper: String = "", apps: [String] = []) {
    self.name = name; self.minutes = minutes; self.playlist = playlist; self.wallpaper = wallpaper; self.apps = apps
  }
}
public struct TokenRecord: Codable, Identifiable {
  public var id: String
  public var date: Date
  public var tool: String
  public var input: Int
  public var output: Int
  public var cached: Int
  public var reportedCost: Double?
}
public enum UsageMath {
  public static func seconds(_ intervals: [ActivityInterval], from start: Date, to end: Date) -> [String: Double] {
    var totals: [String: Double] = [:]
    for interval in intervals {
      let duration = min(interval.end, end).timeIntervalSince(max(interval.start, start))
      if duration > 0 { totals[interval.name, default: 0] += duration }
    }
    return totals
  }
  public static func estimate(_ records: [TokenRecord], inputRate: Double, outputRate: Double, cacheRate: Double) -> Double? {
    guard inputRate >= 0, outputRate >= 0, cacheRate >= 0,
      inputRate.isFinite, outputRate.isFinite, cacheRate.isFinite,
      inputRate + outputRate + cacheRate > 0 else { return nil }
    return records.reduce(0) { $0 + (Double($1.input) * inputRate + Double($1.output) * outputRate + Double($1.cached) * cacheRate) / 1_000_000 }
  }
}
/// Reads only numeric usage fields; message text is never retained in the result.
public enum LocalUsageParser {
  public static func records(lines: [String], tool: String, source: String) -> [TokenRecord] {
    var records: [String: TokenRecord] = [:]
    var previous = (input: 0, output: 0, cached: 0)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    for line in lines {
      guard let data = line.data(using: .utf8), let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let timestamp = row["timestamp"] as? String, let date = formatter.date(from: timestamp) ?? plain.date(from: timestamp) else { continue }
      if tool == "Codex" {
        guard let payload = row["payload"] as? [String: Any], payload["type"] as? String == "token_count",
          let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] else { continue }
        let input = max(0, usage["input_tokens"] as? Int ?? 0)
        let output = max(0, usage["output_tokens"] as? Int ?? 0)
        let cached = min(input, max(0, usage["cached_input_tokens"] as? Int ?? 0))
        let di = max(0, input - previous.input), dout = max(0, output - previous.output), dc = min(di, max(0, cached - previous.cached))
        previous = (input, output, cached)
        guard di + dout > 0 else { continue }
        let id = "\(source):\(timestamp):\(input):\(output):\(cached)"
        records[id] = TokenRecord(id: id, date: date, tool: tool, input: di - dc, output: dout, cached: dc)
      } else {
        guard let message = row["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
          let id = message["id"] as? String else { continue }
        let input = max(0, usage["input_tokens"] as? Int ?? 0) + max(0, usage["cache_creation_input_tokens"] as? Int ?? 0)
        let output = max(0, usage["output_tokens"] as? Int ?? 0)
        let cached = max(0, usage["cache_read_input_tokens"] as? Int ?? 0)
        let cost = row["costUSD"] as? Double
        records[id] = TokenRecord(id: id, date: date, tool: tool, input: input, output: output, cached: cached, reportedCost: cost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
      }
    }
    return records.values.sorted { $0.date < $1.date }
  }
}
