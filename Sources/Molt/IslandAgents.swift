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
    if let item = agents.pending.first {
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
          HStack(alignment: .top, spacing: 6) {
            Text(item.event.tool).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(MoltTheme.agent(item.event.agent))
            Text(item.event.target.isEmpty ? "No details" : item.event.target)
              .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.9)).lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
          }
          .padding(.horizontal, 8).padding(.vertical, 5)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
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
