import XCTest
@testable import TSB

final class ConservativeCleanerTests: XCTestCase {
    func testCleanerNormalizesWhitespaceAndRepeatedPunctuation() {
        let result = ConservativeCleaner().clean("  这个  想法。。不能  改！！  ")

        XCTAssertEqual(result.text, "这个 想法。不能 改！")
        XCTAssertFalse(result.edits.isEmpty)
    }

    func testCleanerPreservesMeaningBearingContent() {
        let source = "嗯，我不是要删除 2026-08-19，也不是 GPT-5.5"

        XCTAssertEqual(ConservativeCleaner().clean(source).text, source)
    }

    func testCleanerTrimsWhitespaceOnlyTextToEmpty() {
        let result = ConservativeCleaner().clean(" \n\t ")

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.edits.first?.kind, .trim)
    }
}
