import XCTest
@testable import TSB

final class TranscriptTerminologyTests: XCTestCase {
    func testLongestApprovedAliasWinsAndProducesUTF16Trace() throws {
        let entries = [
            TranscriptTerminologyEntry(canonical: "TSB", aliases: ["T B", "TB"]),
            TranscriptTerminologyEntry(canonical: "Keychain", aliases: ["key chain"]),
        ]

        let result = TranscriptTerminologyCorrector().correct("T B uses key chain", entries: entries)

        XCTAssertEqual(result.text, "TSB uses Keychain")
        XCTAssertEqual(result.edits.map(\.canonical), ["TSB", "Keychain"])
        XCTAssertEqual(result.edits.map(\.startUTF16), [0, 9])
        XCTAssertEqual(result.edits.map(\.lengthUTF16), [3, 9])
    }

    func testParserTrimsAndRejectsDuplicateOrAmbiguousAliases() throws {
        XCTAssertEqual(
            try TranscriptTerminologyParser.parse(" TSB = T B | TB \nKeychain = key chain "),
            [
                TranscriptTerminologyEntry(canonical: "TSB", aliases: ["T B", "TB"]),
                TranscriptTerminologyEntry(canonical: "Keychain", aliases: ["key chain"]),
            ]
        )
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("TSB = TB\nOther = TB"))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("TSB = TB | TB"))
    }

    func testParserRejectsBlankFieldsAndSpecifiedLimits() throws {
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse(" = alias"))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("Canonical = "))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("Canonical alias"))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse((0...64).map { "C\($0) = a\($0)" }.joined(separator: "\n")))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("C = " + (0...8).map { "a\($0)" }.joined(separator: " | ")))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("C = " + String(repeating: "a", count: 81)))
        XCTAssertThrowsError(try TranscriptTerminologyParser.parse("C = a\n" + String(repeating: "x", count: 4_097)))
    }

    func testCorrectorHonorsLatinWordBoundariesAndAppliesEditsFromTheEnd() {
        let entries = [
            TranscriptTerminologyEntry(canonical: "T S B", aliases: ["TSB"]),
            TranscriptTerminologyEntry(canonical: "TypeScript", aliases: ["TS"]),
        ]

        let result = TranscriptTerminologyCorrector().correct("TSB, TS and XTSY", entries: entries)

        XCTAssertEqual(result.text, "T S B, TypeScript and XTSY")
        XCTAssertEqual(result.edits.map(\.original), ["TSB", "TS"])
    }

    func testCorrectorDoesNotReplaceMultiwordLatinAliasesInsideWords() {
        let entries = [
            TranscriptTerminologyEntry(canonical: "Keychain", aliases: ["key chain"]),
            TranscriptTerminologyEntry(canonical: "TSB", aliases: ["T B"]),
        ]

        let result = TranscriptTerminologyCorrector().correct("monkey chainmail and XT Bx", entries: entries)

        XCTAssertEqual(result.text, "monkey chainmail and XT Bx")
        XCTAssertTrue(result.edits.isEmpty)
    }

    func testCorrectorTreatsUnicodeLatinLettersAsBoundariesButKeepsChineseAdjacentAlias() {
        let entries = [TranscriptTerminologyEntry(canonical: "TSB", aliases: ["TB"])]

        let result = TranscriptTerminologyCorrector().correct("éTBé 与 中TB文", entries: entries)

        XCTAssertEqual(result.text, "éTBé 与 中TSB文")
        XCTAssertEqual(result.edits.map(\.original), ["TB"])
    }

    func testParsedAliasHonorsDecomposedLatinGraphemeBoundariesAndStandaloneCases() throws {
        let entries = try TranscriptTerminologyParser.parse("TSB = TB")
        let source = "e\u{301}TBé e\u{301}TB 中TB文 TB"

        let result = TranscriptTerminologyCorrector().correct(source, entries: entries)

        XCTAssertEqual(result.text, "e\u{301}TBé e\u{301}TB 中TSB文 TSB")
        XCTAssertEqual(result.edits.map(\.original), ["TB", "TB"])
    }
}
