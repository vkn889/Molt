import AppKit
import MoltCore
import SwiftUI

/// Chat with Molt: Ollama or LM Studio on this Mac, or a cloud service with your key.
struct PersonalChatView: View {
  @ObservedObject var assistant: AssistantController
  @FocusState private var focused: Bool
  @State private var key = ""
  var body: some View {
    VStack(spacing: 7) {
      services
      ScrollViewReader { reader in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            if assistant.conversation.isEmpty && assistant.reply.isEmpty {
              if assistant.ready {
                Text("Ask anything.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
              } else {
                setup
              }
            }
            ForEach(Array(assistant.conversation.enumerated()), id: \.offset) { index, message in
              bubble(message.content, user: message.role == "user").id(index)
            }
            if !assistant.reply.isEmpty, assistant.running || assistant.conversation.last?.role == "user" {
              bubble(assistant.reply, user: false).id("reply")
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: assistant.reply) { _ in reader.scrollTo("reply", anchor: .bottom) }
        .onChange(of: assistant.conversation.count) { count in reader.scrollTo(count - 1, anchor: .bottom) }
      }
      HStack(spacing: 6) {
        Button(action: assistant.chooseFile) { Image(systemName: "paperclip").font(.system(size: 12, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 28)).help(assistant.attachmentName.isEmpty ? "Attach a text file" : assistant.attachmentName)
          .accessibilityLabel("Attach a text file")
        TextField("Message Molt", text: $assistant.draft).textFieldStyle(.plain).font(.system(size: 12))
          .focused($focused).onSubmit { assistant.send() }
          .padding(.horizontal, 10).frame(height: 28)
          .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
        if !assistant.attachmentName.isEmpty {
          Button {
            assistant.attachment = ""; assistant.attachmentName = ""; assistant.sharedImage = nil
          } label: {
            Label(assistant.attachmentName, systemImage: "xmark").font(.system(size: 10)).lineLimit(1).frame(maxWidth: 110)
          }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove attachment")
        }
        if assistant.running {
          Button(action: assistant.cancel) { Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold)) }
            .buttonStyle(NotchIconButtonStyle(size: 28, prominent: true)).accessibilityLabel("Stop")
        } else {
          Button { assistant.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
            .buttonStyle(NotchIconButtonStyle(size: 28, prominent: true)).foregroundStyle(Color.accentColor)
            .disabled(assistant.draft.isEmpty || !assistant.ready).accessibilityLabel("Send")
        }
        Button(action: assistant.newConversation) { Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 28)).help("New chat").accessibilityLabel("New chat")
      }
      // Errors and progress always show, so a request never fails silently.
      if !assistant.status.isEmpty, !assistant.status.hasPrefix("Response complete"),
        assistant.ready || !assistant.conversation.isEmpty || assistant.draft.isEmpty == false
      {
        Text(assistant.status).font(.system(size: 10)).foregroundStyle(assistant.ready ? Color.secondary : Color.orange).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 12)
    .onAppear { focused = true }
  }
  static let keyPages = [
    "anthropic": "https://console.anthropic.com/settings/keys", "openai": "https://platform.openai.com/api-keys",
    "google": "https://aistudio.google.com/apikey", "openrouter": "https://openrouter.ai/keys",
  ]
  /// What's missing for the chosen service, with the one step that fixes it.
  @ViewBuilder private var setup: some View {
    let info = assistant.serviceInfo
    VStack(alignment: .leading, spacing: 6) {
      if info.needsKey && !assistant.hasKey(info.id) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("\(info.name) needs your API key").font(.system(size: 13, weight: .semibold))
          Text("Messages go to \(info.name). The key stays in your keychain.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        HStack(spacing: 6) {
          SecureField("Paste your key \(info.keyHint)", text: $key).textFieldStyle(.plain).font(.system(size: 11))
            .padding(.horizontal, 8).frame(width: 200, height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .onSubmit(saveKey)
          Button("Save", action: saveKey).disabled(key.isEmpty)
          if let page = Self.keyPages[info.id], let url = URL(string: page) {
            Link("Get a key", destination: url).font(.system(size: 10, weight: .semibold))
          }
          Spacer(minLength: 4)
          if AssistantController.ollamaInstalled {
            Button("Use Ollama instead", action: assistant.useOllama).buttonStyle(.plain)
              .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
          }
        }
      } else if info.id == "ollama" {
        Text(AssistantController.ollamaInstalled ? "Ollama isn't running" : "Ollama isn't installed").font(.system(size: 13, weight: .semibold))
        Text("Ollama runs models on this Mac; nothing leaves it. Molt starts it for you.").font(.system(size: 10)).foregroundStyle(.secondary)
        HStack(spacing: 6) {
          if AssistantController.ollamaInstalled {
            Button(assistant.running ? "Starting…" : "Start Ollama", action: assistant.refresh).disabled(assistant.running)
          } else {
            Link("Get Ollama", destination: URL(string: "https://ollama.com/download")!).font(.system(size: 11, weight: .semibold))
          }
        }
      } else if info.id == "lmstudio" {
        Text("LM Studio's server isn't on").font(.system(size: 13, weight: .semibold))
        Text("In LM Studio, load a model and turn on the local server (Developer tab), then connect.")
          .font(.system(size: 10)).foregroundStyle(.secondary)
        Button(assistant.running ? "Connecting…" : "Connect", action: assistant.refresh).disabled(assistant.running)
      } else {
        Text("Connecting to \(info.name)…").font(.system(size: 13, weight: .semibold))
        Button("Try again", action: assistant.refresh).disabled(assistant.running)
      }
      if info.id != "ollama" && !info.needsKey && AssistantController.ollamaInstalled {
        Button("Use Ollama on this Mac instead", action: assistant.useOllama).buttonStyle(.plain)
          .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NotchSurface(radius: 14))
  }
  private func saveKey() {
    guard !key.isEmpty else { return }
    assistant.setKey(key, for: assistant.service)
    key = ""
  }
  /// Where messages go: a local server, or a cloud service with your key.
  private var services: some View {
    HStack(spacing: 4) {
      ForEach(ChatService.all) { service in
        Button { assistant.service = service.id } label: {
          HStack(spacing: 4) {
            Circle().fill(service.local ? Color.green : Color.orange).frame(width: 5, height: 5)
            Text(service.name).font(.system(size: 10, weight: .semibold))
          }
          .padding(.horizontal, 8).frame(height: 20)
          .foregroundStyle(assistant.service == service.id ? Color.white : Color.white.opacity(0.55))
          .background(Capsule().fill(Color.white.opacity(assistant.service == service.id ? 0.14 : 0.04)))
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(service.local ? "\(service.name) runs on this Mac" : "Messages are sent to \(service.name) with your key")
      }
      Spacer(minLength: 4)
      let info = assistant.serviceInfo
      if !assistant.models.isEmpty {
        Menu {
          ForEach(assistant.models) { model in Button(model.id) { assistant.selectedModel = model.id } }
          if info.needsKey {
            Divider()
            Button("Forget \(info.name) key", role: .destructive) { assistant.forgetKey(info.id) }
          }
        } label: {
          Text(assistant.selectedModel.isEmpty ? "Model" : assistant.selectedModel).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .menuStyle(.borderlessButton).fixedSize().frame(maxWidth: 170)
      }
    }
    .onAppear { if assistant.models.isEmpty { assistant.refresh() } }
  }
  private func bubble(_ text: String, user: Bool) -> some View {
    HStack {
      if user { Spacer(minLength: 80) }
      Text(text).font(.system(size: 12)).textSelection(.enabled)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(user ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.08)))
        .foregroundStyle(.white)
      if !user { Spacer(minLength: 80) }
    }
  }
}
