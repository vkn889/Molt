import CryptoKit
import Darwin
import Foundation

public enum ManagedModel {
  public static let id = "qwen2.5-0.5b-instruct-q4_k_m"
  public static let filename = id + ".gguf"
  public static let bytes: Int64 = 491_400_032
  public static let sha256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
  public static let download = URL(
    string:
      "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/\(filename)"
  )!
  public static func verify(_ url: URL) throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    var size: Int64 = 0
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hash.update(data: data)
      size += Int64(data.count)
    }
    guard size == bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256
    else {
      throw MoltError.invalid("Model integrity check failed. The previous model is preserved.")
    }
  }
}
private final class WorkerControl: @unchecked Sendable {
  let lock = NSLock()
  var process: Process?
  var canceled = false
  func start(_ process: Process) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !canceled else { throw CancellationError() }
    self.process = process
    try process.run()
  }
  func stop() {
    lock.lock()
    defer { lock.unlock() }
    canceled = true
    if let process, process.isRunning {
      process.terminate()
      DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      }
    }
  }
}
/// One bounded child process per request. No listening socket and no shell evaluation.
public final class ManagedLocalProvider: InferenceProvider, @unchecked Sendable {
  public let executable: URL
  public let modelURL: URL
  public init(executable: URL, modelURL: URL) {
    self.executable = executable
    self.modelURL = modelURL
  }
  public func models() async throws -> [LocalModel] {
    guard FileManager.default.isExecutableFile(atPath: executable.path),
      FileManager.default.fileExists(atPath: modelURL.path)
    else {
      throw MoltError.invalid("Install the managed model in a runtime-equipped Molt build first.")
    }
    return [LocalModel(id: ManagedModel.id, bytes: ManagedModel.bytes)]
  }
  public func unload(model: String) async throws
  { /* Each completed worker exits and releases its model. */  }
  public func stream(model: String, messages: [InferenceMessage]) -> AsyncThrowingStream<
    String, Error
  > {
    AsyncThrowingStream { continuation in
      let control = WorkerControl()
      let deadline = DispatchWorkItem { control.stop() }
      DispatchQueue.global(qos: .userInitiated).async {
        let input = Pipe()
        let output = Pipe()
        let process = Process()
        defer {
          deadline.cancel()
          try? input.fileHandleForWriting.close()
          try? output.fileHandleForReading.close()
        }
        do {
          guard model == ManagedModel.id else { throw InferenceError.unsupported }
          guard !messages.contains(where: { !($0.images ?? []).isEmpty }) else {
            throw InferenceError.server(
              "The compact managed model cannot see images. Choose a local Ollama vision model or share the screen's extracted text."
            )
          }
          // Revalidate integrity before launch, including imported or externally edited files.
          try ManagedModel.verify(self.modelURL)
          let prompt =
            messages.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined()
            + "<|im_start|>assistant\n"
          guard prompt.utf8.count <= 40_000 else {
            throw MoltError.invalid("Shorten the supplied context and try again.")
          }
          process.executableURL = self.executable
          process.arguments = [
            "-m", self.modelURL.path, "-f", "/dev/stdin", "-n", "512", "-c", "4096",
            "--no-conversation", "--no-display-prompt", "--color", "off", "--simple-io", "--temp",
            "0.3",
          ]
          process.standardInput = input
          process.standardOutput = output
          process.standardError = FileHandle.nullDevice
          try control.start(process)
          DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: deadline)
          try input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
          try input.fileHandleForWriting.close()
          var pending = Data()
          var count = 0
          while let data = try output.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {
            pending.append(data)
            count += data.count
            guard count <= 256_000 else {
              control.stop()
              throw InferenceError.malformed
            }
            if let text = String(data: pending, encoding: .utf8) {
              continuation.yield(text)
              pending.removeAll(keepingCapacity: true)
            }
          }
          process.waitUntilExit()
          guard process.terminationStatus == 0 else {
            throw MoltError.invalid(
              "Local worker stopped or failed. Your companion and saves are unaffected.")
          }
          if !pending.isEmpty || count == 0 { throw InferenceError.malformed }
          continuation.finish()
        } catch {
          control.stop()
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in control.stop() }
    }
  }
}
