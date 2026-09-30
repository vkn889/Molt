import Foundation

/// A small Supabase Realtime client (Phoenix protocol 1.0.0 over one WebSocket). Every channel
/// is private, so the server's row-level security decides who may join, listen and send.
@MainActor final class RealtimeSocket {
  private var task: URLSessionWebSocketTask?
  private var channels: [String: RealtimeChannel] = [:]
  private var reference = 0
  private var heartbeat: Timer?
  private var refreshTimer: Timer?
  private var retry = 0
  private var wanted = false
  let token: () async -> String?

  init(token: @escaping () async -> String?) { self.token = token }

  func channel(_ name: String, presenceKey: String? = nil, changes: [[String: String]] = []) -> RealtimeChannel {
    if let existing = channels["realtime:" + name] { return existing }
    let channel = RealtimeChannel(topic: "realtime:" + name, presenceKey: presenceKey, changes: changes, socket: self)
    channels[channel.topic] = channel
    return channel
  }
  func connect() {
    wanted = true
    guard task == nil else { return }
    var parts = URLComponents(url: MoltCloud.url, resolvingAgainstBaseURL: false)!
    parts.scheme = "wss"
    parts.path = "/realtime/v1/websocket"
    parts.queryItems = [.init(name: "apikey", value: MoltCloud.key), .init(name: "vsn", value: "1.0.0")]
    let task = URLSession.shared.webSocketTask(with: parts.url!)
    self.task = task
    task.resume()
    receive(task)
    heartbeat?.invalidate()
    heartbeat = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.push(topic: "phoenix", event: "heartbeat", payload: [:]) }
    }
    // Keep private channels open past token expiry.
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.sendToken() }
    }
    for channel in channels.values where channel.wanted { Task { await channel.sendJoin() } }
  }
  func disconnect() {
    wanted = false
    for channel in channels.values { channel.leave() }
    channels = [:]
    heartbeat?.invalidate()
    refreshTimer?.invalidate()
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
  }
  func remove(_ channel: RealtimeChannel) { channels[channel.topic] = nil }

  func nextReference() -> String {
    reference += 1
    return String(reference)
  }
  /// Sends one message. A join uses its own reference as its join reference.
  @discardableResult func push(topic: String, event: String, payload: [String: Any], joinRef: String? = nil) -> String {
    let ref = nextReference()
    var message: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": ref]
    if let joinRef = event == "phx_join" ? ref : joinRef { message["join_ref"] = joinRef }
    if let data = try? JSONSerialization.data(withJSONObject: message), let text = String(data: data, encoding: .utf8) {
      task?.send(.string(text)) { _ in }
    }
    return ref
  }
  private func sendToken() async {
    guard let token = await token() else { return }
    for channel in channels.values where channel.joined {
      push(topic: channel.topic, event: "access_token", payload: ["access_token": token], joinRef: channel.joinRef)
    }
  }
  private func receive(_ task: URLSessionWebSocketTask) {
    task.receive { [weak self] result in
      Task { @MainActor in
        guard let self, self.task === task else { return }
        switch result {
        case .success(let message):
          self.retry = 0
          if case .string(let text) = message { self.handle(text) }
          self.receive(task)
        case .failure:
          self.reconnect()
        }
      }
    }
  }
  private func handle(_ text: String) {
    guard let data = text.data(using: .utf8),
      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let topic = message["topic"] as? String, let event = message["event"] as? String
    else { return }
    channels[topic]?.receive(event: event, payload: message["payload"] as? [String: Any] ?? [:], ref: message["ref"] as? String)
  }
  /// Backs off 1, 2, 5, then 10 seconds, and rejoins every channel that is still wanted.
  private func reconnect() {
    task = nil
    for channel in channels.values { channel.joined = false }
    guard wanted else { return }
    let delay = [1.0, 2, 5, 10][min(retry, 3)]
    retry += 1
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      if self.wanted && self.task == nil { self.connect() }
    }
  }
}

