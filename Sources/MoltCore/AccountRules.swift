import Foundation

/// Client-side checks that mirror the server's rules, so mistakes are caught before sign-up.
public enum AccountRules {
  public static func usernameProblem(_ value: String) -> String? {
    let name = value.lowercased()
    guard (3...20).contains(name.count) else { return "Usernames are 3 to 20 characters." }
    guard name.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" }) else {
      return "Use letters, numbers and underscores only."
    }
    return nil
  }
  public static func passwordProblem(_ value: String) -> String? {
    guard value.count >= 8 else { return "Use at least 8 characters." }
    guard value.contains(where: \.isLetter), value.contains(where: \.isNumber) else {
      return "Include at least one letter and one number."
    }
    return nil
  }
  public static func emailLooksValid(_ value: String) -> Bool {
    let parts = value.trimmingCharacters(in: .whitespaces).split(separator: "@")
    return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
      && !value.contains(" ")
  }
  /// Reads the claims of a JWT without verifying it; the server verifies every request.
  public static func claims(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    guard let data = Data(base64Encoded: base64) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
}
