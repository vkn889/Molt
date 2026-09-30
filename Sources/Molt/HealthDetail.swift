import AppKit
import IOKit
import IOKit.ps
import MoltCore
import SwiftUI

/// What is using the Mac's CPU, memory, battery and storage, with safe one-click fixes. Nothing
/// is quit or removed without a confirmation, and system processes are never touched.
@MainActor final class HealthDetailController: ObservableObject {
  enum Section: String, CaseIterable { case cpu = "CPU", memory = "Memory", battery = "Battery", storage = "Storage" }
  struct Battery: Equatable {
    var health: Double?
    var cycles: Int?
    var temperature: Double?
    var minutesLeft: Int?
    var charging = false
    var onPower = false
    var watts: Int?
  }
  struct Folder: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var symbol: String
    var size: Int64?
    var action: String?
  }
  @Published var section: Section = .cpu
  @Published private(set) var apps: [AppUsage] = []
  @Published private(set) var battery = Battery()
  @Published private(set) var folders: [Folder] = []
  @Published private(set) var scanning = false
  @Published var confirming: String?
  @Published var status = ""
  private var timer: Timer?

  var active = false {
    didSet {
      guard active != oldValue else { return }
      timer?.invalidate()
      guard active else { return }
      sample()
      timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.sample() }
      }
    }
  }

  var byCPU: [AppUsage] { apps.sorted { $0.cpu > $1.cpu }.prefix(5).map { $0 } }
  var byMemory: [AppUsage] { apps.sorted { $0.memory > $1.memory }.prefix(5).map { $0 } }

  /// Regular apps the user runs (never Molt, Finder or system processes) can be quit.
  func runningApp(_ usage: AppUsage) -> NSRunningApplication? {
    guard let path = usage.appPath else { return nil }
    return NSWorkspace.shared.runningApplications.first {
      $0.bundleURL?.path == path && $0.activationPolicy == .regular
        && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleIdentifier != "com.apple.finder"
    }
  }
  func icon(_ usage: AppUsage) -> NSImage? { usage.appPath.map { NSWorkspace.shared.icon(forFile: $0) } }
  func quit(_ usage: AppUsage) {
    confirming = nil
    guard let app = runningApp(usage) else { return }
    status = app.terminate() ? "Asked \(usage.name) to quit. It may ask to save first." : "\(usage.name) didn't quit."
    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); sample() }
  }

  /// Molt's one best suggestion for the current section.
  func suggestion(health: [String: Double]) -> (text: String, action: String, target: AppUsage?)? {
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleURL?.path
    let background = apps.filter { runningApp($0) != nil && $0.appPath != frontmost }
    switch section {
    case .cpu:
      if let busy = background.max(by: { $0.cpu < $1.cpu }), busy.cpu > 40 {
        return ("\(busy.name) is using \(Int(busy.cpu))% CPU in the background. Quitting it cools things down.", "Quit \(busy.name)", busy)
      }
    case .memory:
      let used = health["memoryUsed"] ?? 0, pressure = health["memoryPressure"] ?? 0
      if (used > 0.8 || pressure >= 0.5), let big = background.max(by: { $0.memory < $1.memory }), big.memory > 500_000_000 {
        return ("Memory is tight. \(big.name) is holding \(Self.bytes(Int64(big.memory))). Quitting it frees that up.", "Quit \(big.name)", big)
      }
    case .battery:
      if !battery.onPower, (health["batteryLevel"] ?? 1) < 0.25 {
        return ("Battery is low. Low Power Mode stretches it further, and Molt can switch to low-impact mode.", "Battery settings", nil)
      }
      if let busy = background.max(by: { $0.cpu < $1.cpu }), busy.cpu > 25, !battery.onPower {
        return ("\(busy.name) is draining battery in the background.", "Quit \(busy.name)", busy)
      }
    case .storage:
      if let trash = folders.first(where: { $0.action == "empty" }), let size = trash.size, size > 500_000_000 {
        return ("Your Trash holds \(Self.bytes(size)). Emptying it frees that space.", "Empty Trash", nil)
      }
      if let build = folders.first(where: { $0.action == "clear" }), let size = build.size, size > 1_000_000_000 {
        return ("Xcode build data takes \(Self.bytes(size)). It rebuilds itself when needed.", "Clear build data", nil)
      }
    }
    return nil
  }
  func openBatterySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
  }

  // MARK: Sampling

  private func sample() {
    Task {
      let output = await QuickActions.output("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="])
      apps = ProcessTable.group(ProcessTable.parse(output))
      battery = Self.readBattery()
    }
  }
  private static func readBattery() -> Battery {
    var result = Battery()
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    if service != 0 {
      defer { IOObjectRelease(service) }
      func value(_ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
      }
      let design = value("DesignCapacity")
      let maximum = value("AppleRawMaxCapacity") ?? value("MaxCapacity")
      if let design, let maximum, design > 0, maximum > 100 { result.health = min(1, Double(maximum) / Double(design)) }
      result.cycles = value("CycleCount")
      result.temperature = value("Temperature").map { Double($0) / 100 }
      result.charging = value("IsCharging") == 1
      result.onPower = value("ExternalConnected") == 1
      if let minutes = value("TimeRemaining"), minutes > 0, minutes < 65535 { result.minutesLeft = minutes }
      if let adapter = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
        result.watts = (adapter["Watts"] as? NSNumber)?.intValue
      }
    }
    return result
  }

  // MARK: Storage

  /// Measures common space hogs. Runs only when you ask, since some folders need permission.
  func scanStorage() {
    guard !scanning else { return }
    scanning = true
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates: [Folder] = [
      Folder(name: "Trash", path: home.appendingPathComponent(".Trash").path, symbol: "trash.fill", action: "empty"),
      Folder(name: "Downloads", path: home.appendingPathComponent("Downloads").path, symbol: "arrow.down.circle.fill"),
      Folder(name: "Desktop", path: home.appendingPathComponent("Desktop").path, symbol: "menubar.dock.rectangle"),
      Folder(name: "Documents", path: home.appendingPathComponent("Documents").path, symbol: "doc.fill"),
      Folder(name: "Movies", path: home.appendingPathComponent("Movies").path, symbol: "film.fill"),
      Folder(name: "App caches", path: home.appendingPathComponent("Library/Caches").path, symbol: "shippingbox.fill"),
      Folder(name: "Xcode build data", path: home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path, symbol: "hammer.fill", action: "clear"),
      Folder(name: "iOS simulators", path: home.appendingPathComponent("Library/Developer/CoreSimulator/Devices").path, symbol: "iphone"),
    ].filter { FileManager.default.fileExists(atPath: $0.path) }
    folders = candidates
    Task {
      await withTaskGroup(of: (String, Int64).self) { group in
        for folder in candidates {
          group.addTask { (folder.path, await Self.size(of: folder.path)) }
        }
        for await (path, size) in group {
          if let index = folders.firstIndex(where: { $0.path == path }) { folders[index].size = size }
        }
      }
      folders.sort { ($0.size ?? 0) > ($1.size ?? 0) }
      scanning = false
    }
  }
  func reveal(_ folder: Folder) { NSWorkspace.shared.open(URL(fileURLWithPath: folder.path)) }
  func perform(_ action: String) {
    confirming = nil
    switch action {
    case "empty":
      Task.detached {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        let emptied = error == nil
        await MainActor.run { self.status = emptied ? "Trash emptied." : "Finder didn't allow emptying the Trash."; self.scanStorage() }
      }
    case "clear":
      // Moved to the Trash, so it can be recovered until the Trash is emptied.
      guard let folder = folders.first(where: { $0.action == "clear" }) else { return }
      let url = URL(fileURLWithPath: folder.path)
      let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
      var moved = 0
      for item in items where (try? FileManager.default.trashItem(at: item, resultingItemURL: nil)) != nil { moved += 1 }
      status = "Moved \(moved) build folders to the Trash."
      scanStorage()
    default: break
    }
  }
  nonisolated private static func size(of path: String) async -> Int64 {
    await Task.detached(priority: .utility) { () -> Int64 in
      let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
      guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
      else { return 0 }
      var total: Int64 = 0, count = 0
      let deadline = Date().addingTimeInterval(20)
      for case let url as URL in enumerator {
        count += 1
        if count % 2000 == 0, Date() > deadline { break }
        if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
          total += Int64(values.totalFileAllocatedSize ?? 0)
        }
      }
      return total
    }.value
  }
  static func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
}

