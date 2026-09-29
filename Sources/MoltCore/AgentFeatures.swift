import Foundation

public struct ApprovedMemory: Codable, Identifiable {
  public var id = UUID()
  public var text: String
  public var enabled = true
  public init(_ text: String) { self.text = text }
}

public enum AgentPlan {
  public static func parse(_ output: String) throws -> [ToolProposal] {
    struct Step: Decodable {
      var tool: AssistantTool
      var text: String
      var minutes: Int?
    }
    let cleaned = output.replacingOccurrences(of: "[end of text]", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let steps = try JSONDecoder().decode([Step].self, from: Data(cleaned.utf8))
    guard (1...6).contains(steps.count) else {
      throw MoltError.invalid("A plan must contain one to six steps.")
    }
    return try steps.map { step in
      guard step.tool != .openWorkspace else {
        throw MoltError.invalid("Opening folders requires the explicit project picker.")
      }
      let proposal = ToolProposal(tool: step.tool, text: step.text, minutes: step.minutes)
      try proposal.validate()
      return proposal
    }
  }
}
