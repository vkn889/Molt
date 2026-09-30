import AppKit
import MoltCore
import SwiftUI

@MainActor final class MoltingController: ObservableObject {
  @Published var researchURLs = ""
  @Published var researchSources: [ReadWebPage] = []
  @Published var researchFailures: [String] = []
  @Published var query = ""
  @Published var browserURL: URL?
  @Published var currentURL: URL?
  @Published var pageAddress = ""
  @Published var excerpt = ""
  @Published var source: URL?
  @Published var status = "Search the web, read a public page, then discuss it with Molt."
  @Published var busy = false
  private var request: Task<Void, Never>?
  func search() {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    var url = URLComponents(string: "https://duckduckgo.com/")!
    url.queryItems = [URLQueryItem(name: "q", value: String(query.prefix(1000)))]
    browserURL = url.url
    currentURL = url.url
    status = "Search query sent to DuckDuckGo. Browsing uses an isolated, nonpersistent session."
  }
  func readPage() {
    guard !busy, let url = URL(string: pageAddress) else {
      status = "Enter a public HTTPS page URL."
      return
    }
    busy = true
    excerpt = ""
    source = nil
    status = "Reading the public page and its reader policy…"
    request = Task {
      defer { busy = false }
      do {
        let page = try await WebReader().read(url)
        try Task.checkCancellation()
        excerpt = page.text
        source = page.url
        status =
          "Page ready for review. Nothing has been sent to AI. Dynamic or restricted content may be unavailable."
      } catch { status = Task.isCancelled ? "Page read canceled." : error.localizedDescription }
    }
  }
  func research() {
    guard !busy else { return }
    let lines = researchURLs.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard (2...5).contains(lines.count), lines.allSatisfy({ URL(string: $0) != nil }) else {
      status = "Provide two to five public HTTPS source URLs, one per line."
      return
    }
    researchSources = []
    researchFailures = []
    busy = true
    request = Task {
      defer { busy = false }
      for address in lines {
        if Task.isCancelled { status = "Research stopped. Completed sources remain available."; return }
        status = "Reading source \(researchSources.count + researchFailures.count + 1) of \(lines.count)…"
        do {
          let page = try await WebReader().read(URL(string: address)!)
          try Task.checkCancellation()
          researchSources.append(page)
        } catch {
          if Task.isCancelled { status = "Research stopped."; return }
          researchFailures.append("\(address): \(error.localizedDescription)")
        }
      }
      status = "Research ready: \(researchSources.count) sources, \(researchFailures.count) unavailable. Review before synthesizing."
    }
  }
  func cancel() { request?.cancel() }
}
