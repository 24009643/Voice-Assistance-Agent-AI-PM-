import Foundation
import XCTest
@testable import TSB

final class KeychainSecretStoreTests: XCTestCase {
    func testSaveLoadAndDeleteRoundTrip() throws {
        let store = makeStore()
        defer { try? store.delete() }
        let dummySecret = UUID().uuidString

        try store.save(dummySecret)
        XCTAssertEqual(try store.load(), dummySecret)

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testDeletingMissingSecretSucceeds() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.delete()

        XCTAssertNil(try store.load())
    }

    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "KeychainSecretStoreTests.\(UUID().uuidString)", account: "api-key")
    }
}
