import Foundation
import Security

enum KeychainStore {
    private static let service = "AIChatApp.OpenAICompatible"
    private static let apiKeyAccount = "apiKey"

    static func readAPIKey(account: String = apiKeyAccount) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    static func saveAPIKey(_ apiKey: String, account: String = apiKeyAccount) {
        let query = baseQuery(account: account)

        if apiKey.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(apiKey.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func deleteAPIKey(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
