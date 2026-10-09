import MoltCore
import SwiftUI

/// Dress Molt up. Items are earned by caring for Molt, hanging out with friends, finishing agent
/// work, keeping a GitHub streak, or being around for a season. One item per slot.
struct WardrobeView: View {
  @ObservedObject var controller: PetController
  @ObservedObject var agents: AgentController
  @ObservedObject var github: GitHubController
  @ObservedObject var account: AccountController
  @State private var tried: Date?
  init(controller: PetController) {
    self.controller = controller
    agents = controller.agents
    github = controller.github
    account = controller.account
  }
  private var progress: WardrobeProgress {
    WardrobeProgress(
      inventory: controller.companion.inventory, friendPoints: account.profile?.points ?? 0,
      agentTasks: agents.saved.tasksFinished, bestStreak: github.bestStreak,
      month: Calendar.current.component(.month, from: Date()))
  }
  var body: some View {
    HStack(spacing: 14) {
      VStack(spacing: 4) {
        CreatureView(appearance: controller.companion.appearance, mood: tried.map { Date().timeIntervalSince($0) < 2 } == true ? "celebrating" : "waving", poked: tried)
          .frame(width: 112, height: 104)
        Text(controller.petName).font(.system(size: 13, weight: .semibold))
        Text(controller.companion.appearance.outfit.isEmpty ? "Nothing on" : controller.companion.appearance.outfit.compactMap { WardrobeItem.find($0)?.name }.joined(separator: " · "))
          .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
      }
      .frame(width: 190).frame(maxHeight: .infinity)
      .background(NotchSurface(radius: 16))
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Wardrobe").font(.system(size: 12, weight: .semibold))
          Text("\(WardrobeItem.all.filter(progress.owns).count) of \(WardrobeItem.all.count)").font(.system(size: 10)).foregroundStyle(.secondary)
          Spacer()
          if let seasonal = WardrobeItem.all.first(where: { if case .season(let months) = $0.unlock { return months.contains(progress.month) } else { return false } }) {
            Label("\(seasonal.name) is here this month", systemImage: "sparkles").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
          }
          Text("⌃⌥W").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
          ForEach(WardrobeItem.all) { item in tile(item) }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
    .onAppear(perform: collect)
  }
  private func tile(_ item: WardrobeItem) -> some View {
    let owned = progress.owns(item)
    let worn = controller.companion.appearance.outfit.contains(item.id)
    var preview = controller.companion.appearance
    preview.outfit = [item.id]
    return Button {
      guard owned else { return }
      controller.changeCompanion { $0.appearance.toggle(item.id) }
      tried = Date()
    } label: {
      VStack(spacing: 2) {
        ZStack(alignment: .topTrailing) {
          CreatureView(appearance: preview, mood: "idle", moving: false).frame(width: 40, height: 37).opacity(owned ? 1 : 0.3)
          if !owned { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
        }
        Text(item.name).font(.system(size: 9, weight: .medium)).lineLimit(1).foregroundStyle(Color.white.opacity(owned ? 0.8 : 0.4))
      }
      .frame(maxWidth: .infinity).frame(height: 60)
      .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(worn ? 0.16 : 0.05)))
      .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(worn ? Color.accentColor : .clear, lineWidth: 1.5))
      .contentShape(RoundedRectangle(cornerRadius: 11))
    }
    .buttonStyle(.plain)
    .help(owned ? (worn ? "Take off \(item.name)" : "Wear \(item.name)") : item.requirement)
    .accessibilityLabel(owned ? "\(item.name)\(worn ? ", wearing" : "")" : "\(item.name), locked. \(item.requirement)")
  }
  /// Keeps what's been earned, so seasonal items stay after their season.
  private func collect() {
    let earned = progress.newlyEarned
    guard !earned.isEmpty else { return }
    controller.changeCompanion { companion in
      companion.inventory.append(contentsOf: earned.filter { !companion.inventory.contains($0) })
    }
  }
}
