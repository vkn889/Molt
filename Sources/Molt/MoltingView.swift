import AppKit
import MoltCore
import SwiftUI
import WebKit

@MainActor final class MoltingController: ObservableObject {
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
  func cancel() { request?.cancel() }
}
struct MoltingView: View {
  @ObservedObject var assistant: AssistantController
  var onChat: () -> Void
  var body: some View {
    MoltingContent(model: assistant.molting, assistant: assistant, onChat: onChat)
  }
}
private struct MoltingContent: View {
  @ObservedObject var model: MoltingController
  @ObservedObject var assistant: AssistantController
  var onChat: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Molting", systemImage: "globe").font(MoltTheme.display(20))
        TextField("Search anything…", text: $model.query).textFieldStyle(.roundedBorder).onSubmit(
          model.search)
        Button("Search web", action: model.search)
      }
      Text(
        "Web queries go to the search engine. Chat stays local. Pages are never instructions to execute actions."
      ).font(.caption2).foregroundStyle(.secondary)
      if let url = model.browserURL {
        SearchBrowser(url: url, model: model).frame(height: 230).clipShape(
          RoundedRectangle(cornerRadius: 10))
        HStack {
          Button("Read current page") {
            model.pageAddress = model.currentURL?.absoluteString ?? ""
            model.readPage()
          }.disabled(model.busy)
          if let current = model.currentURL { Link("Open in browser", destination: current) }
        }.font(.caption)
      }
      HStack {
        TextField("Or paste a public HTTPS page to read", text: $model.pageAddress).textFieldStyle(
          .roundedBorder
        ).onSubmit(model.readPage)
        if model.busy {
          Button("Stop", action: model.cancel)
        } else {
          Button("Read page", action: model.readPage)
        }
      }
      Text(model.status).font(.caption)
      if let source = model.source {
        Link(source.absoluteString, destination: source).font(.caption).lineLimit(2)
        DisclosureGroup("Preview extracted page text") {
          Text(model.excerpt).font(.caption).textSelection(.enabled)
        }
        Button("Discuss this source with Molt") {
          assistant.sharedImage = nil
          assistant.attachment = model.excerpt
          assistant.attachmentName = source.absoluteString
          assistant.draft =
            model.query.isEmpty
            ? "Summarize this source and help me understand it. Cite the source URL."
            : "Help me with: \(model.query). Use the supplied page, cite its URL, and distinguish source facts from your reasoning."
          onChat()
        }
      }
    }
  }
}
private struct SearchBrowser: NSViewRepresentable {
  let url: URL
  @ObservedObject var model: MoltingController
  func makeCoordinator() -> Coordinator { Coordinator(model) }
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: configuration)
    web.navigationDelegate = context.coordinator
    web.underPageBackgroundColor = .clear
    return web
  }
  func updateNSView(_ view: WKWebView, context: Context) {
    if context.coordinator.requested != url {
      context.coordinator.requested = url
      view.load(URLRequest(url: url))
    }
  }
  @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
    let model: MoltingController
    var requested: URL?
    init(_ model: MoltingController) { self.model = model }
    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url, (try? WebAccessPolicy.validate(url)) != nil
      else {
        decisionHandler(.cancel)
        return
      }
      Task {
        do {
          try await Task.detached { try WebAccessPolicy.checkDNS(url) }.value
          decisionHandler(.allow)
        } catch {
          model.status = error.localizedDescription
          decisionHandler(.cancel)
        }
      }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      model.currentURL = webView.url
    }
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) { model.status = "Browser: \(error.localizedDescription)" }
  }
}
