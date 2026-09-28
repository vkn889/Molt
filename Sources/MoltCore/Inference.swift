import Foundation

public struct InferenceMessage: Codable, Sendable, Equatable {
  public var role: String
  public var content: String
  public init(role: String, content: String) { self.role = role; self.content = content }
}
public struct LocalModel: Identifiable, Sendable, Equatable {
  public var id: String
  public var bytes: Int64
  public init(id: String, bytes: Int64) { self.id = id; self.bytes = bytes }
}
public protocol InferenceProvider: Sendable {
  func models() async throws -> [LocalModel]
  func stream(model: String, messages: [InferenceMessage]) -> AsyncThrowingStream<String, Error>
  func unload(model: String) async throws
}
public enum InferenceError: LocalizedError {
  case unavailable, remoteModel, unsupported, malformed, server(String)
  public var errorDescription: String? {
    switch self {
    case .unavailable: return "Ollama is unavailable. Start the local Ollama app, then refresh models. Your companion still works."
    case .remoteModel: return "This model uses a remote service. Molt only permits local models."
    case .unsupported: return "This model does not support text completion. Choose a local chat model."
    case .malformed: return "The model returned an incomplete or invalid response. Please retry."
    case .server(let message): return message
    }
  }
}
// Do not follow redirects from the loopback service to an external provider.
private final class LocalOnlyRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public final class OllamaProvider: InferenceProvider, @unchecked Sendable {
  private let session: URLSession
  private let base = URL(string: "http://127.0.0.1:11434/api/")!
  public init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 45
    config.timeoutIntervalForResource = 180
    config.connectionProxyDictionary = [:]
    session = URLSession(configuration: config, delegate: LocalOnlyRedirects(), delegateQueue: nil)
  }
  private func request(_ path: String, body: Data? = nil) -> URLRequest {
    var request = URLRequest(url: base.appendingPathComponent(path))
    request.httpMethod = body == nil ? "GET" : "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }
  private func data(_ path: String, body: Data? = nil) async throws -> Data {
    let (data, response) = try await session.data(for: request(path, body: body))
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InferenceError.unavailable }
    return data
  }
  public func models() async throws -> [LocalModel] {
    struct Listing: Decodable {
      struct Entry: Decodable { var name: String; var size: Int64 }
      var models: [Entry]
    }
    do {
      return try JSONDecoder().decode(Listing.self, from: await data("tags")).models
        .filter { !$0.name.lowercased().contains("cloud") }
        .map { LocalModel(id: $0.name, bytes: $0.size) }
    } catch is CancellationError { throw CancellationError() }
    catch { throw InferenceError.unavailable }
  }
  public static func validateMetadata(_ data: Data, name: String) throws {
    guard !name.lowercased().contains("cloud"),
      let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw InferenceError.remoteModel
    }
    for key in ["remote_host", "remote_model"] {
      if let value = metadata[key] as? String, !value.isEmpty { throw InferenceError.remoteModel }
    }
    guard let capabilities = metadata["capabilities"] as? [String], capabilities.contains("completion") else {
      throw InferenceError.unsupported
    }
  }
  public func stream(model: String, messages: [InferenceMessage]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let body = try JSONSerialization.data(withJSONObject: ["model": model])
          try Self.validateMetadata(await data("show", body: body), name: model)
          struct Chat: Encodable {
            var model: String; var messages: [InferenceMessage]
            var stream = true; var keep_alive = "2m"
            var options = ["num_predict": 1024, "num_ctx": 4096]
          }
          let encoded = try JSONEncoder().encode(Chat(model: model, messages: messages))
          let (bytes, response) = try await session.bytes(for: request("chat", body: encoded))
          guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InferenceError.unavailable }
          var count = 0
          for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            count += line.utf8.count
            guard count <= 1_000_000 else { throw InferenceError.malformed }
            let chunk = try Self.decodeChunk(Data(line.utf8))
            if !chunk.text.isEmpty { continuation.yield(chunk.text) }
            if chunk.done { continuation.finish(); return }
          }
          throw InferenceError.malformed
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }
  public static func decodeChunk(_ data: Data) throws -> (text: String, done: Bool) {
    struct Chunk: Decodable { var message: InferenceMessage?; var done: Bool?; var error: String? }
    let chunk = try JSONDecoder().decode(Chunk.self, from: data)
    if let error = chunk.error { throw InferenceError.server(String(error.prefix(500))) }
    guard chunk.message != nil || chunk.done == true else { throw InferenceError.malformed }
    return (chunk.message?.content ?? "", chunk.done == true)
  }
  public func unload(model: String) async throws {
    _ = try await data("generate", body: JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0]))
  }
}
