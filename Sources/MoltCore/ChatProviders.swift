import Foundation

/// Where Chat and Lens send messages. Ollama and LM Studio stay on this Mac; the others are
/// cloud services that receive your messages and need your own key.
public struct ChatService: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var base: String
  public var local: Bool
  public var needsKey: Bool
  public var keyHint: String
  public static let all: [ChatService] = [
    ChatService(id: "ollama", name: "Ollama", base: "http://127.0.0.1:11434", local: true, needsKey: false, keyHint: ""),
    ChatService(id: "lmstudio", name: "LM Studio", base: "http://127.0.0.1:1234/v1", local: true, needsKey: false, keyHint: ""),
    ChatService(id: "anthropic", name: "Anthropic", base: "https://api.anthropic.com/v1", local: false, needsKey: true, keyHint: "sk-ant-…"),
    ChatService(id: "openai", name: "OpenAI", base: "https://api.openai.com/v1", local: false, needsKey: true, keyHint: "sk-…"),
    ChatService(id: "google", name: "Google", base: "https://generativelanguage.googleapis.com/v1beta/openai", local: false, needsKey: true, keyHint: "AIza…"),
    ChatService(id: "openrouter", name: "OpenRouter", base: "https://openrouter.ai/api/v1", local: false, needsKey: true, keyHint: "sk-or-…"),
  ]
  public static func find(_ id: String) -> ChatService? { all.first { $0.id == id } }
}

private func readLines(_ bytes: URLSession.AsyncBytes, limit: Int, _ handle: (String) throws -> Bool) async throws {
  var count = 0
  for try await line in bytes.lines {
    try Task.checkCancellation()
    count += line.utf8.count
    guard count <= limit else { throw InferenceError.malformed }
    if try handle(line) { return }
  }
}

private func failure(_ data: Data, status: Int, service: String) -> InferenceError {
  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  let message = (row?["error"] as? [String: Any])?["message"] as? String ?? row?["error"] as? String
  if status == 401 || status == 403 { return .server("\(service) didn't accept the key. Check it in Settings.") }
  if status == 429 { return .server("\(service) is rate limiting you. Try again in a moment.") }
  return .server(message.map { "\(service): \(String($0.prefix(300)))" } ?? "\(service) is unavailable (\(status)).")
}

/// Any server speaking OpenAI's chat completions format: LM Studio, OpenAI, Google and OpenRouter.
public final class OpenAICompatibleProvider: InferenceProvider, @unchecked Sendable {
  public let service: ChatService
  private let key: String?
  private let session: URLSession
  public init(service: ChatService, key: String?) {
    self.service = service
    self.key = key
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 300
    session = URLSession(configuration: config)
  }
  private func request(_ path: String, body: Data? = nil) -> URLRequest {
    var request = URLRequest(url: URL(string: service.base + path)!)
    request.httpMethod = body == nil ? "GET" : "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    if service.id == "openrouter" { request.setValue("Molt", forHTTPHeaderField: "X-Title") }
    return request
  }
  public func models() async throws -> [LocalModel] {
    let data: Data, response: URLResponse
    do { (data, response) = try await session.data(for: request("/models")) } catch {
      throw service.local ? InferenceError.server("\(service.name) isn't running. Start its local server, then refresh.") : error
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw failure(data, status: status, service: service.name) }
    return Self.parseModels(data, service: service.id)
  }
  public static func parseModels(_ data: Data, service: String) -> [LocalModel] {
    guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = row["data"] as? [[String: Any]] else { return [] }
    let skip = ["embed", "whisper", "tts", "dall-e", "image", "audio", "moderation", "realtime", "transcribe"]
    return list.compactMap { $0["id"] as? String }
      .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
      .filter { id in !skip.contains { id.lowercased().contains($0) } }
      .prefix(300).map { LocalModel(id: $0, bytes: 0) }
  }
  public func stream(model: String, messages: [InferenceMessage]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let body = try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
          ])
          let (bytes, response) = try await session.bytes(for: request("/chat/completions", body: body))
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count > 20_000 { break } }
            throw failure(data, status: status, service: service.name)
          }
          try await readLines(bytes, limit: 4_000_000) { line in
            guard let chunk = try Self.decode(line) else { return false }
            if !chunk.text.isEmpty { continuation.yield(chunk.text) }
            return chunk.done
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }
  /// One server-sent event line. Returns nil for lines that carry nothing.
  public static func decode(_ line: String) throws -> (text: String, done: Bool)? {
    guard line.hasPrefix("data:") else { return nil }
    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if payload == "[DONE]" { return ("", true) }
    guard let row = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return nil }
    if let error = row["error"] as? [String: Any] { throw InferenceError.server(String((error["message"] as? String ?? "The service failed.").prefix(300))) }
    let choice = (row["choices"] as? [[String: Any]])?.first
    let text = (choice?["delta"] as? [String: Any])?["content"] as? String ?? ""
    return (text, false)
  }
  public func unload(model: String) async throws {}
}

