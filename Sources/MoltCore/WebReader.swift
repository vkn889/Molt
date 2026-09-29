import Darwin
import Foundation

public enum WebAccessPolicy {
  public static func validate(_ url: URL) throws {
    guard url.scheme == "https", url.user == nil, url.password == nil,
      url.port == nil || url.port == 443, let host = url.host?.lowercased(),
      host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
      !host.hasSuffix(".internal"), !host.hasSuffix(".test"), !host.contains(":"),
      host != "localhost", !host.hasSuffix(".localhost."), host != "metadata.google.internal"
    else {
      throw MoltError.invalid(
        "Choose a public HTTPS webpage, without credentials or a custom port.")
    }
    if host.allSatisfy({ $0.isNumber || $0 == "." }), !isPublicIPv4(host) {
      throw MoltError.invalid("Local and private network addresses cannot be read by Molting.")
    }
  }
  public static func isPublicIPv4(_ value: String) -> Bool {
    let parts = value.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
    let a = parts[0]
    let b = parts[1]
    return a != 0 && a != 10 && a != 127 && a < 224
      && !(a == 169 && b == 254) && !(a == 172 && (16...31).contains(b))
      && !(a == 192 && b == 168) && !(a == 100 && (64...127).contains(b))
      && !(a == 192 && b == 0) && !(a == 198 && (18...19).contains(b))
  }
  public static func checkDNS(_ url: URL) throws {
    try validate(url)
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(url.host, nil, nil, &result) == 0, let first = result else {
      throw MoltError.invalid("The webpage host could not be resolved.")
    }
    defer { freeaddrinfo(result) }
    var cursor: UnsafeMutablePointer<addrinfo>? = first
    while let current = cursor {
      let info = current.pointee
      if info.ai_family == AF_INET {
        var address = info.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
          $0.pointee.sin_addr
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil,
          isPublicIPv4(String(cString: buffer))
        else { throw MoltError.invalid("This host resolves to a private network.") }
      } else if info.ai_family == AF_INET6 {
        let bytes = info.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
          Array(withUnsafeBytes(of: $0.pointee.sin6_addr) { Data($0) })
        }
        // Require globally routed unicast IPv6, excluding mapped/private/link-local addresses.
        guard bytes.count == 16, bytes[0] & 0xe0 == 0x20 else {
          throw MoltError.invalid("This host resolves to a non-public network.")
        }
      }
      cursor = info.ai_next
    }
  }
}
public enum WebText {
  public static func extract(_ html: String) -> String {
    var text = html
    for pattern in [
      "(?is)<(script|style|noscript|svg)[\\s>].*?</\\1\\s*>", "(?s)<!--.*?-->", "(?s)<[^>]+>",
    ] {
      text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    for (entity, replacement) in [
      ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
      ("&#39;", "'"),
    ] {
      text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return String(
      text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines).prefix(12000))
  }
  public static func robotsAllows(_ robots: String, path: String) -> Bool {
    var matches = false
    var seenRule = false
    var bestAllow = -1
    var bestDeny = -1
    for raw in robots.components(separatedBy: .newlines) {
      let line = raw.components(separatedBy: "#")[0]
      guard let colon = line.firstIndex(of: ":") else { continue }
      let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      if key == "user-agent" {
        if seenRule {
          matches = false
          seenRule = false
        }
        matches = matches || value == "*" || value.lowercased().contains("molt")
      } else if key == "allow" || key == "disallow" {
        seenRule = true
        guard matches, !value.isEmpty else { continue }
        let end = value.hasSuffix("$")
        let clean = end ? String(value.dropLast()) : value
        let pattern =
          "^"
          + clean.components(separatedBy: "*").map(NSRegularExpression.escapedPattern).joined(
            separator: ".*") + (end ? "$" : "")
        if path.range(of: pattern, options: .regularExpression) != nil {
          if key == "allow" {
            bestAllow = max(bestAllow, value.count)
          } else {
            bestDeny = max(bestDeny, value.count)
          }
        }
      }
    }
    return bestDeny < 0 || bestAllow >= bestDeny
  }
}
private final class RejectWebRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
public struct ReadWebPage: Sendable {
  public var url: URL
  public var text: String
}
public final class WebReader: @unchecked Sendable {
  private let session: URLSession
  public init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 40
    config.httpShouldSetCookies = false
    config.connectionProxyDictionary = [:]
    session = URLSession(configuration: config, delegate: RejectWebRedirects(), delegateQueue: nil)
  }
  private func fetch(_ url: URL, maximum: Int) async throws -> (Data, HTTPURLResponse) {
    try await Task.detached { try WebAccessPolicy.checkDNS(url) }.value
    var request = URLRequest(url: url)
    request.setValue("MoltReader/0.4 (+local personal assistant)", forHTTPHeaderField: "User-Agent")
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MoltError.invalid("No webpage response.")
    }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximum else {
        throw MoltError.invalid("This page exceeds the reader's size limit.")
      }
      data.append(byte)
    }
    return (data, http)
  }
  public func read(_ supplied: URL) async throws -> ReadWebPage {
    var url = supplied
    for _ in 0..<4 {
      try WebAccessPolicy.validate(url)
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      components.path = "/robots.txt"
      components.query = nil
      components.fragment = nil
      let (robots, robotResponse) = try await fetch(components.url!, maximum: 128_000)
      guard
        robotResponse.statusCode == 404
          || (robotResponse.statusCode == 200
            && WebText.robotsAllows(
              String(decoding: robots, as: UTF8.self),
              path: url.path + (url.query.map { "?" + $0 } ?? "")))
      else {
        throw MoltError.invalid(
          "This site's reader policy could not be verified or does not allow this path. Open it in the browser instead."
        )
      }
      let (data, response) = try await fetch(url, maximum: 1_000_000)
      if (300...399).contains(response.statusCode),
        let location = response.value(forHTTPHeaderField: "Location"),
        let redirected = URL(string: location, relativeTo: url)?.absoluteURL
      {
        url = redirected
        continue
      }
      guard response.statusCode == 200 else {
        throw MoltError.invalid(
          "The site returned HTTP \(response.statusCode). Molting does not bypass access restrictions."
        )
      }
      let mime = response.mimeType ?? ""
      guard ["text/html", "text/plain", "application/xhtml+xml"].contains(mime) else {
        throw MoltError.invalid("The reader supports HTML and plain text webpages.")
      }
      guard let source = String(data: data, encoding: .utf8) else {
        throw MoltError.invalid("This page is not UTF-8 text.")
      }
      let text = mime == "text/plain" ? String(source.prefix(12000)) : WebText.extract(source)
      guard !text.isEmpty else {
        throw MoltError.invalid(
          "No readable text. The site may need JavaScript; use the browser view.")
      }
      return ReadWebPage(url: url, text: text)
    }
    throw MoltError.invalid("Too many redirects. Open the final public page directly.")
  }
}
