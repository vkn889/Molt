import Foundation
import MoltCore
import SwiftUI

@MainActor final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
  @Published var progress: Double = 0
  @Published var busy = false
  @Published var message = "Optional compact model: 491 MB download, Apache 2.0. Limited reasoning quality."
  @Published var installed = false
  let modelURL: URL
  let executable: URL
  private var session: URLSession?
  private var download: URLSessionDownloadTask?
  init(directory: URL) {
    modelURL = directory.appendingPathComponent("Models/\(ManagedModel.filename)")
    #if arch(arm64)
    let arch = "arm64"
    #else
    let arch = "x64"
    #endif
    let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    executable = resources.appendingPathComponent("Runtime/\(arch)/llama-completion")
    super.init()
    installed = FileManager.default.fileExists(atPath: modelURL.path)
  }
  var runtimeAvailable: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }
  var provider: ManagedLocalProvider { ManagedLocalProvider(executable: executable, modelURL: modelURL) }
  func install() {
    guard !busy, runtimeAvailable else { message = "This build does not contain the managed runtime. Use a packaged Molt build or optional Ollama."; return }
    do {
      try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let space = try modelURL.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      guard (space.volumeAvailableCapacityForImportantUsage ?? 0) > ManagedModel.bytes * 3,
        ProcessInfo.processInfo.physicalMemory >= 4_000_000_000 else {
        message = "The compact model needs at least 4 GB RAM and 1.5 GB available storage during installation."; return
      }
      busy = true; progress = 0; message = "Downloading the pinned compact model. Cancel is available."
      let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 1800
      session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
      download = session?.downloadTask(with: ManagedModel.download); download?.resume()
    } catch { message = error.localizedDescription }
  }
  func cancel() { download?.cancel() }
  func uninstall() {
    guard !busy else { return }
    do { if installed { try FileManager.default.removeItem(at: modelURL) }; installed = false; message = "Model removed. Pet, organization data, and memory are preserved." }
    catch { message = error.localizedDescription }
  }
  nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    Task { @MainActor in self.progress = min(1, Double(totalBytesWritten) / Double(ManagedModel.bytes)) }
  }
  nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("molt-model-\(UUID()).gguf")
    do {
      guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw InferenceError.unavailable }
      try FileManager.default.moveItem(at: location, to: staging)
      try ManagedModel.verify(staging)
      Task { @MainActor in
        defer { try? FileManager.default.removeItem(at: staging); self.finish() }
        do {
          if FileManager.default.fileExists(atPath: self.modelURL.path) {
            _ = try FileManager.default.replaceItemAt(self.modelURL, withItemAt: staging)
          } else { try FileManager.default.moveItem(at: staging, to: self.modelURL) }
          self.installed = true; self.message = "Model verified and installed. Choose Managed local and connect to run a readiness request."
        } catch { self.message = error.localizedDescription }
      }
    } catch {
      try? FileManager.default.removeItem(at: staging)
      Task { @MainActor in self.message = error.localizedDescription; self.finish() }
    }
  }
  nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error else { return }
    Task { @MainActor in self.message = error.localizedDescription; self.finish() }
  }
  private func finish() { busy = false; download = nil; session?.finishTasksAndInvalidate(); session = nil }
}