/// Claude, through Anthropic's Messages API with your API key.
public final class AnthropicProvider: InferenceProvider, @unchecked Sendable {
  public static let defaultModels = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"]
  private let key: String
  private let session: URLSession
  private let base = "https://api.anthropic.com/v1"
  public init(key: String) {
    self.key = key
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 120
    config.timeoutIntervalForResource = 600
    session = URLSession(configuration: config)
  }
  private func request(_ path: String, body: Data? = nil, fallback: Bool = false) -> URLRequest {
    var request = URLRequest(url: URL(string: base + path)!)
    request.httpMethod = body == nil ? "GET" : "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    if fallback { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
    return request
  }
  public func models() async throws -> [LocalModel] {
    let (data, response) = try await session.data(for: request("/models?limit=100"))
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw failure(data, status: status, service: "Anthropic") }
    let listed = OpenAICompatibleProvider.parseModels(data, service: "anthropic").map(\.id)
    // Current models first, then anything else the account can use.
    let ordered = Self.defaultModels.filter { listed.isEmpty || listed.contains($0) } + listed.filter { !Self.defaultModels.contains($0) }
    return ordered.map { LocalModel(id: $0, bytes: 0) }
  }
  public static func body(model: String, messages: [InferenceMessage]) -> [String: Any] {
    let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
    var turns: [[String: Any]] = []
    for message in messages where message.role != "system" {
      let role = message.role == "assistant" ? "assistant" : "user"
      // The API needs alternating turns; merge consecutive messages from the same side.
      if var last = turns.last, last["role"] as? String == role {
        last["content"] = (last["content"] as? String ?? "") + "\n\n" + message.content
        turns[turns.count - 1] = last
      } else {
        turns.append(["role": role, "content": message.content])
      }
    }
    var body: [String: Any] = ["model": model, "max_tokens": 16000, "stream": true, "messages": turns]
    if !system.isEmpty { body["system"] = system }
    // On a policy decline, the API retries on a suitable fallback model within the same call.
    if supportsFallback(model) { body["fallbacks"] = "default" }
    return body
  }
  static func supportsFallback(_ model: String) -> Bool {
    ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
  }
  public func stream(model: String, messages: [InferenceMessage]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let payload = try JSONSerialization.data(withJSONObject: Self.body(model: model, messages: messages))
          let (bytes, response) = try await session.bytes(for: request("/messages", body: payload, fallback: Self.supportsFallback(model)))
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count > 20_000 { break } }
            throw failure(data, status: status, service: "Anthropic")
          }
          try await readLines(bytes, limit: 4_000_000) { line in
            guard let event = try Self.decode(line) else { return false }
            if !event.text.isEmpty { continuation.yield(event.text) }
            return event.done
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }
  /// One `data:` line of the Messages stream: text deltas, the stop, refusals and errors.
  public static func decode(_ line: String) throws -> (text: String, done: Bool)? {
    guard line.hasPrefix("data:"),
      let row = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)) as? [String: Any],
      let type = row["type"] as? String
    else { return nil }
    switch type {
    case "content_block_delta":
      let delta = row["delta"] as? [String: Any]
      return (delta?["type"] as? String == "text_delta" ? delta?["text"] as? String ?? "" : "", false)
    case "message_delta":
      if (row["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
        throw InferenceError.server("Claude declined to answer this one.")
      }
      return nil
    case "message_stop": return ("", true)
    case "error":
      throw InferenceError.server(String(((row["error"] as? [String: Any])?["message"] as? String ?? "Anthropic failed.").prefix(300)))
    default: return nil
    }
  }
  public func unload(model: String) async throws {}
}
