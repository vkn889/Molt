import Foundation

/// `Molt --cloud-selftest <emailA> <passwordA> <emailB> <passwordB>` exercises the realtime
/// client end to end: lobby presence, a hangout invite delivered as a database change, and a
/// position broadcast between two Molts. Nothing is stored on this Mac.
@MainActor enum CloudSelfTest {
  static func run(emailA: String, passwordA: String, emailB: String, passwordB: String) async -> Bool {
    guard let a = await signIn(emailA, passwordA), let b = await signIn(emailB, passwordB) else {
      print("FAIL sign in"); return false
    }
    var passed = true
    func check(_ label: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + label); passed = passed && ok }
    let socketA = RealtimeSocket { a.token }, socketB = RealtimeSocket { b.token }

    let lobbyA = socketA.channel("lobby", presenceKey: a.id)
    let lobbyB = socketB.channel("lobby", presenceKey: b.id)
    var seenA = false
    lobbyB.onPresence = { state in if state[a.id]?["username"] as? String == "selftest_a" { seenA = true } }
    lobbyA.track(["username": "selftest_a"])
    lobbyA.join()
    lobbyB.track(["username": "selftest_b"])
    lobbyB.join()
    check("lobby presence", await wait { seenA })

    var invitedID: String?
    let inbox = socketB.channel("user:\(b.id)", changes: [["event": "INSERT", "schema": "public", "table": "hangouts", "filter": "guest=eq.\(b.id)"]])
    var inboxJoined = false
    inbox.onJoin = { ok, _ in inboxJoined = ok }
    inbox.onChange = { data in invitedID = (data["record"] as? [String: Any])?["id"] as? String }
    inbox.join()
    check("inbox subscription", await wait { inboxJoined })
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    _ = await request("POST", "/rest/v1/friendships", ["requester": a.id, "addressee": b.id], token: a.token)
    _ = await request("PATCH", "/rest/v1/friendships?requester=eq.\(a.id)&addressee=eq.\(b.id)", ["status": "accepted"], token: b.token)
    let created = await request("POST", "/rest/v1/hangouts?select=id", ["host": a.id, "guest": b.id], token: a.token, prefer: "return=representation")
    let hangout = ((try? JSONSerialization.jsonObject(with: created)) as? [[String: Any]])?.first?["id"] as? String ?? ""
    check("invite delivered", await wait { invitedID == hangout && !hangout.isEmpty })

    _ = await request("POST", "/rest/v1/rpc/accept_hangout", ["hangout": hangout], token: b.token)
    let roomA = socketA.channel("hangout:\(hangout)"), roomB = socketB.channel("hangout:\(hangout)")
    var joinedA = false, joinedB = false, received: Double?
    roomA.onJoin = { ok, _ in joinedA = ok }
    roomB.onJoin = { ok, _ in joinedB = ok }
    roomB.onBroadcast = { event, payload in if event == "pos" { received = payload["x"] as? Double } }
    roomA.join()
    roomB.join()
    check("both join the playground", await wait { joinedA && joinedB })
    try? await Task.sleep(nanoseconds: 500_000_000)
    roomA.broadcast("pos", ["x": 0.42, "y": 0.5])
    check("position broadcast", await wait { received == 0.42 })

    _ = await request("POST", "/rest/v1/rpc/end_hangout", ["hangout": hangout], token: a.token)
    _ = await request("DELETE", "/rest/v1/friendships?requester=eq.\(a.id)&addressee=eq.\(b.id)", nil, token: a.token)
    socketA.disconnect()
    socketB.disconnect()
    return passed
  }
  private struct Session { var id: String; var token: String }
  private static func signIn(_ email: String, _ password: String) async -> Session? {
    let data = await request("POST", "/auth/v1/token?grant_type=password", ["email": email, "password": password], token: nil)
    guard let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let token = row["access_token"] as? String,
      let id = (row["user"] as? [String: Any])?["id"] as? String
    else { return nil }
    return Session(id: id, token: token)
  }
  private static func request(_ method: String, _ path: String, _ body: [String: Any]?, token: String?, prefer: String? = nil) async -> Data {
    var request = URLRequest(url: URL(string: MoltCloud.url.absoluteString + path)!)
    request.httpMethod = method
    request.setValue(MoltCloud.key, forHTTPHeaderField: "apikey")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
    if let body {
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return (try? await URLSession.shared.data(for: request).0) ?? Data()
  }
  private static func wait(_ seconds: Double = 12, until: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if until() { return true }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    return until()
  }
}