struct HealthDetailView: View {
  @ObservedObject var detail: HealthDetailController
  @ObservedObject var controller: PetController
  var body: some View {
    let health = controller.health.values
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 4) {
          ForEach(HealthDetailController.Section.allCases, id: \.self) { section in
            Button { detail.section = section; if section == .storage && detail.folders.isEmpty { detail.scanStorage() } } label: {
              Text(section.rawValue).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(detail.section == section ? Color.white : Color.white.opacity(0.45))
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(detail.section == section ? 0.14 : 0)))
                .contentShape(Capsule())
            }.buttonStyle(.plain)
          }
          Spacer()
          Text(headline(health)).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        ScrollView { list(health) }
      }
      advice(health).frame(width: 220)
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
    .onAppear { detail.active = true; controller.refreshHealth() }
    .onDisappear { detail.active = false }
  }

  private func headline(_ health: [String: Double]) -> String {
    switch detail.section {
    case .cpu: return health["cpuLoad"].map { "\(Int($0 * 100))% in use" } ?? ""
    case .memory: return health["memoryUsed"].map { "\(Int($0 * 100))% used" } ?? ""
    case .battery: return health["batteryLevel"].map { "\(Int($0 * 100))%\(detail.battery.charging ? " · charging" : "")" } ?? "No battery"
    case .storage: return health["diskFreeRatio"].map { "\(Int($0 * 100))% free" } ?? ""
    }
  }
  @ViewBuilder private func list(_ health: [String: Double]) -> some View {
    switch detail.section {
    case .cpu, .memory:
      let rows = detail.section == .cpu ? detail.byCPU : detail.byMemory
      VStack(spacing: 4) {
        ForEach(rows) { usage in appRow(usage) }
        if rows.isEmpty { ProgressView().controlSize(.small).padding() }
      }
    case .battery:
      let b = detail.battery
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
        stat("Health", b.health.map { "\(Int($0 * 100))%" } ?? "n/a", "heart.fill")
        stat("Cycles", b.cycles.map(String.init) ?? "n/a", "arrow.triangle.2.circlepath")
        stat("Temperature", b.temperature.map { String(format: "%.0f°C", $0) } ?? "n/a", "thermometer.medium")
        stat("Power", b.onPower ? (b.watts.map { "\($0) W adapter" } ?? "Plugged in") : "On battery", "powerplug.fill")
        stat(b.charging ? "Until full" : "Time left", b.minutesLeft.map { "\($0 / 60)h \($0 % 60)m" } ?? "Estimating", "clock.fill")
        stat("Top drain", detail.byCPU.first?.name ?? "n/a", "bolt.fill")
      }
    case .storage:
      VStack(spacing: 4) {
        ForEach(detail.folders) { folder in
          HStack(spacing: 8) {
            Image(systemName: folder.symbol).font(.system(size: 12)).foregroundStyle(Color.accentColor).frame(width: 18)
            Text(folder.name).font(.system(size: 12))
            Spacer()
            Text(folder.size.map(HealthDetailController.bytes) ?? "…").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            Button { detail.reveal(folder) } label: { Image(systemName: "folder").font(.system(size: 10, weight: .semibold)) }
              .buttonStyle(NotchIconButtonStyle(size: 22)).help("Show in Finder").accessibilityLabel("Show \(folder.name) in Finder")
          }
        }
        if detail.scanning { Text("Measuring…").font(.system(size: 10)).foregroundStyle(.secondary) }
      }
    }
  }
  private func appRow(_ usage: AppUsage) -> some View {
    let quittable = detail.runningApp(usage) != nil
    let value = detail.section == .cpu ? min(1, usage.cpu / 100) : min(1, Double(usage.memory) / Double(ProcessInfo.processInfo.physicalMemory))
    return HStack(spacing: 8) {
      if let icon = detail.icon(usage) {
        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
      } else {
        Image(systemName: "gearshape.2").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 18)
      }
      Text(usage.name).font(.system(size: 12)).lineLimit(1).frame(width: 150, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.1))
          Capsule().fill(Color.accentColor).frame(width: proxy.size.width * value)
        }
      }.frame(height: 4)
      Text(detail.section == .cpu ? "\(Int(usage.cpu))%" : HealthDetailController.bytes(Int64(usage.memory)))
        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      if detail.confirming == usage.id {
        Button("Quit") { detail.quit(usage) }.foregroundStyle(.red)
        Button { detail.confirming = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
          .buttonStyle(NotchIconButtonStyle(size: 20)).accessibilityLabel("Keep running")
      } else {
        Button { detail.confirming = usage.id } label: { Image(systemName: "xmark.circle").font(.system(size: 12)) }
          .buttonStyle(NotchIconButtonStyle(size: 22)).opacity(quittable ? 1 : 0).disabled(!quittable)
          .help("Quit \(usage.name)").accessibilityLabel("Quit \(usage.name)")
      }
    }
  }
  private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
      Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).lineLimit(1)
    }
  }
  private func advice(_ health: [String: Double]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Molt's advice", systemImage: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      if let tip = detail.suggestion(health: health) {
        Text(tip.text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        if detail.confirming == "advice" {
          HStack {
            Button("Yes, \(tip.action.lowercased())") { runAdvice(tip) }
            Button("Cancel") { detail.confirming = nil }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
          }
        } else {
          Button(tip.action) {
            if tip.action == "Battery settings" { detail.openBatterySettings() } else { detail.confirming = "advice" }
          }
        }
      } else {
        Text(detail.section == .storage && detail.folders.isEmpty ? "Measure your biggest folders to find space." : "Everything looks healthy.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
        if detail.section == .storage { Button(detail.scanning ? "Measuring…" : "Measure", action: detail.scanStorage).disabled(detail.scanning) }
      }
      Spacer(minLength: 0)
      HStack {
        Text("Low-impact Molt").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8))
        Spacer()
        Toggle("Low-impact Molt", isOn: Binding(
          get: { controller.companion.preferences.reducedMotion },
          set: { value in controller.changeCompanion { $0.preferences.reducedMotion = value } }))
          .labelsHidden().toggleStyle(.switch).controlSize(.mini)
      }.help("Stops Molt's animations to save energy")
      if !detail.status.isEmpty { Text(detail.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
    }
    .padding(12).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
  }
  private func runAdvice(_ tip: (text: String, action: String, target: AppUsage?)) {
    if let target = tip.target { detail.quit(target); return }
    detail.perform(tip.action == "Empty Trash" ? "empty" : "clear")
  }
}
