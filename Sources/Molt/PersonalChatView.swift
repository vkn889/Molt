import AppKit
import MoltCore
import SwiftUI

/// Chat with Molt through Ollama on this Mac.
struct PersonalChatView: View {
  @ObservedObject var assistant: AssistantController
  @FocusState private var focused: Bool
  var body: some View {
    VStack(spacing: 8) {
      ScrollViewReader { reader in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            if assistant.conversation.isEmpty && assistant.reply.isEmpty {
              Text(assistant.selectedModel.isEmpty ? "Connect Ollama to start chatting." : "Ask anything.")
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
          Button("Connect Ollama", action: assistant.refresh)
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
