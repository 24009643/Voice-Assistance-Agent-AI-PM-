import Foundation
import Security

final class TemporaryKeychain {
    let reference: SecKeychain

    private let directory: URL
    private var isDeleted = false

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TSBTests-Keychain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let path = directory.appendingPathComponent("temporary.keychain-db").path
        let password = UUID().uuidString
        var keychain: SecKeychain?
        let status = path.withCString { pathPointer in
            password.withCString { passwordPointer in
                SecKeychainCreate(
                    pathPointer,
                    UInt32(password.utf8.count),
                    passwordPointer,
                    false,
                    nil,
                    &keychain
                )
            }
        }
        guard status == errSecSuccess, let keychain else {
            try? FileManager.default.removeItem(at: directory)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        self.directory = directory
        reference = keychain
    }

    func delete() {
        guard !isDeleted else { return }
        isDeleted = true
        SecKeychainDelete(reference)
        try? FileManager.default.removeItem(at: directory)
    }

    deinit {
        delete()
    }
}
