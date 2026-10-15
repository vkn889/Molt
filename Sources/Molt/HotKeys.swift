import AppKit
import Carbon
import Foundation

/// Molt's keyboard shortcuts: each has a default, and Settings › Shortcuts can change any of them.
enum HotKeys {
  struct Binding: Codable, Equatable { var key: Int; var modifiers: UInt32 }
  struct Action { var id: UInt32; var title: String; var binding: Binding }
  /// Control-Option is VoiceOver's own modifier; with VoiceOver on, those defaults add Command.
  private static var hyper: UInt32 {
    UInt32(NSWorkspace.shared.isVoiceOverEnabled ? controlKey | optionKey | cmdKey : controlKey | optionKey)
  }
  static var actions: [Action] {
    [
      Action(id: 1, title: "Open Molt", binding: Binding(key: kVK_Return, modifiers: UInt32(cmdKey | shiftKey))),
      Action(id: 2, title: "Ask about your screen", binding: Binding(key: kVK_ANSI_L, modifiers: UInt32(cmdKey | shiftKey))),
      Action(id: 3, title: "Chat", binding: Binding(key: kVK_ANSI_C, modifiers: hyper)),
      Action(id: 5, title: "Agents", binding: Binding(key: kVK_ANSI_A, modifiers: hyper)),
      Action(id: 6, title: "Plan usage", binding: Binding(key: kVK_ANSI_U, modifiers: hyper)),
      Action(id: 7, title: "GitHub", binding: Binding(key: kVK_ANSI_G, modifiers: hyper)),
      Action(id: 4, title: "Wardrobe", binding: Binding(key: kVK_ANSI_W, modifiers: hyper)),
      Action(id: 8, title: "Hub", binding: Binding(key: kVK_ANSI_H, modifiers: hyper)),
      Action(id: 12, title: "Start a focus session", binding: Binding(key: kVK_ANSI_F, modifiers: hyper)),
      Action(id: 13, title: "Clipboard", binding: Binding(key: kVK_ANSI_V, modifiers: hyper)),
      Action(id: 10, title: "Allow an approval", binding: Binding(key: kVK_ANSI_Y, modifiers: hyper)),
      Action(id: 11, title: "Deny an approval", binding: Binding(key: kVK_ANSI_N, modifiers: hyper)),
    ]
  }
  private static var custom: [String: Binding] {
    get { (UserDefaults.standard.data(forKey: "hotKeys").flatMap { try? JSONDecoder().decode([String: Binding].self, from: $0) }) ?? [:] }
    set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "hotKeys") }
  }
  /// The binding in use for an action; a disabled one (key -1) is nil.
  static func binding(_ id: UInt32) -> Binding? {
    let binding = custom[String(id)] ?? actions.first { $0.id == id }?.binding
    return binding?.key == -1 ? nil : binding
  }
  static func set(_ id: UInt32, _ binding: Binding?) {
    var all = custom
    all[String(id)] = binding ?? Binding(key: -1, modifiers: 0)
    custom = all
  }
  static func reset(_ id: UInt32) {
    var all = custom
    all[String(id)] = nil
    custom = all
  }
  static func isCustom(_ id: UInt32) -> Bool { custom[String(id)] != nil }
  /// "⌃⌥C", "⌘⇧↩".
  static func describe(_ binding: Binding?) -> String {
    guard let binding else { return "Off" }
    var text = ""
    if binding.modifiers & UInt32(controlKey) != 0 { text += "⌃" }
    if binding.modifiers & UInt32(optionKey) != 0 { text += "⌥" }
    if binding.modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
    if binding.modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
    return text + keyName(binding.key)
  }
  static func keyName(_ code: Int) -> String {
    let named: [Int: String] = [
      kVK_Return: "↩", kVK_Space: "Space", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
      kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
      kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
    if let name = named[code] { return name }
    let letters: [Int: String] = [
      kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
      kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
      kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
      kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
      kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
      kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
    ]
    return letters[code] ?? "Key \(code)"
  }
  /// Carbon modifier flags from an AppKit event's.
  static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var value: UInt32 = 0
    if flags.contains(.command) { value |= UInt32(cmdKey) }
    if flags.contains(.option) { value |= UInt32(optionKey) }
    if flags.contains(.control) { value |= UInt32(controlKey) }
    if flags.contains(.shift) { value |= UInt32(shiftKey) }
    return value
  }
}
