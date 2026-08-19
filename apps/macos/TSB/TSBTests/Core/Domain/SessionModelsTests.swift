import Foundation
import XCTest
@testable import TSB

final class SessionModelsTests: XCTestCase {
    func testTranscriptRecordRoundTripsWithoutOverwritingOriginal() throws {
        let record = TranscriptRecord(
            id: SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            ordinal: SessionOrdinal(rawValue: 1),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationMilliseconds: 1_500,
            detectedLanguages: ["zh"],
            originalText: "嗯 这个想法不能删",
            localCleanedText: "嗯 这个想法不能删",
            edits: [],
            deliveryStatus: .pending
        )

        let decoded = try JSONDecoder().decode(TranscriptRecord.self, from: JSONEncoder().encode(record))

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.originalText, "嗯 这个想法不能删")
    }

    func testTranscriptRecordPersistsBothASRCandidates() throws {
        let record = TranscriptRecord(
            id: SessionID(rawValue: UUID()),
            ordinal: SessionOrdinal(rawValue: 3),
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            durationMilliseconds: 900,
            detectedLanguages: ["zh"],
            originalText: "SenseVoice final",
            localCleanedText: "SenseVoice final",
            edits: [],
            deliveryStatus: .pending,
            finalSource: .senseVoice,
            streamingText: "Paraformer draft",
            senseVoiceText: "SenseVoice final"
        )

        let decoded = try JSONDecoder().decode(TranscriptRecord.self, from: JSONEncoder().encode(record))

        XCTAssertEqual(decoded.streamingText, "Paraformer draft")
        XCTAssertEqual(decoded.senseVoiceText, "SenseVoice final")
    }

    func testTranscriptRecordEncodesRetainedSessionDefaultsAndDecodesLegacyRecords() throws {
        let record = TranscriptRecord(
            id: SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            ordinal: SessionOrdinal(rawValue: 2),
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            durationMilliseconds: 800,
            detectedLanguages: ["en"],
            originalText: "keep this",
            localCleanedText: "keep this",
            edits: [],
            deliveryStatus: .pending
        )
        let encoded = try JSONEncoder().encode(record)
        let fields = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(fields?["outcome"] as? String, "success")
        XCTAssertEqual(fields?["finalSource"] as? String, "senseVoice")
        XCTAssertNil(fields?["localEvaluationConsent"])
        XCTAssertEqual(fields?["reviewState"] as? String, "unreviewed")
        XCTAssertEqual(fields?["intendedUse"] as? String, "localEvaluation")
        XCTAssertEqual(
            try JSONDecoder().decode(TranscriptRecord.self, from: encoded),
            record
        )

        var legacyFields = try XCTUnwrap(fields)
        legacyFields.removeValue(forKey: "streamingText")
        legacyFields.removeValue(forKey: "senseVoiceText")
        let legacy = try JSONSerialization.data(withJSONObject: legacyFields)
        let decodedLegacy = try JSONDecoder().decode(TranscriptRecord.self, from: legacy)
        XCTAssertNil(decodedLegacy.streamingText)
        XCTAssertNil(decodedLegacy.senseVoiceText)
    }
}
