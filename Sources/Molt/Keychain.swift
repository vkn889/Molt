import Foundation
import Security

/// One Codable value in the login keychain. Sign-in tokens live here, never in preferences.
struct KeychainItem<Value: Codable> {
  let service: String
  let account: String
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }
  func read() -> Value? {
    var q = query
    q[kSecReturnData as String] = true
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return try? JSONDecoder().decode(Value.self, from: data)
  }
  func write(_ value: Value) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
      var q = query
      q[kSecValueData as String] = data
      q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(q as CFDictionary, nil)
    }
  }
  func delete() { SecItemDelete(query as CFDictionary) }
}
