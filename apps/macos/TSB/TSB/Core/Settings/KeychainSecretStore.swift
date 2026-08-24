import Foundation
import Security

enum KeychainSecretStoreError: Error, Equatable {
    case invalidSecretData
    case unexpectedStatus(OSStatus)
}

struct KeychainSecretStore {
    private let service: String
    private let account: String
    private let keychain: SecKeychain?
    private let update: (CFDictionary, CFDictionary) -> OSStatus
    private let add: (CFDictionary) -> OSStatus
    private let deleteItem: (CFDictionary) -> OSStatus

    init(
        service: String = AppIdentity.keychainService,
        account: String = "organization-api-key",
        keychain: SecKeychain? = nil,
        update: @escaping (CFDictionary, CFDictionary) -> OSStatus = { SecItemUpdate($0, $1) },
        add: @escaping (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) },
        deleteItem: @escaping (CFDictionary) -> OSStatus = { SecItemDelete($0) }
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
        self.update = update
        self.add = add
        self.deleteItem = deleteItem
    }

    func save(_ secret: String) throws {
        let data = Data(secret.utf8)
        let status = update(matchQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainSecretStoreError.unexpectedStatus(status) }
        var query = addQuery
        query[kSecValueData as String] = data
        let addStatus = add(query as CFDictionary)
        guard addStatus == errSecSuccess else { throw KeychainSecretStoreError.unexpectedStatus(addStatus) }
    }

    func load() throws -> String? {
        var query = matchQuery
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

    func hasSecret() throws -> Bool {
        var query = matchQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainSecretStoreError.unexpectedStatus(status) }
        return true
    }

    func delete() throws {
        let status = deleteItem(matchQuery as CFDictionary)
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

    private var addQuery: [String: Any] {
        var query = baseQuery
        if let keychain {
            query[kSecUseKeychain as String] = keychain
        }
        return query
    }

    private var matchQuery: [String: Any] {
        var query = baseQuery
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        return query
    }
}
