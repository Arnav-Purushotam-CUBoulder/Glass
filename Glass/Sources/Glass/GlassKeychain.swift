import Foundation
import Security

enum GlassKeychain {
    private static let service = "com.arnavpurushotam.glass"
    private static let legacyServices = ["com.natively.glass"]
    private static let openAIAccount = "openai-api-key"
    private static let legacySttAccount = "openai-stt-api-key"

    static func loadOpenAIKey() -> String {
        if let primary = loadValue(forAccount: openAIAccount), !primary.isEmpty {
            return primary
        }
        if let currentLegacyAccount = loadValue(forAccount: legacySttAccount), !currentLegacyAccount.isEmpty {
            try? saveOpenAIKey(currentLegacyAccount)
            deleteValue(forAccount: legacySttAccount, service: service)
            return currentLegacyAccount
        }

        for legacyService in legacyServices {
            if let migrated = loadValue(forAccount: openAIAccount, service: legacyService), !migrated.isEmpty {
                try? saveOpenAIKey(migrated)
                deleteLegacyValues()
                return migrated
            }

            if let migrated = loadValue(forAccount: legacySttAccount, service: legacyService), !migrated.isEmpty {
                try? saveOpenAIKey(migrated)
                deleteLegacyValues()
                return migrated
            }
        }

        return ""
    }

    private static func loadValue(forAccount account: String) -> String? {
        loadValue(forAccount: account, service: service)
    }

    private static func loadValue(forAccount account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func saveOpenAIKey(_ key: String) throws {
        deleteValue(forAccount: openAIAccount)
        deleteValue(forAccount: legacySttAccount)
        deleteLegacyValues()
        guard !key.isEmpty else { return }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIAccount,
            kSecValueData as String: Data(key.utf8)
        ]

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func deleteValue(forAccount account: String) {
        deleteValue(forAccount: account, service: service)
    }

    private static func deleteValue(forAccount account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func deleteLegacyValues() {
        for legacyService in legacyServices {
            deleteValue(forAccount: openAIAccount, service: legacyService)
            deleteValue(forAccount: legacySttAccount, service: legacyService)
        }
    }
}
