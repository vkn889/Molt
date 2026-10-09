import AppKit
import MoltCore
import SwiftUI

extension PetController {
  /// Molt's mood once the agents, your plan and your repository have had their say. An approval
  /// wakes Molt up; working agents put it at its laptop; a red default branch worries it; a plan
  /// nearly used up tires it out.
  var displayMood: String {
    if agents.needsYou { return "alert" }
    if isResting { return "sleeping" }
    if let mood = agents.mood { return mood }
    if github.summary?.ci == .failing { return "worried" }
    if plans.tightest >= 90 { return "tired" }
    return mood
  }
  var shellColor: Color? { agents.activeAgent.map(MoltTheme.agent) }
  var focusing: Bool { organization.sessions.contains { $0.finished == nil && $0.lastResumed != nil } }
}

/// One approval, with what it would do, how risky it is and how to answer.
struct ApprovalCard: View {
  @ObservedObject var agents: AgentController
  var appearance: Appearance
  var body: some View {
    if let item = agents.pending.first, item.isQuestion {
      QuestionCard(agents: agents, item: item, appearance: appearance).id(item.id)
    } else if let item = agents.pending.first {
      let agent = AgentKind.find(item.event.agent)
      HStack(alignment: .top, spacing: 12) {
        CreatureView(appearance: appearance, mood: "alert", shell: MoltTheme.agent(item.event.agent), followsPointer: false)
          .frame(width: 46, height: 43)
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            Circle().fill(MoltTheme.agent(item.event.agent)).frame(width: 7, height: 7)
            Text(agent?.name ?? "Agent").font(.system(size: 12, weight: .semibold))
            if !item.event.project.isEmpty {
              Text(item.event.project).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if agents.pending.count > 1 {
              Text("+\(agents.pending.count - 1) more").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            RiskPill(risk: item.risk, why: item.why)
          }
          ApprovalDetail(item: item)
          HStack(spacing: 6) {
            Button { agents.allow(item.id) } label: { Label("Allow", systemImage: "checkmark").frame(minWidth: 56) }
              .buttonStyle(PillButtonStyle(tint: .green)).help("Allow (⌃⌥Y)")
            Button("This session") { agents.allow(item.id, remember: true) }
              .buttonStyle(PillButtonStyle(tint: .white.opacity(0.14))).help("Allow \(ApprovalRule.signature(tool: item.event.tool, target: item.event.target)) for the rest of this session")
              .disabled(item.risk == .high)
            Button { agents.deny(item.id) } label: { Label("Deny", systemImage: "xmark") }
              .buttonStyle(PillButtonStyle(tint: .red.opacity(0.8))).help("Deny (⌃⌥N)")
            Spacer(minLength: 4)
            if !item.event.reason.isEmpty {
              Text(item.event.reason).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Terminal") { agents.answerInTerminal(item.id) }.buttonStyle(.plain)
              .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).help("Answer in the terminal instead")
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(agent?.name ?? "An agent") asks to use \(item.event.tool): \(item.event.target)")
    }
  }
}

/// What the agent wants to do: the diff for edits, otherwise the command or path.
struct ApprovalDetail: View {
  var item: AgentController.Pending
  var body: some View {
    let tint = MoltTheme.agent(item.event.agent)
    if let change = item.change {
      DiffPreview(change: change, tint: tint)
    } else {
      HStack(alignment: .top, spacing: 6) {
        Text(item.event.tool).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        Text(item.event.target.isEmpty ? "No details" : item.event.target)
          .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.9)).lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
      }
      .padding(.horizontal, 8).padding(.vertical, 5)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
    }
  }
}

/// The lines an edit would change, before you allow it.
struct DiffPreview: View {
  var change: ProposedChange
  var tint: Color
  static let height: CGFloat = 112
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Image(systemName: change.created ? "doc.badge.plus" : "pencil").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
        Text(URL(fileURLWithPath: change.path).lastPathComponent).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
        Text(change.created ? "new file" : change.note).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength: 4)
        Text("+\(change.added)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(.green)
        Text("−\(change.removed)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(.red)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if change.lines.isEmpty {
            Text("No changes to the text.").font(.system(size: 10)).foregroundStyle(.secondary)
          }
          ForEach(Array(change.lines.prefix(400).enumerated()), id: \.offset) { _, line in DiffRow(line: line) }
        }.textSelection(.enabled)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 5)
    .frame(height: Self.height)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Changes to \(URL(fileURLWithPath: change.path).lastPathComponent): \(change.added) lines added, \(change.removed) removed")
  }
}

