import XCTest
@testable import TSB

final class DeterministicOrganizerTests: XCTestCase {
    func testReturnsStableNumberedTranscriptUnitsWithoutSemanticClaims() throws {
        let organizer = DeterministicOrganizer()

        let segments = try organizer.segments(from: "第一件事。第二件事！\nThird item.")
        let output = try organizer.organize(segments: segments)

        XCTAssertEqual(segments.map(\.id), ["c1", "c2", "c3"])
        XCTAssertEqual(segments.map(\.text), ["第一件事。", "第二件事！", "Third item."])
        XCTAssertEqual(output.numberedPoints, [
            NumberedPoint(number: 1, text: "第一件事。", sourceSegmentIDs: ["c1"]),
            NumberedPoint(number: 2, text: "第二件事！", sourceSegmentIDs: ["c2"]),
            NumberedPoint(number: 3, text: "Third item.", sourceSegmentIDs: ["c3"])
        ])
        XCTAssertNil(output.noResultReason)
        XCTAssertEqual(output.knownRecordLinks, [])
        XCTAssertEqual(output.speculativeConnections, [])
    }

    func testBlankTranscriptReturnsExplicitInsufficientContent() throws {
        let organizer = DeterministicOrganizer()

        let segments = try organizer.segments(from: "  \n\t")
        let output = try organizer.organize(segments: segments)

        XCTAssertEqual(segments, [])
        XCTAssertEqual(output.noResultReason, .insufficientContent)
        XCTAssertEqual(output.numberedPoints, [])
    }
}
