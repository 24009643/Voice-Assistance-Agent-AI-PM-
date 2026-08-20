import Foundation
import XCTest
@testable import TSB

final class OrganizationModelsTests: XCTestCase {
    func testTextSegmentRejectsEmptyRequestLocalIDOrText() throws {
        let segment = try TextSegment(id: "current-1", text: "当前文本")

        XCTAssertEqual(segment.id, "current-1")
        XCTAssertEqual(segment.text, "当前文本")
        XCTAssertThrowsError(try TextSegment(id: "", text: "当前文本"))
        XCTAssertThrowsError(try TextSegment(id: "current-1", text: ""))
    }

    func testOrganizationOutputRejectsNonconsecutivePointNumbers() {
        let output = OrganizationOutput(
            noResultReason: nil,
            numberedPoints: [
                NumberedPoint(number: 1, text: "第一点", sourceSegmentIDs: ["current-1"]),
                NumberedPoint(number: 3, text: "第三点", sourceSegmentIDs: ["current-1"])
            ],
            knownRecordLinks: [],
            speculativeConnections: []
        )

        XCTAssertThrowsError(try output.validate())
    }

    func testOrganizationOutputRejectsEmptySourceSegmentIDs() {
        let output = OrganizationOutput(
            noResultReason: nil,
            numberedPoints: [
                NumberedPoint(number: 1, text: "第一点", sourceSegmentIDs: [])
            ],
            knownRecordLinks: [],
            speculativeConnections: []
        )

        XCTAssertThrowsError(try output.validate())
    }

    func testOrganizationOutputRetainsKnownRecordLinksAfterLocalResolution() throws {
        let linkedRecordID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!)
        let output = OrganizationOutput(
            noResultReason: nil,
            numberedPoints: [],
            knownRecordLinks: [
                KnownRecordLink(
                    recordID: linkedRecordID,
                    reason: "与当前主题相关",
                    sourceSegmentIDs: ["current-1"]
                )
            ],
            speculativeConnections: []
        )

        try output.validate()

        XCTAssertEqual(output.knownRecordLinks.first?.recordID, linkedRecordID)
    }
}
