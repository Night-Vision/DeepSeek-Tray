import Foundation
import Security

struct KeychainManager {
    private static let service = "com.deepseek.tray"

    static func save(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(account: account)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Keychain ACL: nil trusted application list permits ad-hoc dev builds (whose
        // cdhash shifts on every rebuild) to access the token without repeated macOS prompts.
        // Upgrade to app-scoped ACL when signing with Apple Developer ID.
        var access: SecAccess?
        if SecAccessCreate("DeepSeek Tray" as CFString, nil, &access) == errSecSuccess, let access {
            query[kSecAttrAccess as String] = access
        }

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
