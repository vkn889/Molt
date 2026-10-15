import Foundation
import MoltCore

/// How you've arranged the notch: tab order, what the closed notch shows first, and how it feels.
@MainActor final class NotchPrefs: ObservableObject {
  /// One set of preferences for the whole app.
  static let shared = NotchPrefs()
  private let defaults = UserDefaults.standard
  @Published var tabOrder: [String] { didSet { defaults.set(tabOrder, forKey: "notchTabOrder") } }
  @Published var hiddenTabs: Set<String> { didSet { defaults.set(Array(hiddenTabs), forKey: "notchHiddenTabs") } }
  @Published var priority: [LiveKind] { didSet { defaults.set(priority.map(\.rawValue), forKey: "notchPriority") } }
  /// Seconds the pointer rests on the notch before it opens.
  @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "notchHoverDelay") } }
  /// Each page sizes the notch to what it shows, instead of every page sharing Home's size.
  @Published var fitContent: Bool { didSet { defaults.set(fitContent, forKey: "notchFitContent") } }
  /// Molt notices the Mac: sleepy on low battery, warm when the Mac is.
  @Published var petReacts: Bool { didSet { defaults.set(petReacts, forKey: "notchPetReacts") } }
  /// Typing with the notch open searches everything.
  @Published var typeToJump: Bool { didSet { defaults.set(typeToJump, forKey: "notchTypeToJump") } }
  /// Clicking the closed notch opens it.
  @Published var openOnClick: Bool { didSet { defaults.set(openOnClick, forKey: "notchOpenOnClick") } }
  /// Scrolling down on the closed notch opens it.
  @Published var openOnScroll: Bool { didSet { defaults.set(openOnScroll, forKey: "notchOpenOnScroll") } }
  /// How quickly the notch moves: 0.7 is gentler, 1.4 is snappier.
  @Published var animationSpeed: Double { didSet { defaults.set(animationSpeed, forKey: "notchAnimationSpeed") } }
  /// How round the open notch's lower corners are, from 0.5 (squarer) to 1.5 (rounder).
  @Published var cornerScale: Double { didSet { defaults.set(cornerScale, forKey: "notchCornerScale") } }
  /// Hide the closed notch's activities while an app is full screen.
  @Published var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: "notchHideInFullScreen") } }
  /// Approvals start as a small pill beside the notch and grow when you hover over them.
  @Published var compactApprovals: Bool { didSet { defaults.set(compactApprovals, forKey: "notchCompactApprovals") } }
  /// Molt wakes up and waves when you open it after quitting.
  @Published var wakeAnimation: Bool { didSet { defaults.set(wakeAnimation, forKey: "notchWakeAnimation") } }
  /// Live activities you've switched off never show beside the notch.
  @Published var liveOff: Set<String> { didSet { defaults.set(Array(liveOff), forKey: "notchLiveOff") } }
  /// Whole parts of Molt you've switched off; they disappear everywhere.
  @Published var featuresOff: Set<String> { didSet { defaults.set(Array(featuresOff), forKey: "moltFeaturesOff") } }

  struct Feature: Identifiable { var id: String; var title: String; var symbol: String; var detail: String }
  static let features: [Feature] = [
    Feature(id: "music", title: "Music", symbol: "music.note", detail: "Now playing, playlists, and Molt dancing along"),
    Feature(id: "calendar", title: "Calendar & to-dos", symbol: "calendar", detail: "What's next today, Reminders and countdowns"),
    Feature(id: "focus", title: "Focus", symbol: "timer", detail: "Focus sessions, timers, breaks and habits"),
    Feature(id: "agents", title: "Coding agents", symbol: "terminal.fill", detail: "Claude Code and Codex: approvals, usage, GitHub"),
    Feature(id: "friends", title: "Friends", symbol: "person.2.fill", detail: "Molting: friends and hangouts"),
    Feature(id: "clipboard", title: "Clipboard history", symbol: "doc.on.clipboard", detail: "What you've copied, kept on this Mac"),
    Feature(id: "lens", title: "Lens", symbol: "text.viewfinder", detail: "Ask about anything on your screen"),
    Feature(id: "chat", title: "Chat", symbol: "bubble.left.fill", detail: "Talk to Molt with the model you choose"),
    Feature(id: "play", title: "Play", symbol: "gamecontroller.fill", detail: "Games and caring for Molt"),
  ]
  func has(_ feature: String) -> Bool { !featuresOff.contains(feature) }
  func set(_ feature: String, on: Bool) { if on { featuresOff.remove(feature) } else { featuresOff.insert(feature) } }
  /// The feature a tab, tool, widget or live activity belongs to, if it can be switched off.
  static func feature(of id: String) -> String? {
    switch id {
    case "Molting": return "friends"
    case "Play", "Wardrobe": return "play"
    case "Lens", "lens": return "lens"
    case "Agents", "agents", "agentUsage", "planUsage", "github", "weekRecap": return "agents"
    case "Ask Molt", "dailyBrief": return "chat"
    case "music", "nowPlaying", "playlists", "soundOutput": return "music"
    case "focus", "Focus", "focusStats", "timer", "breaks", "habits": return "focus"
    case "upNext", "reminders", "countdown", "tasks": return "calendar"
    case "clipboard": return "clipboard"
    default: return nil
    }
  }
  func shows(_ id: String) -> Bool { Self.feature(of: id).map(has) ?? true }

  init() {
    tabOrder = NotchLayout.allTabs(order: defaults.stringArray(forKey: "notchTabOrder") ?? [])
    hiddenTabs = Set(defaults.stringArray(forKey: "notchHiddenTabs") ?? [])
    priority = NotchLayout.priority(defaults.stringArray(forKey: "notchPriority") ?? [])
    hoverDelay = min(1, max(0, defaults.object(forKey: "notchHoverDelay") as? Double ?? 0.12))
    fitContent = defaults.object(forKey: "notchFitContent") as? Bool ?? true
    petReacts = defaults.object(forKey: "notchPetReacts") as? Bool ?? true
    typeToJump = defaults.object(forKey: "notchTypeToJump") as? Bool ?? true
    openOnClick = defaults.object(forKey: "notchOpenOnClick") as? Bool ?? true
    openOnScroll = defaults.object(forKey: "notchOpenOnScroll") as? Bool ?? true
    animationSpeed = min(1.4, max(0.7, defaults.object(forKey: "notchAnimationSpeed") as? Double ?? 1))
    cornerScale = min(1.5, max(0.5, defaults.object(forKey: "notchCornerScale") as? Double ?? 1))
    hideInFullScreen = defaults.object(forKey: "notchHideInFullScreen") as? Bool ?? true
    compactApprovals = defaults.object(forKey: "notchCompactApprovals") as? Bool ?? true
    wakeAnimation = defaults.object(forKey: "notchWakeAnimation") as? Bool ?? true
    liveOff = Set(defaults.stringArray(forKey: "notchLiveOff") ?? [])
    featuresOff = Set(defaults.stringArray(forKey: "moltFeaturesOff") ?? [])
  }
  var visibleTabs: [String] { NotchLayout.tabs(order: tabOrder, hidden: hiddenTabs).filter(shows) }
  func setTab(_ route: String, shown: Bool) {
    guard route != "Notch" else { return }
    if shown { hiddenTabs.remove(route) } else { hiddenTabs.insert(route) }
  }
  func moveTab(_ route: String, before target: String?) { tabOrder = NotchLayout.move(route, before: target, in: tabOrder) }
  func movePriority(_ kind: LiveKind, before target: LiveKind?) { priority = NotchLayout.move(kind, before: target, in: priority) }
}
