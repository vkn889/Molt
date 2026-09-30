import Foundation

public struct ProcessSample: Equatable, Sendable {
  public var pid: Int32
  public var cpu: Double
  /// Resident memory in bytes.
  public var memory: Int
  public var path: String
}

/// Processes grouped under the app that owns them, so a browser and all its helpers read as one.
public struct AppUsage: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var appPath: String?
  public var cpu: Double
  public var memory: Int
  public var pids: [Int32]
}

public enum ProcessTable {
  /// Parses `ps -axo pid=,pcpu=,rss=,comm=`. Paths may contain spaces.
  public static func parse(_ output: String) -> [ProcessSample] {
    output.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
      guard fields.count == 4, let pid = Int32(fields[0]),
        let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")), let rss = Int(fields[2])
      else { return nil }
      return ProcessSample(pid: pid, cpu: cpu, memory: rss * 1024, path: String(fields[3]).trimmingCharacters(in: .whitespaces))
    }
  }
  /// The outermost `.app` bundle in an executable path, if any.
  public static func appBundle(of path: String) -> String? {
    guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil)
    else { return nil }
    return String(path[..<range.lowerBound]) + ".app"
  }
  public static func group(_ samples: [ProcessSample]) -> [AppUsage] {
    var groups: [String: AppUsage] = [:]
    for sample in samples {
      let bundle = appBundle(of: sample.path)
      let key = bundle ?? sample.path
      let name = bundle.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        ?? URL(fileURLWithPath: sample.path).lastPathComponent
      var usage = groups[key] ?? AppUsage(id: key, name: name, appPath: bundle, cpu: 0, memory: 0, pids: [])
      usage.cpu += sample.cpu
      usage.memory += sample.memory
      usage.pids.append(sample.pid)
      groups[key] = usage
    }
    return Array(groups.values)
  }
}
