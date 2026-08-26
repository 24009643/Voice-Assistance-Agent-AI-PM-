import Foundation
import XCTest
@testable import TSB

final class OrganizationValidatorTests: XCTestCase {
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let recordID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
    private let inputHash = "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9"

    func testValidMixedLanguageFixturePassesStrictParserAndValidator() throws {
        let output = try makeAdversarialValidator().validate(try decodeStrictResponse(
            OrganizationAdversarialFixtures.validMixedLanguage
        ))

        XCTAssertEqual(output.numberedPoints.map(\.text), [
            "今天先完成 TSB 0.2 privacy check。",
            "跟住用廣東話驗證，唔好改原意。",
            "Finally, keep the original meaning."
        ])
        XCTAssertEqual(output.knownRecordLinks.map(\.recordID), [recordID])
        XCTAssertEqual(output.speculativeConnections.map(\.relatedRecordIDs), [[recordID]])
    }

    func testSemanticAdversarialFixturesRemainVerbatimForManualGoldenReview() throws {
        for (source, fixture, expectedText) in [
            (
                OrganizationAdversarialFixtures.meaningReversalSource,
                OrganizationAdversarialFixtures.meaningReversal,
                "上传音频。"
            ),
            (
                OrganizationAdversarialFixtures.inventedFactSource,
                OrganizationAdversarialFixtures.inventedFact,
                "用户已经批准把完整历史发送到云端。"
            )
        ] {
            let output = try makeAdversarialValidator(firstSegmentText: source).validate(try decodeStrictResponse(fixture))
            XCTAssertEqual(output.numberedPoints.map(\.text), [expectedText])
            XCTAssertNotEqual(output.numberedPoints.first?.text, source)
        }
    }

    func testAdversarialUnknownReferencesAreRejectedByValidator() throws {
        XCTAssertThrowsError(try makeAdversarialValidator().validate(try decodeStrictResponse(
            OrganizationAdversarialFixtures.unknownCandidate
        ))) { error in
            XCTAssertEqual(error as? OrganizationValidatorError, .unknownCandidateID("h9"))
        }
        XCTAssertThrowsError(try makeAdversarialValidator().validate(try decodeStrictResponse(
            OrganizationAdversarialFixtures.unknownCurrentSegment
        ))) { error in
            XCTAssertEqual(error as? OrganizationValidatorError, .unknownSegmentID("c9"))
        }
    }

    func testKnownAndSpeculativeCategoryMixingIsRejectedByStrictParser() {
        XCTAssertThrowsError(try decodeStrictResponse(OrganizationAdversarialFixtures.knownSpeculativeMixing))
    }

    func testMalformedFixtureIsRejectedByStrictParser() {
        XCTAssertThrowsError(try decodeStrictResponse(OrganizationAdversarialFixtures.malformed))
    }

    func testEmptyFixtureUsesAllowedNoResultReason() throws {
        let output = try makeAdversarialValidator().validate(try decodeStrictResponse(
            OrganizationAdversarialFixtures.empty
        ))

        XCTAssertEqual(output.noResultReason, .noReliableStructure)
        XCTAssertEqual(output.numberedPoints, [])
    }

    func testValidResponseResolvesOnlyFrozenCandidatesToLocalRecords() throws {
        let response = try decodeResponse("""
        {
          "schema_version": "tsb.organization.output.v1",
          "request_id": "00000000-0000-0000-0000-000000000101",
          "source_text_hash": "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9",
          "no_result_reason": null,
          "numbered_points": [
            {"number": 1, "text": "alpha", "source_segment_ids": ["c1"]},
            {"number": 2, "text": "beta", "source_segment_ids": ["c2"]}
          ],
          "known_record_links": [
            {"candidate_id": "h1", "reason": "same topic", "source_segment_ids": ["c1"]}
          ],
          "speculative_connections": [
            {
              "statement": "may extend the plan",
              "why_speculative": "not confirmed",
              "source_segment_ids": ["c2"],
              "candidate_ids": ["h1"]
            }
          ]
        }
        """)

        let output = try makeValidator().validate(response)

        XCTAssertEqual(output.numberedPoints.map(\.number), [1, 2])
        XCTAssertEqual(output.knownRecordLinks.map(\.recordID), [recordID])
        XCTAssertEqual(output.speculativeConnections.map(\.relatedRecordIDs), [[recordID]])
    }

