import Foundation
import Security

enum KeychainSecretStoreError: Error, Equatable {
    case invalidSecretData
    case unexpectedStatus(OSStatus)
}

struct KeychainSecretStore {
    private let service: String
    private let account: String

    init(service: String = AppIdentity.keychainService, account: String = "organization-api-key") {
        self.service = service
        self.account = account
    }

    func save(_ secret: String) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(secret.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainSecretStoreError.unexpectedStatus(status) }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainSecretStoreError.unexpectedStatus(status) }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.invalidSecretData
        }
        return secret
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
