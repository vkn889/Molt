import Darwin
import Foundation
import IOKit.ps
import MoltCore

final class SystemHealthMonitor: SystemHealthMonitoring {
  private var previousCPU: (Double, Double)?
  private var pressure: Double?
  private var source: DispatchSourceMemoryPressure?
  init() {
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical], queue: .main)
    source.setEventHandler { [weak self, weak source] in
      guard let data = source?.data else { return }
      self?.pressure = data.contains(.critical) ? 1 : data.contains(.warning) ? 0.5 : 0
    }
    source.resume()
    self.source = source
  }
  deinit { source?.cancel() }
  func currentSnapshot() -> SystemHealthSnapshot {
    var values: [String: Double] = [
      "uptimeHours": ProcessInfo.processInfo.systemUptime / 3600,
      "thermalState": Double(ProcessInfo.processInfo.thermalState.rawValue),
    ]
    values["memoryPressure"] = pressure
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    {
      for source in sources {
        guard
          let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
            as? [String: Any], let current = raw[kIOPSCurrentCapacityKey] as? Double,
          let max = raw[kIOPSMaxCapacityKey] as? Double, max > 0
        else { continue }
        values["batteryLevel"] = current / max
        values["isCharging"] = (raw[kIOPSIsChargingKey] as? Bool ?? false) ? 1 : 0
        break
      }
    }
    if let disk = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [
      .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
    ]), let free = disk.volumeAvailableCapacity, let total = disk.volumeTotalCapacity, total > 0 {
      values["diskFreeRatio"] = Double(free) / Double(total)
    }
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { p in
      p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    if result == KERN_SUCCESS {
      let ticks = info.cpu_ticks
      let busy = Double(ticks.0) + Double(ticks.1) + Double(ticks.3)
      let total = busy + Double(ticks.2)
      if let prior = previousCPU, total > prior.1, busy >= prior.0 {
        values["cpuLoad"] = min(1, (busy - prior.0) / (total - prior.1))
      }
      previousCPU = (busy, total)
    }
    var vm = vm_statistics64_data_t()
    var vmCount = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let vmResult = withUnsafeMutablePointer(to: &vm) { p in
      p.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
      }
    }
    let physical = Double(ProcessInfo.processInfo.physicalMemory)
    if vmResult == KERN_SUCCESS, physical > 0 {
      let used = Double(vm.active_count + vm.wire_count + vm.compressor_page_count) * Double(vm_kernel_page_size)
      values["memoryUsed"] = min(1, used / physical)
    }
    return SystemHealthSnapshot(values: values)
  }
}
