import Foundation
import XCTest
@testable import TSB

final class HistorySelectorTests: XCTestCase {
    func testSuggestionsExcludeCurrentFailedAndEmptyRecordsAndUseOnlySucceededNumberedPoints() throws {
        let current = makeRecord(id: 1, text: "roadmap")
        let valid = makeRecord(
            id: 2,
            text: "roadmap draft",
            organization: organization(points: ["roadmap draft", "owners"])
        )
        let failedTranscript = makeRecord(
            id: 3,
            text: "roadmap",
            outcome: .transcriptionFailed,
            organization: organization(points: ["roadmap should not appear"])
        )
        let failedOrganization = makeRecord(
            id: 4,
            text: "roadmap",
            organization: organization(state: .failed, points: ["roadmap should not appear"])
        )
        let emptyOrganization = makeRecord(id: 5, text: "roadmap", organization: organization(points: []))
        let selector = HistorySelector()

        let suggestions = selector.suggestions(for: current, from: [current, failedTranscript, failedOrganization, emptyOrganization, valid])

        XCTAssertEqual(suggestions.suggestedSummaries, [
            HistorySummaryDTO(candidateID: "h1", summary: "1. roadmap draft\n2. owners")
        ])
        XCTAssertEqual(suggestions.localRecordByCandidateID, ["h1": valid.id])
    }

    func testSuggestionsAreBoundedToFiveRecordsSixHundredCharactersEachAndThreeThousandTotal() throws {
        let current = makeRecord(id: 1, text: "project")
        let records = (2...7).map { id in
            makeRecord(
                id: id,
                text: "project",
                createdAt: TimeInterval(id),
                organization: organization(points: ["project " + String(repeating: "x", count: 700)])
            )
        }
        let selector = HistorySelector()

        let suggestions = selector.suggestions(for: current, from: records)

        XCTAssertEqual(suggestions.suggestedSummaries.map(\.candidateID), ["h1", "h2", "h3", "h4", "h5"])
        XCTAssertEqual(suggestions.suggestedSummaries.count, 5)
        XCTAssertTrue(suggestions.suggestedSummaries.allSatisfy { $0.summary.count <= 600 })
        XCTAssertLessThanOrEqual(suggestions.suggestedSummaries.reduce(0) { $0 + $1.summary.count }, 3_000)
        XCTAssertEqual(Set(suggestions.localRecordByCandidateID.values), Set(records.suffix(5).map(\.id)))
    }

    func testSuggestionsRequirePositiveTextRelevanceAndUseRecencyOnlyToBreakEqualScores() throws {
        let current = makeRecord(id: 1, text: "project alpha plan")
        let newestWeak = makeRecord(id: 2, text: "project", createdAt: 40, organization: organization(points: ["project"] ))
        let olderEqual = makeRecord(id: 3, text: "alpha", createdAt: 20, organization: organization(points: ["alpha"] ))
        let newestEqual = makeRecord(id: 4, text: "alpha", createdAt: 30, organization: organization(points: ["alpha"] ))
        let oldestBest = makeRecord(id: 5, text: "project alpha", createdAt: 10, organization: organization(points: ["project alpha"] ))
        let unrelated = makeRecord(id: 6, text: "grocery", createdAt: 50, organization: organization(points: ["grocery"] ))
        let selector = HistorySelector()

        let suggestions = selector.suggestions(
            for: current,
            from: [newestWeak, olderEqual, newestEqual, oldestBest, unrelated]
        )

        XCTAssertEqual(suggestions.suggestedSummaries.map(\.summary), ["1. project alpha", "1. project", "1. alpha", "1. alpha"])
        XCTAssertEqual(
            suggestions.suggestedSummaries.map(\.candidateID).compactMap { suggestions.localRecordByCandidateID[$0] },
            [oldestBest.id, newestWeak.id, newestEqual.id, olderEqual.id]
        )
    }

    func testSuggestionsAreEmptyWhenNoPriorSummaryOverlapsCurrentText() throws {
        let current = makeRecord(id: 1, text: "project")
        let unrelated = makeRecord(id: 2, text: "grocery", organization: organization(points: ["grocery"] ))

        XCTAssertEqual(HistorySelector().suggestions(for: current, from: [unrelated]).suggestedSummaries, [])
    }

    private func makeRecord(
        id: Int,
        text: String,
        createdAt: TimeInterval = 0,
        outcome: TranscriptOutcome = .success,
        organization: OrganizationRecord? = nil
    ) -> TranscriptRecord {
        TranscriptRecord(
            id: SessionID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!),
            ordinal: SessionOrdinal(rawValue: UInt64(id)),
            createdAt: Date(timeIntervalSince1970: createdAt),
            durationMilliseconds: 1,
            detectedLanguages: ["en"],
            originalText: text,
            localCleanedText: text,
            edits: [],
            deliveryStatus: .pending,
            outcome: outcome,
            organization: organization
        )
    }

    private func organization(
        state: OrganizationPersistenceState = .succeeded,
        points: [String]
    ) -> OrganizationRecord {
        OrganizationRecord(
            requestID: UUID(),
            inputTextSHA256: "hash",
            state: state,
            provider: "local",
            model: "model",
            providerKind: .local,
            selectedRecordIDs: [],
            output: OrganizationOutput(
                noResultReason: nil,
                numberedPoints: points.enumerated().map {
                    NumberedPoint(number: $0.offset + 1, text: $0.element, sourceSegmentIDs: ["current-1"])
                },
                knownRecordLinks: [],
                speculativeConnections: []
            ),
            errorCode: nil,
            updatedAt: Date()
        )
    }
}
