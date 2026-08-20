import Foundation
import NaturalLanguage

struct DeterministicOrganizer {
    func segments(from text: String) throws -> [TextSegment] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var texts: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let unit = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !unit.isEmpty { texts.append(unit) }
            return true
        }
        return try texts.enumerated().map { offset, text in
            try TextSegment(id: "c\(offset + 1)", text: text)
        }
    }

    func organize(segments: [TextSegment]) throws -> OrganizationOutput {
        let output = OrganizationOutput(
            noResultReason: segments.isEmpty ? .insufficientContent : nil,
            numberedPoints: segments.enumerated().map { offset, segment in
                NumberedPoint(number: offset + 1, text: segment.text, sourceSegmentIDs: [segment.id])
            },
            knownRecordLinks: [],
            speculativeConnections: []
        )
        try output.validate()
        return output
    }
}
