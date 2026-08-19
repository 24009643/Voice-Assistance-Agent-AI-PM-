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

        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalRecordURL(for: record.id, in: directory).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyRecordURL(for: record.id, in: directory).path))
        XCTAssertEqual(try store.load(id: record.id), record)
    }

    func testLoadReadsLegacyFlatRecordWithoutMigratingIt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let legacyURL = legacyRecordURL(for: record.id, in: directory)
        try legacyEncodedData(for: record).write(to: legacyURL)
        let store = TranscriptStore(directory: directory)

        let loaded = try store.load(id: record.id)
        XCTAssertEqual(loaded.id, record.id)
        XCTAssertEqual(loaded.localCleanedText, record.localCleanedText)
        XCTAssertNil(loaded.localEvaluationConsent)
        XCTAssertNil(loaded.finalSource)
        XCTAssertEqual(loaded.reviewState, .unreviewed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalRecordURL(for: record.id, in: directory).path))
    }

    func testLegacyStatusUpdateRewritesOnlyTheLegacyRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let legacyURL = legacyRecordURL(for: record.id, in: directory)
        try legacyEncodedData(for: record).write(to: legacyURL)
        let store = TranscriptStore(directory: directory)

        try store.updateDeliveryStatus(id: record.id, to: .copied)

        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalRecordURL(for: record.id, in: directory).path))
        let rewritten = try JSONDecoder().decode(TranscriptRecord.self, from: Data(contentsOf: legacyURL))
        XCTAssertEqual(rewritten.deliveryStatus, .copied)
        XCTAssertNil(rewritten.localEvaluationConsent)
        XCTAssertNil(rewritten.finalSource)
    }

    func testLoadPrefersCanonicalRecordOverLegacyFlatRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let canonical = makeRecord()
        let legacy = TranscriptRecord(
            id: canonical.id,
            ordinal: canonical.ordinal,
            createdAt: canonical.createdAt,
            durationMilliseconds: canonical.durationMilliseconds,
            detectedLanguages: canonical.detectedLanguages,
            originalText: "旧版文本",
            localCleanedText: "旧版文本",
            edits: [],
            deliveryStatus: .pending
        )
        let canonicalURL = canonicalRecordURL(for: canonical.id, in: directory)
        try FileManager.default.createDirectory(at: canonicalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(canonical).write(to: canonicalURL)
        try JSONEncoder().encode(legacy).write(to: legacyRecordURL(for: canonical.id, in: directory))
        let store = TranscriptStore(directory: directory)

        XCTAssertEqual(try store.load(id: canonical.id), canonical)
        XCTAssertEqual(
            try JSONDecoder().decode(TranscriptRecord.self, from: Data(contentsOf: legacyRecordURL(for: canonical.id, in: directory))),
            legacy
        )
    }

    func testUpdateDeliveryStatusAtomicallyRewritesTheSavedRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let store = TranscriptStore(directory: directory)
        try store.save(record)

        try store.updateDeliveryStatus(id: record.id, to: .copied)

        let rewritten = try JSONDecoder().decode(
            TranscriptRecord.self,
            from: Data(contentsOf: canonicalRecordURL(for: record.id, in: directory))
        )
        XCTAssertEqual(rewritten.deliveryStatus, .copied)
        XCTAssertEqual(rewritten.id, record.id)
        XCTAssertEqual(rewritten.localCleanedText, record.localCleanedText)
    }

    func testFailedDeliveryStatusUpdateSurfacesErrorAndKeepsPendingRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: canonicalRecordURL(for: makeRecord().id, in: directory).deletingLastPathComponent().path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        let record = makeRecord()
        let store = TranscriptStore(directory: directory)
        try store.save(record)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: canonicalRecordURL(for: record.id, in: directory).deletingLastPathComponent().path
        )

        XCTAssertThrowsError(try store.updateDeliveryStatus(id: record.id, to: .failed))
        XCTAssertEqual(try store.load(id: record.id).deliveryStatus, .pending)
    }

    func testRemoveSessionDeletesOnlyItsCanonicalBundleAndIsIdempotent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let store = TranscriptStore(directory: directory)
        try store.save(record)
        let bundleURL = canonicalRecordURL(for: record.id, in: directory).deletingLastPathComponent()
        try Data("audio".utf8).write(to: bundleURL.appendingPathComponent("audio.wav"))
        try JSONEncoder().encode(record).write(to: legacyRecordURL(for: record.id, in: directory))

        try store.removeSession(id: record.id)
        try store.removeSession(id: record.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyRecordURL(for: record.id, in: directory).path))
    }

    func testRemoveSessionRejectsASymlinkThatEscapesTheSessionsRoot() throws {
        let directory = try makeTemporaryDirectory()
        let outsideDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outsideDirectory)
        }
        let record = makeRecord()
        let outsideFile = outsideDirectory.appendingPathComponent("outside.txt")
        try Data("do not delete".utf8).write(to: outsideFile)
        let escapedBundleURL = canonicalRecordURL(for: record.id, in: directory).deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: escapedBundleURL, withDestinationURL: outsideDirectory)
        let store = TranscriptStore(directory: directory)

        XCTAssertThrowsError(try store.removeSession(id: record.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func canonicalRecordURL(for id: SessionID, in directory: URL) -> URL {
        directory
            .appendingPathComponent(id.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("record.json")
    }

    private func legacyRecordURL(for id: SessionID, in directory: URL) -> URL {
        directory
            .appendingPathComponent(id.rawValue.uuidString)
            .appendingPathExtension("json")
    }

    private func legacyEncodedData(for record: TranscriptRecord) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        ["outcome", "error", "finalSource", "languageSlice", "localEvaluationConsent", "reviewState", "intendedUse"].forEach {
            object.removeValue(forKey: $0)
        }
        return try JSONSerialization.data(withJSONObject: object)
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
