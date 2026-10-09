import AppKit
import MoltCore
import SwiftUI

/// Chat with Molt through Ollama on this Mac.
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
              Text(assistant.selectedModel.isEmpty ? "Pick a service above to start chatting." : "Ask anything.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
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
        if assistant.selectedModel.isEmpty {
          Button("Connect \(assistant.serviceInfo.name)", action: assistant.refresh)
        } else if assistant.running {
          Button(action: assistant.cancel) { Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold)) }
            .buttonStyle(NotchIconButtonStyle(size: 28, prominent: true)).accessibilityLabel("Stop")
        } else {
          Button { assistant.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
            .buttonStyle(NotchIconButtonStyle(size: 28, prominent: true)).foregroundStyle(Color.accentColor)
            .disabled(assistant.draft.isEmpty).accessibilityLabel("Send")
        }
        Button(action: assistant.newConversation) { Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 28)).help("New chat").accessibilityLabel("New chat")
      }
      if !assistant.status.isEmpty && assistant.selectedModel.isEmpty {
        Text(assistant.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 12)
    .onAppear { focused = true }
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
      if info.needsKey && !assistant.hasKey(info.id) {
        SecureField("\(info.name) key \(info.keyHint)", text: $key).textFieldStyle(.plain).font(.system(size: 10))
          .padding(.horizontal, 7).frame(width: 150, height: 20)
          .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
          .onSubmit { assistant.setKey(key, for: info.id); key = "" }
      } else if !assistant.models.isEmpty {
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
