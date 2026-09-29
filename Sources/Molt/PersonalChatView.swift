import AppKit
import MoltCore
import SwiftUI

struct PersonalChatView: View {
  @ObservedObject var assistant: AssistantController
  var onSetup: () -> Void
  @State private var showScreen = false
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if assistant.conversation.isEmpty {
        Text("What’s on your mind?").font(MoltTheme.display(22))
        Text("Talk something through, learn, plan, create, or share a screen for help.").font(
          .callout
        ).foregroundStyle(.secondary)
      }
      ForEach(Array(assistant.conversation.enumerated()), id: \.offset) { _, message in
        VStack(alignment: .leading, spacing: 4) {
          Text(message.role == "user" ? "You" : "Molt").font(.caption.bold()).foregroundStyle(
            Color.accentColor)
          Text(message.content).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
          .background(
            Color.primary.opacity(message.role == "user" ? 0.08 : 0.03),
            in: RoundedRectangle(cornerRadius: 12))
      }
      if !assistant.reply.isEmpty, assistant.running || assistant.conversation.last?.role == "user"
      {
        Text(assistant.reply).textSelection(.enabled)
      }
      TextField("Ask anything…", text: $assistant.draft, axis: .vertical).lineLimit(1...4)
        .textFieldStyle(.roundedBorder).focused($focused).onSubmit { assistant.send() }
      HStack {
        Button {
          showScreen.toggle()
        } label: {
          Label("Screen help", systemImage: "rectangle.dashed.badge.record")
        }
        Button("Attach text", action: assistant.chooseFile)
        Button("New chat", action: assistant.newConversation)
        Spacer()
        if assistant.selectedModel.isEmpty {
          Button("Set up AI", action: onSetup)
        } else if assistant.running {
          Button("Stop", action: assistant.cancel)
        } else {
          Button("Send", action: assistant.send).disabled(assistant.draft.isEmpty)
        }
      }.font(.caption)
      if !assistant.attachmentName.isEmpty {
        HStack {
          Label(assistant.attachmentName, systemImage: "paperclip").font(.caption)
          if assistant.sharedImage != nil { Text("Image shared with next message").font(.caption) }
          Button("Remove") {
            assistant.attachment = ""
            assistant.attachmentName = ""
            assistant.sharedImage = nil
          }
        }
      }
      Text(assistant.status).font(.caption2).foregroundStyle(.secondary)
      if showScreen { ScreenHelpView(help: assistant.screenHelp, assistant: assistant) }
    }.onAppear { focused = true }
  }
}
struct ScreenHelpView: View {
  @ObservedObject var help: ScreenHelp
  @ObservedObject var assistant: AssistantController
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Share your screen, only when you choose").font(.headline)
      Text(
        "macOS will request Screen Recording permission. One frame is captured, excluding Molt. Review it before sharing with a local model. No continuous monitoring or cloud upload."
      ).font(.caption)
      HStack {
        Picker("Display", selection: $help.displayIndex) {
          ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
            Text(screen.localizedName).tag(index)
          }
        }
        Button("Capture once", action: help.capture).disabled(help.busy)
        Button("Attach screenshot", action: help.chooseImage).disabled(help.busy)
      }
      Text(help.status).font(.caption)
      if let image = help.preview {
        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 140).accessibilityLabel(
          "Screenshot preview. Check for private information before sharing.")
        HStack {
          Button("Use image in next message") { assistant.shareScreen(asImage: true) }
          Button("Use extracted text") { assistant.shareScreen(asImage: false) }.disabled(
            help.recognizedText.isEmpty)
          Button("Discard") {
            help.clear()
            assistant.sharedImage = nil
            assistant.attachment = ""
            assistant.attachmentName = ""
          }
        }.font(.caption)
        DisclosureGroup("Preview extracted text") {
          Text(help.recognizedText).font(.caption).textSelection(.enabled)
        }
        Text(
          "Images require a local Ollama vision model. The compact managed model can help with extracted text."
        ).font(.caption2).foregroundStyle(.secondary)
      }
    }.padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
  }
}
