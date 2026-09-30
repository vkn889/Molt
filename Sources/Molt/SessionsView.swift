import AppKit
import MoltCore
import SwiftUI

/// Claude Code and Codex conversations, with today's usage, in the same footprint as Home.
struct SessionsView: View {
  @ObservedObject var sessions: SessionsController
  var body: some View {
    Group {
      if sessions.enabled {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            usage
            list
          }.frame(width: 270)
          transcript
        }
      } else {
        HStack(spacing: 18) {
          Image(systemName: "terminal.fill").font(.system(size: 30)).foregroundStyle(Color.accentColor)
          VStack(alignment: .leading, spacing: 6) {
            Text("Your Claude Code and Codex chats").font(.system(size: 15, weight: .semibold))
            Text("Molt reads the conversations these tools save on this Mac, keeps a private copy so they are never lost, and shows your token usage. Nothing leaves your Mac.")
              .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Turn on") { sessions.enabled = true }.padding(.top, 2)
          }.frame(maxWidth: 440, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
    .onAppear { sessions.scan() }
  }

  private var usage: some View {
    let today = Calendar.current.startOfDay(for: Date())
    let week = today.addingTimeInterval(-6 * 86400)
    return HStack(spacing: 6) {
      stat("Claude Code", sessions.tokens(tool: "Claude Code", since: today), tint: .orange)
      stat("Codex", sessions.tokens(tool: "Codex", since: today), tint: .teal)
      stat("7 days", sessions.tokens(since: week), tint: .white)
      Spacer(minLength: 0)
      if sessions.busy { ProgressView().controlSize(.mini) }
      Button { sessions.scan(force: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)) }
        .buttonStyle(NotchIconButtonStyle(size: 22)).help("Rescan").accessibilityLabel("Rescan conversations")
    }
  }
  private func stat(_ title: String, _ tokens: Int, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(Self.compact(tokens)).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
      Text(title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    .accessibilityElement().accessibilityLabel("\(title): \(tokens) tokens")
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        if sessions.sessions.isEmpty && !sessions.busy {
          Text("No conversations found yet.").font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
        }
        ForEach(sessions.sessions) { session in
          let selected = sessions.selected == session.id
          Button { sessions.selected = session.id } label: {
            HStack(spacing: 8) {
              Circle().fill(session.tool == "Codex" ? Color.teal : Color.orange).frame(width: 6, height: 6)
              VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                  .foregroundStyle(Color.white.opacity(selected ? 1 : 0.85))
                Text([session.project, session.updated.formatted(.relative(presentation: .named))].filter { !$0.isEmpty }.joined(separator: " · "))
                  .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
              }
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected ? 0.12 : 0)))
            .contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
    }
  }

  private var transcript: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let session = sessions.selectedSession {
        HStack(spacing: 6) {
          Text(session.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Spacer(minLength: 4)
          Text("\(session.messages) messages · \(Self.compact(session.tokens)) tokens").font(.system(size: 10)).foregroundStyle(.secondary)
          Button { sessions.reveal(session) } label: { Image(systemName: "folder").font(.system(size: 11, weight: .semibold)) }
            .buttonStyle(NotchIconButtonStyle(size: 22)).help("Show file in Finder").accessibilityLabel("Show file in Finder")
          Button(action: sessions.openArchive) { Image(systemName: "archivebox").font(.system(size: 11, weight: .semibold)) }
            .buttonStyle(NotchIconButtonStyle(size: 22)).help("Open Molt's saved copies (\(sessions.archivedCount))").accessibilityLabel("Open saved chats")
        }
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              ForEach(Array(sessions.transcript.enumerated()), id: \.offset) { index, message in
                HStack(alignment: .top, spacing: 6) {
                  Text(message.role == "user" ? "You" : session.tool == "Codex" ? "Codex" : "Claude")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(message.role == "user" ? Color.accentColor : (session.tool == "Codex" ? .teal : .orange))
                    .frame(width: 38, alignment: .trailing)
                  Text(message.text).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(message.role == "user" ? 6 : 10).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.id(index)
              }
            }
          }
          .onChange(of: sessions.transcript.count) { count in
            if count > 0 { reader.scrollTo(count - 1, anchor: .bottom) }
          }
        }
      } else {
        Text("Pick a conversation.").font(.system(size: 11)).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NotchSurface(radius: 14))
  }
  static func compact(_ value: Int) -> String {
    value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000)
      : value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : "\(value)"
  }
}