    func testRejectsWrongSchemaRequestIDOrInputHash() throws {
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            schemaVersion: "tsb.organization.output.v2"
        ))))
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            requestID: "00000000-0000-0000-0000-000000000999"
        ))))
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            sourceTextHash: "wrong"
        ))))
    }

    func testRejectsUnknownOrEmptyCurrentSegmentReferences() throws {
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            sourceSegmentIDs: "[\"c9\"]"
        ))))
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            sourceSegmentIDs: "[]"
        ))))
    }

    func testRejectsUnknownCandidateReferencesBeforeLocalResolution() throws {
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            candidateID: "h9"
        ))))
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(validJSON(
            speculativeCandidateIDs: "[\"h9\"]"
        ))))
    }

    func testRejectsNonconsecutivePointNumbers() throws {
        let json = validJSON(pointNumber: 2)

        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(json)))
    }

    func testEmptyResultRequiresAnAllowedNoResultReason() throws {
        XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(emptyJSON(reason: "null"))))

        let insufficient = try makeValidator().validate(try decodeResponse(emptyJSON(reason: "\"insufficient_content\"")))
        let unstructured = try makeValidator().validate(try decodeResponse(emptyJSON(reason: "\"no_reliable_structure\"")))

        XCTAssertEqual(insufficient.noResultReason, .insufficientContent)
        XCTAssertEqual(unstructured.noResultReason, .noReliableStructure)
    }

    func testUserVisibleTextMustBeNonemptyAfterTrimming() throws {
        for json in [
            validJSON(pointText: "   "),
            validJSON(linkReason: "   "),
            validJSON(speculativeStatement: "   "),
            validJSON(speculativeRationale: "   ")
        ] {
            XCTAssertThrowsError(try makeValidator().validate(try decodeResponse(json)))
        }

        let output = try makeValidator().validate(try decodeResponse(validJSON(
            pointText: " point ",
            linkReason: " reason ",
            speculativeStatement: " statement ",
            speculativeRationale: " rationale "
        )))
        XCTAssertEqual(output.numberedPoints.map(\.text), ["point"])
        XCTAssertEqual(output.knownRecordLinks.map(\.reason), ["reason"])
        XCTAssertEqual(output.speculativeConnections.map(\.statement), ["statement"])
        XCTAssertEqual(output.speculativeConnections.map(\.whySpeculative), ["rationale"])
    }

    func testRejectsExcessiveOutputItemsAndVisibleText() throws {
        let excessivePoints = (1...(OrganizationValidator.maximumNumberedPoints + 1)).map {
            NumberedPointDTO(number: $0, text: "point", sourceSegmentIDs: ["c1"])
        }
        let excessiveItemResponse = OrganizationResponseDTO(
            schemaVersion: "tsb.organization.output.v1",
            requestID: requestID,
            sourceTextHash: inputHash,
            noResultReason: nil,
            numberedPoints: excessivePoints,
            knownRecordLinks: [],
            speculativeConnections: []
        )
        XCTAssertThrowsError(try makeValidator().validate(excessiveItemResponse)) { error in
            XCTAssertEqual(error as? OrganizationValidatorError, .responseLimitExceeded)
        }

        let excessiveTextResponse = OrganizationResponseDTO(
            schemaVersion: "tsb.organization.output.v1",
            requestID: requestID,
            sourceTextHash: inputHash,
            noResultReason: nil,
            numberedPoints: [NumberedPointDTO(
                number: 1,
                text: String(repeating: "a", count: OrganizationValidator.maximumVisibleTextCharacters + 1),
                sourceSegmentIDs: ["c1"]
            )],
            knownRecordLinks: [],
            speculativeConnections: []
        )
        XCTAssertThrowsError(try makeValidator().validate(excessiveTextResponse)) { error in
            XCTAssertEqual(error as? OrganizationValidatorError, .responseLimitExceeded)
        }
    }

    private func makeValidator() throws -> OrganizationValidator {
        OrganizationValidator(
            requestID: requestID,
            inputTextSHA256: inputHash,
            currentSegmentByID: [
                "c1": try TextSegment(id: "c1", text: "alpha"),
                "c2": try TextSegment(id: "c2", text: "beta")
            ],
            recordByCandidateID: ["h1": recordID]
        )
    }

    private func makeAdversarialValidator(
        firstSegmentText: String = "今天先完成 TSB 0.2 privacy check。"
    ) throws -> OrganizationValidator {
        OrganizationValidator(
            requestID: UUID(uuidString: OrganizationAdversarialFixtures.requestID)!,
            inputTextSHA256: OrganizationAdversarialFixtures.sourceTextHash,
            currentSegmentByID: [
                "c1": try TextSegment(id: "c1", text: firstSegmentText),
                "c2": try TextSegment(id: "c2", text: "跟住用廣東話驗證，唔好改原意。"),
                "c3": try TextSegment(id: "c3", text: "Finally, keep the original meaning.")
            ],
            recordByCandidateID: ["h1": recordID]
        )
    }

    private func decodeResponse(_ json: String) throws -> OrganizationResponseDTO {
        try JSONDecoder().decode(OrganizationResponseDTO.self, from: Data(json.utf8))
    }

    private func decodeStrictResponse(_ json: String) throws -> OrganizationResponseDTO {
        try OrganizationResponseDTO.decodeStrictly(from: Data(json.utf8))
    }

    private func validJSON(
        schemaVersion: String = "tsb.organization.output.v1",
        requestID: String = "00000000-0000-0000-0000-000000000101",
        sourceTextHash: String = "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9",
        pointNumber: Int = 1,
        sourceSegmentIDs: String = "[\"c1\"]",
        candidateID: String = "h1",
        speculativeCandidateIDs: String = "[\"h1\"]",
        pointText: String = "alpha",
        linkReason: String = "same topic",
        speculativeStatement: String = "possible",
        speculativeRationale: String = "unconfirmed"
    ) -> String {
        """
        {
          "schema_version": "\(schemaVersion)",
          "request_id": "\(requestID)",
          "source_text_hash": "\(sourceTextHash)",
          "no_result_reason": null,
          "numbered_points": [
            {"number": \(pointNumber), "text": "\(pointText)", "source_segment_ids": \(sourceSegmentIDs)}
          ],
          "known_record_links": [
            {"candidate_id": "\(candidateID)", "reason": "\(linkReason)", "source_segment_ids": ["c1"]}
          ],
          "speculative_connections": [
            {
              "statement": "\(speculativeStatement)",
              "why_speculative": "\(speculativeRationale)",
              "source_segment_ids": ["c1"],
              "candidate_ids": \(speculativeCandidateIDs)
            }
          ]
        }
        """
    }

    private func emptyJSON(reason: String) -> String {
        """
        {
          "schema_version": "tsb.organization.output.v1",
          "request_id": "00000000-0000-0000-0000-000000000101",
          "source_text_hash": "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9",
          "no_result_reason": \(reason),
          "numbered_points": [],
          "known_record_links": [],
          "speculative_connections": []
        }
        """
    }
}
