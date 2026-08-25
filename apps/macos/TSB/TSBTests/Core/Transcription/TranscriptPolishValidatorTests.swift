import XCTest
@testable import TSB

final class TranscriptPolishValidatorTests: XCTestCase {
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    func testAcceptsFormattingAndTerminologyEditsThatReproduceText() throws {
        let request = makeRequest(offline: "Use TB  now for this dictation", streaming: "Use TSB now for this dictation")
        let data = response(for: request, base: .offline, corrected: "Use TSB now for this dictation", edits: [
            edit(.terminology, 4, 2, "TB", "TSB", "approved alias"),
            edit(.formatting, 6, 2, "  ", " ", "spacing")
        ])
        let outcome = try TranscriptPolishValidator().validate(data, for: request)
        XCTAssertEqual(outcome, .accepted(baseCandidateID: .offline, text: "Use TSB now for this dictation", edits: [
            edit(.terminology, 4, 2, "TB", "TSB", "approved alias"),
            edit(.formatting, 6, 2, "  ", " ", "spacing")
        ]))
    }

    func testContextOnlyRewriteRequiresReview() throws {
        let request = makeRequest(offline: "清版内容保持原样而且不会丢失")
        let outcome = try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: "这一版内容保持原样而且不会丢失", edits: [edit(.candidateSupported, 0, 2, "清版", "这一版", "context")]), for: request)
        guard case .reviewRequired = outcome else { return XCTFail("must not auto-accept") }
    }

    func testRejectsUnknownKeysAndHashMismatches() throws {
        let request = makeRequest(offline: "alpha")
        var object = try json(response(for: request, base: .offline, corrected: "alpha", edits: []))
        object["unexpected"] = true
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(try encoded(object), for: request))
        object.removeValue(forKey: "unexpected")
        var hashes = try XCTUnwrap(object["candidate_hashes"] as? [[String: Any]])
        hashes[0]["text_sha256"] = String(repeating: "0", count: 64)
        object["candidate_hashes"] = hashes
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(try encoded(object), for: request))
    }

    func testRejectsOverlappingOrNonReproducibleEditsAndExcessiveChanges() throws {
        let request = makeRequest(offline: "abcdefghij")
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: "XYcdefghij", edits: [edit(.formatting, 0, 1, "a", "X", "x"), edit(.formatting, 0, 1, "a", "Y", "y")]), for: request))
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: "xxxxxxxxxx", edits: [edit(.formatting, 0, 10, "abcdefghij", "xxxxxxxxxx", "not formatting")]), for: request))
    }

    func testRejectsChangesToNumbersURLsAndEmails() throws {
        for pair in [("Call 123", "Call 124"), ("https://example.test/a", "https://example.test/b"), ("me@example.test", "you@example.test")] {
            let request = makeRequest(offline: pair.0)
            XCTAssertThrowsError(try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: pair.1, edits: [edit(.formatting, 0, pair.0.utf16.count, pair.0, pair.1, "bad")]), for: request))
        }
    }

    func testRejectsSmallImmutableChangesAndBooleanOrOverflowedRanges() throws {
        let request = makeRequest(offline: "call 12345 safely today")
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: "call 12346 safely today", edits: [edit(.formatting, 8, 1, "5", "6", "bad")]), for: request))
        var object = try json(response(for: request, base: .offline, corrected: "call 12345 safely today", edits: []))
        object["edits"] = [["kind": "formatting", "start_utf16": true, "length_utf16": 0, "original": "", "replacement": "", "reason": "bad"]]
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(try encoded(object), for: request))
        object["edits"] = [["kind": "formatting", "start_utf16": Int.max, "length_utf16": 1, "original": "", "replacement": "", "reason": "bad"]]
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(try encoded(object), for: request))
    }

    func testRejectsZeroLengthInsertionBeyondChangeLimitAndUnanchoredCandidateEvidence() throws {
        let request = makeRequest(offline: String(repeating: "a", count: 20), streaming: "xxxxEARTHyyyy")
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: String(repeating: "a", count: 20) + "abcdef", edits: [edit(.formatting, 20, 0, "", "abcdef", "insert")]), for: request))
        let base = "left xxxx right and trailing content"
        let unanchored = makeRequest(offline: base, streaming: "left earth elsewhere xxxx right")
        let review = try TranscriptPolishValidator().validate(response(for: unanchored, base: .offline, corrected: "left earth right and trailing content", edits: [edit(.candidateSupported, 5, 4, "xxxx", "earth", "bad anchors")]), for: unanchored)
        guard case .reviewRequired = review else { return XCTFail("must not accept separately occurring anchors") }
    }

    func testCandidateSupportedNeedsOtherCandidateAnchorEvidence() throws {
        let request = makeRequest(offline: "hello world today and keep the rest", streaming: "hello earth today and keep the rest")
        let accepted = try TranscriptPolishValidator().validate(response(for: request, base: .offline, corrected: "hello earth today and keep the rest", edits: [edit(.candidateSupported, 6, 5, "world", "earth", "other candidate")]), for: request)
        guard case .accepted = accepted else { return XCTFail("anchored alternate must be accepted") }
        let noSupport = makeRequest(offline: "hello world today and keep the rest", streaming: "different entirely")
        let review = try TranscriptPolishValidator().validate(response(for: noSupport, base: .offline, corrected: "hello earth today and keep the rest", edits: [edit(.candidateSupported, 6, 5, "world", "earth", "context")]), for: noSupport)
        guard case .reviewRequired = review else { return XCTFail("unsupported candidate change must require review") }
    }

    func testCandidateSupportRequiresPrefixAndSuffixAtTextBoundaries() throws {
        let prefix = makeRequest(offline: "wrong tail long enough for stable evidence", streaming: "noise right tail long enough for stable evidence")
        let prefixOutcome = try TranscriptPolishValidator().validate(response(for: prefix, base: .offline, corrected: "right tail long enough for stable evidence", edits: [edit(.candidateSupported, 0, 5, "wrong", "right", "boundary")]), for: prefix)
        guard case .reviewRequired = prefixOutcome else { return XCTFail("replacement not at other prefix") }
        let suffix = makeRequest(offline: "long enough start stays stable until wrong", streaming: "long enough start stays stable until right noise")
        let suffixOutcome = try TranscriptPolishValidator().validate(response(for: suffix, base: .offline, corrected: "long enough start stays stable until right", edits: [edit(.candidateSupported, 37, 5, "wrong", "right", "boundary")]), for: suffix)
        guard case .reviewRequired = suffixOutcome else { return XCTFail("replacement not at other suffix") }
    }

    func testRejectsInnerResponseOver48KiB() throws {
        let request = makeRequest(offline: "a")
        XCTAssertThrowsError(try TranscriptPolishValidator().validate(Data(repeating: 0x20, count: TranscriptPolishClient.maximumInnerBytes + 1), for: request))
    }

    private func makeRequest(offline: String, streaming: String? = nil) -> TranscriptPolishRequest {
        TranscriptPolishRequest(requestID: requestID, candidates: [TranscriptCandidate(id: .offline, text: offline)] + (streaming.map { [TranscriptCandidate(id: .streaming, text: $0)] } ?? []), terminology: [TranscriptTerminologyEntry(canonical: "TSB", aliases: ["TB"])])
    }

    private func response(for request: TranscriptPolishRequest, base: TranscriptCandidate.ID, corrected: String, edits: [TranscriptPolishEdit]) -> Data {
        try! encoded(["schema_version": "tsb.transcript_polish.response.v1", "request_id": request.requestID.uuidString.lowercased(), "candidate_hashes": request.candidates.map { ["candidate_id": $0.id.rawValue, "text_sha256": $0.textSHA256] }, "base_candidate_id": base.rawValue, "corrected_text": corrected, "edits": edits.map { ["kind": $0.kind.rawValue, "start_utf16": $0.startUTF16, "length_utf16": $0.lengthUTF16, "original": $0.original, "replacement": $0.replacement, "reason": $0.reason] }])
    }

    private func edit(_ kind: TranscriptPolishEditKind, _ start: Int, _ length: Int, _ original: String, _ replacement: String, _ reason: String) -> TranscriptPolishEdit { .init(kind: kind, startUTF16: start, lengthUTF16: length, original: original, replacement: replacement, reason: reason) }
    private func json(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
    private func encoded(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
}
