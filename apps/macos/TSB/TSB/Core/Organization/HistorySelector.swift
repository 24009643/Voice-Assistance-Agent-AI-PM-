import Foundation
import NaturalLanguage

struct HistorySummaryDTO: Equatable, Sendable {
    let candidateID: String
    let summary: String
}

struct HistorySuggestions: Equatable, Sendable {
    let suggestedSummaries: [HistorySummaryDTO]
    let localRecordByCandidateID: [String: SessionID]
}

struct HistorySelector {
    private static let maximumRecords = 5
    private static let maximumCharactersPerSummary = 600

    func suggestions(for current: TranscriptRecord, from records: [TranscriptRecord]) -> HistorySuggestions {
        let currentTokens = tokens(in: current.localCleanedText)
        let ranked = records.compactMap { record -> (record: TranscriptRecord, points: [NumberedPoint], score: Int)? in
            guard record.id != current.id,
                  record.outcome == .success,
                  let organization = record.organization,
                  organization.state == .succeeded,
                  let output = organization.output,
                  !output.numberedPoints.isEmpty,
                  (try? output.validate()) != nil else { return nil }

            let score = currentTokens.intersection(tokens(in: output.numberedPoints.map(\.text).joined(separator: "\n"))).count
            guard score > 0 else { return nil }
            return (record, output.numberedPoints, score)
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.record.createdAt != $1.record.createdAt { return $0.record.createdAt > $1.record.createdAt }
            if $0.record.ordinal != $1.record.ordinal { return $0.record.ordinal > $1.record.ordinal }
            return $0.record.id.rawValue.uuidString > $1.record.id.rawValue.uuidString
        }

        var suggestedSummaries: [HistorySummaryDTO] = []
        var localRecordByCandidateID: [String: SessionID] = [:]
        for candidate in ranked.prefix(Self.maximumRecords) {
            let summary = summary(from: candidate.points)
            guard !summary.isEmpty else { continue }
            let candidateID = "h\(suggestedSummaries.count + 1)"
            suggestedSummaries.append(HistorySummaryDTO(candidateID: candidateID, summary: summary))
            localRecordByCandidateID[candidateID] = candidate.record.id
        }
        return HistorySuggestions(
            suggestedSummaries: suggestedSummaries,
            localRecordByCandidateID: localRecordByCandidateID
        )
    }

    private func summary(from points: [NumberedPoint]) -> String {
        let text = points.compactMap { point -> String? in
            let pointText = point.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return pointText.isEmpty ? nil : "\(point.number). \(pointText)"
        }.joined(separator: "\n")
        return String(text.prefix(Self.maximumCharactersPerSummary))
    }

    private func tokens(in text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result = Set<String>()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            result.insert(text[range].folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
            return true
        }
        return result
    }
}
