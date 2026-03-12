import Foundation
import Security

struct KeychainTokenStore: Sendable {
    enum TokenKey: String {
        case supabaseAccessToken = "settings.auth.supabase.accessToken"
        case supabaseRefreshToken = "settings.auth.supabase.refreshToken"
    }

    private let service: String

    nonisolated init(service: String = "com.vmaritato.Waypoint.auth") {
        self.service = service
    }

    nonisolated func string(for key: TokenKey) -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value
    }

    nonisolated func set(_ value: String, for key: TokenKey) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            removeValue(for: key)
            return
        }

        let data = Data(normalized.utf8)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(for: key)
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    nonisolated func removeValue(for key: TokenKey) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private nonisolated func baseQuery(for key: TokenKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
