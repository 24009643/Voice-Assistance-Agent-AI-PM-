import Foundation
import XCTest
@testable import TSB

final class TranscriptStoreTests: XCTestCase {
    func testSaveRoundTripsARecordAtomically() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let store = TranscriptStore(directory: directory)

        try store.save(record)

        XCTAssertEqual(try store.load(id: record.id), record)
    }

    func testUpdateDeliveryStatusAtomicallyRewritesTheSavedRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let store = TranscriptStore(directory: directory)
        try store.save(record)

        try store.updateDeliveryStatus(id: record.id, to: .copied)

        XCTAssertEqual(try store.load(id: record.id).deliveryStatus, .copied)
    }

    func testFailedDeliveryStatusUpdateSurfacesErrorAndKeepsPendingRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let record = makeRecord()
        let store = TranscriptStore(directory: directory)
        try store.save(record)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        XCTAssertThrowsError(try store.updateDeliveryStatus(id: record.id, to: .failed))
        XCTAssertEqual(try store.load(id: record.id).deliveryStatus, .pending)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeRecord() -> TranscriptRecord {
        TranscriptRecord(
            id: SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
            ordinal: SessionOrdinal(rawValue: 4),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationMilliseconds: 1_250,
            detectedLanguages: ["zh"],
            originalText: "原始文本",
            localCleanedText: "清理文本",
            edits: [],
            deliveryStatus: .pending
        )
    }
}