struct DiffRow: View {
  var line: DiffLine
  private var mark: String {
    switch line.kind { case .added: return "+"; case .removed: return "−"; case .gap: return "⋯"; case .same: return " " }
  }
  private var color: Color {
    switch line.kind { case .added: return .green; case .removed: return .red; case .gap: return .white.opacity(0.3); case .same: return .white.opacity(0.6) }
  }
  private var fill: Color {
    switch line.kind { case .added: return .green.opacity(0.1); case .removed: return .red.opacity(0.1); default: return .clear }
  }
  var body: some View {
    HStack(spacing: 6) {
      Text(mark).font(.system(size: 10, weight: .bold, design: .monospaced)).frame(width: 10)
      Text(line.text.isEmpty ? " " : line.text).font(.system(size: 10, design: .monospaced)).lineLimit(1)
    }
    .foregroundStyle(color)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 4)
    .background(fill)
  }
}

/// An agent's multiple-choice question, answered with a click. One question at a time.
struct QuestionCard: View {
  @ObservedObject var agents: AgentController
  var item: AgentController.Pending
  var appearance: Appearance
  @State private var index = 0
  @State private var choices: [String: [String]] = [:]
  @State private var typed = ""
  static func height(options: Int) -> CGFloat { 96 + CGFloat((min(options, 6) + 1) / 2) * 44 }
  var body: some View {
    let questions = item.questions
    let question = questions[min(index, questions.count - 1)]
    let picked = choices[question.question] ?? []
    HStack(alignment: .top, spacing: 12) {
      CreatureView(appearance: appearance, mood: "alert", shell: MoltTheme.agent(item.event.agent), followsPointer: false)
        .frame(width: 46, height: 43)
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Circle().fill(MoltTheme.agent(item.event.agent)).frame(width: 7, height: 7)
          Text("\(AgentKind.find(item.event.agent)?.name ?? "Agent") asks").font(.system(size: 12, weight: .semibold))
          if !question.header.isEmpty {
            Text(question.header).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 7).frame(height: 18)
              .background(Capsule().fill(Color.white.opacity(0.1)))
          }
          Spacer(minLength: 4)
          if questions.count > 1 {
            Text("\(index + 1) of \(questions.count)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
          }
          Button("Terminal") { agents.answerInTerminal(item.id) }.buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).help("Answer in the terminal instead")
        }
        Text(question.question).font(.system(size: 13, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
          ForEach(Array(question.options.prefix(6).enumerated()), id: \.offset) { _, option in
            let selected = picked.contains(option.label)
            Button { choose(option.label, in: question) } label: {
              VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                  if question.multiSelect {
                    Image(systemName: selected ? "checkmark.square.fill" : "square").font(.system(size: 10))
                  }
                  Text(option.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                if !option.detail.isEmpty {
                  Text(option.detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 10).frame(height: 38)
              .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08)))
              .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
        }
        HStack(spacing: 6) {
          TextField("Or type your own answer", text: $typed).textFieldStyle(.plain).font(.system(size: 11))
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
            .onSubmit { if !typed.isEmpty { record([typed], for: question) } }
          if question.multiSelect || !typed.isEmpty {
            Button(index + 1 < questions.count ? "Next" : "Send") {
              record(typed.isEmpty ? picked : picked + [typed], for: question)
            }
            .buttonStyle(PillButtonStyle(tint: .accentColor)).disabled(picked.isEmpty && typed.isEmpty)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Question: \(question.question)")
  }
  private func choose(_ label: String, in question: AgentQuestion) {
    if question.multiSelect {
      var list = choices[question.question] ?? []
      if let at = list.firstIndex(of: label) { list.remove(at: at) } else { list.append(label) }
      choices[question.question] = list
    } else {
      record([label], for: question)
    }
  }
  /// Saves the answer and moves on; after the last question, sends them all.
  private func record(_ labels: [String], for question: AgentQuestion) {
    guard !labels.isEmpty else { return }
    choices[question.question] = labels
    typed = ""
    if index + 1 < item.questions.count {
      index += 1
    } else {
      agents.answer(item.id, choices: choices)
    }
  }
}

struct RiskPill: View {
  var risk: ApprovalRisk
  var why: String
  var body: some View {
    let tint: Color = risk == .high ? .red : risk == .medium ? .orange : .green
    Text(risk == .low ? risk.label : why).font(.system(size: 9, weight: .semibold)).lineLimit(1)
      .padding(.horizontal, 7).frame(height: 18)
      .foregroundStyle(tint)
      .background(Capsule().fill(tint.opacity(0.16)))
      .help(why)
  }
}

struct PillButtonStyle: ButtonStyle {
  var tint: Color
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
      .padding(.horizontal, 11).frame(height: 24)
      .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.7 : 1)))
      .contentShape(Capsule())
  }
}

