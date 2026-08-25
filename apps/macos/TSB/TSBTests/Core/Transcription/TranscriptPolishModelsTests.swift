import XCTest
@testable import TSB

final class TranscriptPolishModelsTests: XCTestCase {
    func testCandidateHashesItsTextAndPolishArtifactsRoundTrip() throws {
        let candidate = TranscriptCandidate(id: .offline, text: "local text")
        XCTAssertEqual(candidate.textSHA256, "3712bb0528399f0bd659fc77a737e23fb1bd8c4b6bf00735493c2a9186b61dcd")

        let polish = TranscriptPolishRecord(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            state: .accepted,
            baseCandidateID: .offline,
            polishedText: "polished",
            reviewCandidateText: nil,
            edits: [TranscriptPolishEdit(kind: .formatting, startUTF16: 0, lengthUTF16: 5, original: "local", replacement: "polished", reason: "format")],
            provider: "Local", model: "v1", providerKind: .local, sentCharacterCount: 10,
            elapsedMilliseconds: 25, errorCode: nil, updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(try JSONDecoder().decode(TranscriptPolishRecord.self, from: JSONEncoder().encode(polish)), polish)
    }
}
