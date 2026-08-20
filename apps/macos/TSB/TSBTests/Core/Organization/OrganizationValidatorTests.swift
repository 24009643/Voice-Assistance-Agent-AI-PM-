import Foundation
import XCTest
@testable import TSB

final class OrganizationValidatorTests: XCTestCase {
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let recordID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
    private let inputHash = "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9"

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

    private func decodeResponse(_ json: String) throws -> OrganizationResponseDTO {
        try JSONDecoder().decode(OrganizationResponseDTO.self, from: Data(json.utf8))
    }

    private func validJSON(
        schemaVersion: String = "tsb.organization.output.v1",
        requestID: String = "00000000-0000-0000-0000-000000000101",
        sourceTextHash: String = "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9",
        pointNumber: Int = 1,
        sourceSegmentIDs: String = "[\"c1\"]",
        candidateID: String = "h1",
        speculativeCandidateIDs: String = "[\"h1\"]"
    ) -> String {
        """
        {
          "schema_version": "\(schemaVersion)",
          "request_id": "\(requestID)",
          "source_text_hash": "\(sourceTextHash)",
          "no_result_reason": null,
          "numbered_points": [
            {"number": \(pointNumber), "text": "alpha", "source_segment_ids": \(sourceSegmentIDs)}
          ],
          "known_record_links": [
            {"candidate_id": "\(candidateID)", "reason": "same topic", "source_segment_ids": ["c1"]}
          ],
          "speculative_connections": [
            {
              "statement": "possible",
              "why_speculative": "unconfirmed",
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