/// The contents of a banner: an approval, a finished task, a habit to remember or a short note.
struct IslandBannerView: View {
  var banner: IslandBanner
  @ObservedObject var agents: AgentController
  var appearance: Appearance
  var dismiss: () -> Void
  var open: (String) -> Void
  var body: some View {
    Group {
      switch banner {
      case .approval:
        ApprovalCard(agents: agents, appearance: appearance)
      case .finished(let item):
        HStack(spacing: 12) {
          CreatureView(appearance: appearance, mood: "celebrating", shell: MoltTheme.agent(item.agent), followsPointer: false)
            .frame(width: 40, height: 37)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
              Circle().fill(MoltTheme.agent(item.agent)).frame(width: 6, height: 6)
              Text("\(AgentKind.find(item.agent)?.name ?? "Agent") finished").font(.system(size: 12, weight: .semibold))
              Text([item.project, item.duration >= 60 ? AgentsView.duration(item.duration) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(item.message.isEmpty ? "Ready for you." : item.message).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
          }
          Spacer(minLength: 6)
          Button("Open terminal") { AgentsView.activateTerminal(); dismiss() }.buttonStyle(PillButtonStyle(tint: .accentColor))
          Button("OK", action: dismiss).buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
        }
      case .message(let text, let symbol):
        HStack(spacing: 10) {
          Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(symbol.contains("xmark") ? .red : Color.accentColor)
          Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
          Spacer(minLength: 6)
          Button("Show") { open("GitHub"); dismiss() }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
          Button("OK", action: dismiss).buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
        }
      case .habit(let signature):
        HStack(spacing: 10) {
          CreatureView(appearance: appearance, mood: "happy", followsPointer: false).frame(width: 34, height: 31)
          VStack(alignment: .leading, spacing: 1) {
            Text("You keep allowing \(signature)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text("Always allow it? Risky commands still ask.").font(.system(size: 10)).foregroundStyle(.secondary)
          }
          Spacer(minLength: 6)
          Button("Always allow") { agents.acceptSuggestion(); dismiss() }.buttonStyle(PillButtonStyle(tint: .green))
          Button("No thanks") { agents.declineSuggestion(); dismiss() }.buttonStyle(PillButtonStyle(tint: .white.opacity(0.14)))
        }
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
  }
}

/// Beside the closed notch: Molt at work on the left, and what the agents need on the right.
struct AgentWings: View {
  @ObservedObject var agents: AgentController
  var appearance: Appearance
  var notchWidth: CGFloat
  var height: CGFloat
  @Environment(\.moltReducedMotion) private var reduced
  var body: some View {
    HStack(spacing: 0) {
      CreatureView(appearance: appearance, mood: agents.mood ?? "idle", shell: agents.activeAgent.map(MoltTheme.agent), followsPointer: false)
        .frame(width: height - 4, height: height - 6)
        .frame(maxWidth: .infinity)
      Color.clear.frame(width: notchWidth)
      Group {
        if agents.needsYou {
          Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        } else if !agents.working.isEmpty {
          HStack(spacing: 3) {
            ProgressView().controlSize(.mini).tint(.white)
            if agents.working.count > 1 { Text("\(agents.working.count)").font(.system(size: 10, weight: .bold).monospacedDigit()) }
          }
        } else {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .accessibilityElement()
    .accessibilityLabel(agents.needsYou ? "An agent needs you" : agents.working.isEmpty ? "Agents finished" : "\(agents.working.count) agents working")
  }
}