@MainActor final class RealtimeChannel {
  let topic: String
  let presenceKey: String?
  /// Database changes to receive on this channel; the table's row-level security still applies.
  let changes: [[String: String]]
  private var attempts = 0
  private weak var socket: RealtimeSocket?
  fileprivate(set) var joinRef: String?
  fileprivate var joined = false
  fileprivate var wanted = false
  private var tracked: [String: Any]?
  /// Everyone present, keyed by presence key, with their latest metadata.
  private(set) var presence: [String: [String: Any]] = [:]
  var onBroadcast: ((String, [String: Any]) -> Void)?
  var onPresence: (([String: [String: Any]]) -> Void)?
  var onJoin: ((Bool, String?) -> Void)?
  var onChange: (([String: Any]) -> Void)?

  fileprivate init(topic: String, presenceKey: String?, changes: [[String: String]], socket: RealtimeSocket) {
    self.topic = topic
    self.presenceKey = presenceKey
    self.changes = changes
    self.socket = socket
  }
  func join() {
    wanted = true
    socket?.connect()
    Task { await sendJoin() }
  }
  fileprivate func sendJoin() async {
    guard let socket, !joined, let token = await socket.token() else { return }
    let config: [String: Any] = [
      "broadcast": ["ack": false, "self": false],
      "presence": ["enabled": presenceKey != nil, "key": presenceKey ?? ""],
      "postgres_changes": changes,
      "private": true,
    ]
    joinRef = socket.push(topic: topic, event: "phx_join", payload: ["config": config, "access_token": token], joinRef: nil)
  }
  func broadcast(_ event: String, _ payload: [String: Any] = [:]) {
    guard joined else { return }
    socket?.push(topic: topic, event: "broadcast", payload: ["type": "broadcast", "event": event, "payload": payload], joinRef: joinRef)
  }
  func track(_ meta: [String: Any]) {
    tracked = meta
    guard joined else { return }
    socket?.push(topic: topic, event: "presence", payload: ["type": "presence", "event": "track", "payload": meta], joinRef: joinRef)
  }
  func leave() {
    wanted = false
    if joined { socket?.push(topic: topic, event: "phx_leave", payload: [:], joinRef: joinRef) }
    joined = false
    presence = [:]
    socket?.remove(self)
  }
  fileprivate func receive(event: String, payload: [String: Any], ref: String?) {
    switch event {
    case "phx_reply" where ref == joinRef:
      let ok = payload["status"] as? String == "ok"
      let reason = (payload["response"] as? [String: Any])?["reason"] as? String
      joined = ok
      if ok {
        attempts = 0
        if let tracked { track(tracked) }
      } else if let reason, Self.transient.contains(where: reason.contains), wanted, attempts < 5 {
        // A fresh project or a busy database recovers on its own; try again shortly.
        attempts += 1
        let delay = [1.0, 2, 5, 10, 10][attempts - 1]
        Task { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)); await self.sendJoin() }
        return
      }
      onJoin?(ok, reason)
    case "postgres_changes":
      if let data = payload["data"] as? [String: Any] { onChange?(data) }
    case "broadcast":
      if let name = payload["event"] as? String { onBroadcast?(name, payload["payload"] as? [String: Any] ?? [:]) }
    case "presence_state":
      presence = [:]
      apply(joins: payload, leaves: [:])
    case "presence_diff":
      apply(joins: payload["joins"] as? [String: Any] ?? [:], leaves: payload["leaves"] as? [String: Any] ?? [:])
    case "phx_close", "phx_error":
      joined = false
      if wanted { Task { try? await Task.sleep(nanoseconds: 2_000_000_000); await self.sendJoin() } }
    default: break
    }
  }
  static let transient = [
    "MissingPartition", "InitializingProjectConnection", "IncreaseConnectionPool", "DatabaseLackOfConnections",
    "UnableToConnectToProject", "RealtimeRestarting", "Unknown Error on Channel",
  ]
  private func apply(joins: [String: Any], leaves: [String: Any]) {
    for key in leaves.keys { presence[key] = nil }
    for (key, value) in joins {
      if let meta = ((value as? [String: Any])?["metas"] as? [[String: Any]])?.last { presence[key] = meta }
    }
    onPresence?(presence)
  }
}
