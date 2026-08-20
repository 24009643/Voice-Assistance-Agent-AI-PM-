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

    func testListPrefersCanonicalRecordsSkipsMalformedFilesAndSortsNewestFirst() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let canonical = makeRecord(id: "00000000-0000-0000-0000-000000000011", ordinal: 11, createdAt: 11)
        let legacy = makeRecord(id: "00000000-0000-0000-0000-000000000012", ordinal: 12, createdAt: 12)
        let staleLegacy = TranscriptRecord(
            id: canonical.id,
            ordinal: canonical.ordinal,
            createdAt: canonical.createdAt,
            durationMilliseconds: canonical.durationMilliseconds,
            detectedLanguages: canonical.detectedLanguages,
            originalText: "stale",
            localCleanedText: "stale",
            edits: [],
            deliveryStatus: .pending
        )
        let canonicalURL = canonicalRecordURL(for: canonical.id, in: directory)
        try FileManager.default.createDirectory(at: canonicalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(canonical).write(to: canonicalURL)
        try JSONEncoder().encode(staleLegacy).write(to: legacyRecordURL(for: canonical.id, in: directory))
        try JSONEncoder().encode(legacy).write(to: legacyRecordURL(for: legacy.id, in: directory))
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let malformedID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!)
        let malformedURL = canonicalRecordURL(for: malformedID, in: directory)
        try FileManager.default.createDirectory(at: malformedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: malformedURL)
        let store = TranscriptStore(directory: directory)

        XCTAssertEqual(try store.list(), [legacy, canonical])
    }

    func testListSkipsSymlinkedRecordsOutsideTheSessionsRoot() throws {
        let directory = try makeTemporaryDirectory()
        let outsideDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outsideDirectory)
        }
        let record = makeRecord(id: "00000000-0000-0000-0000-000000000014", ordinal: 14, createdAt: 14)
        let outsideRecordURL = canonicalRecordURL(for: record.id, in: outsideDirectory)
        try FileManager.default.createDirectory(at: outsideRecordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: outsideRecordURL)
        let escapedBundleURL = canonicalRecordURL(for: record.id, in: directory).deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: escapedBundleURL, withDestinationURL: outsideRecordURL.deletingLastPathComponent())
        let store = TranscriptStore(directory: directory)

        XCTAssertEqual(try store.list(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRecordURL.path))
    }

    func testListReportsCanonicalMissingAndNonRegularRecordFilesWithoutReadingThem() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = makeRecord(id: "00000000-0000-0000-0000-000000000015", ordinal: 15, createdAt: 15)
        let nonRegular = makeRecord(id: "00000000-0000-0000-0000-000000000016", ordinal: 16, createdAt: 16)
        let legacyNonRegular = makeRecord(id: "00000000-0000-0000-0000-000000000017", ordinal: 17, createdAt: 17)
        try FileManager.default.createDirectory(
            at: canonicalRecordURL(for: missing.id, in: directory).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: canonicalRecordURL(for: nonRegular.id, in: directory), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyRecordURL(for: legacyNonRegular.id, in: directory), withIntermediateDirectories: true)
        let store = TranscriptStore(directory: directory)

        XCTAssertEqual(try store.list(), [])
        XCTAssertEqual(store.skippedRecordCount, 3)
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

    func testUpdateOrganizationAtomicallyRewritesTheCanonicalRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let organization = makeOrganization()
        let store = TranscriptStore(directory: directory)
        try store.save(record)

        try store.updateOrganization(id: record.id, to: organization)

        let rewritten = try JSONDecoder().decode(
            TranscriptRecord.self,
            from: Data(contentsOf: canonicalRecordURL(for: record.id, in: directory))
        )
        XCTAssertEqual(rewritten.organization, organization)
        XCTAssertEqual(rewritten.originalText.data(using: .utf8), record.originalText.data(using: .utf8))
        XCTAssertEqual(rewritten.localCleanedText.data(using: .utf8), record.localCleanedText.data(using: .utf8))
    }

    func testUpdateOrganizationAtomicallyRewritesOnlyTheLegacyRecord() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = makeRecord()
        let legacyURL = legacyRecordURL(for: record.id, in: directory)
        try legacyEncodedData(for: record).write(to: legacyURL)
        let organization = makeOrganization()
        let store = TranscriptStore(directory: directory)

        try store.updateOrganization(id: record.id, to: organization)

        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalRecordURL(for: record.id, in: directory).path))
        let rewritten = try JSONDecoder().decode(TranscriptRecord.self, from: Data(contentsOf: legacyURL))
        XCTAssertEqual(rewritten.organization, organization)
        XCTAssertEqual(rewritten.originalText.data(using: .utf8), record.originalText.data(using: .utf8))
        XCTAssertEqual(rewritten.localCleanedText.data(using: .utf8), record.localCleanedText.data(using: .utf8))
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

    private func makeRecord(
        id: String = "00000000-0000-0000-0000-000000000004",
        ordinal: UInt64 = 4,
        createdAt: TimeInterval = 1_700_000_000
    ) -> TranscriptRecord {
        TranscriptRecord(
            id: SessionID(rawValue: UUID(uuidString: id)!),
            ordinal: SessionOrdinal(rawValue: ordinal),
            createdAt: Date(timeIntervalSince1970: createdAt),
            durationMilliseconds: 1_250,
            detectedLanguages: ["zh"],
            originalText: "原始文本",
            localCleanedText: "清理文本",
            edits: [],
            deliveryStatus: .pending
        )
    }

    private func makeOrganization() -> OrganizationRecord {
        OrganizationRecord(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            inputTextSHA256: "def456",
            state: .succeeded,
            provider: "Local",
            model: "organizer-v1",
            providerKind: .local,
            selectedRecordIDs: [],
            output: OrganizationOutput(
                noResultReason: nil,
                numberedPoints: [
                    NumberedPoint(number: 1, text: "摘要", sourceSegmentIDs: ["current-1"])
                ],
                knownRecordLinks: [],
                speculativeConnections: []
            ),
            errorCode: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
    }
}
