import Foundation

struct TranscriptTerminologyEntry: Equatable, Codable, Sendable {
    let canonical: String
    let aliases: [String]
}

struct TranscriptTerminologyEdit: Equatable, Codable, Sendable {
    let startUTF16: Int
    let lengthUTF16: Int
    let original: String
    let replacement: String
    let canonical: String
}

struct TranscriptTerminologyResult: Equatable, Sendable {
    let text: String
    let edits: [TranscriptTerminologyEdit]
}

enum TranscriptTerminologyParserError: Error, Equatable {
    case invalidEntry
    case duplicateAlias
    case tooManyEntries
    case tooManyAliases
    case fieldTooLong
    case inputTooLong
}

enum TranscriptTerminologyParser {
    static func parse(_ text: String) throws -> [TranscriptTerminologyEntry] {
        guard text.unicodeScalars.count <= 4_096 else { throw TranscriptTerminologyParserError.inputTooLong }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count <= 64 else { throw TranscriptTerminologyParserError.tooManyEntries }
        var seenAliases = Set<String>()
        var entries: [TranscriptTerminologyEntry] = []

        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw TranscriptTerminologyParserError.invalidEntry }
            let canonical = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let aliases = parts[1].split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !canonical.isEmpty, !aliases.isEmpty, aliases.allSatisfy({ !$0.isEmpty }) else {
                throw TranscriptTerminologyParserError.invalidEntry
            }
            guard canonical.unicodeScalars.count <= 80, aliases.allSatisfy({ $0.unicodeScalars.count <= 80 }) else {
                throw TranscriptTerminologyParserError.fieldTooLong
            }
            guard aliases.count <= 8 else { throw TranscriptTerminologyParserError.tooManyAliases }
            guard aliases.allSatisfy({ seenAliases.insert($0).inserted }) else {
                throw TranscriptTerminologyParserError.duplicateAlias
            }
            entries.append(TranscriptTerminologyEntry(canonical: canonical, aliases: aliases))
        }
        return entries
    }
}

struct TranscriptTerminologyCorrector: Sendable {
    func correct(_ text: String, entries: [TranscriptTerminologyEntry]) -> TranscriptTerminologyResult {
        let aliases = entries.flatMap { entry in entry.aliases.map { ($0, entry.canonical) } }
            .sorted { $0.0.utf16.count > $1.0.utf16.count }
        var matches: [(range: NSRange, original: String, replacement: String)] = []

        for (alias, canonical) in aliases where !alias.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: alias)
            let pattern = alias.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
                ? "(?<![[:alnum:]])\(escaped)(?![[:alnum:]])"
                : escaped
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for range in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range) {
                guard !matches.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { continue }
                matches.append((range, (text as NSString).substring(with: range), canonical))
            }
        }
        matches.sort { $0.range.location < $1.range.location }
        let edits = matches.map {
            TranscriptTerminologyEdit(startUTF16: $0.range.location, lengthUTF16: $0.range.length, original: $0.original, replacement: $0.replacement, canonical: $0.replacement)
        }
        var corrected = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: corrected) else { continue }
            corrected.replaceSubrange(range, with: match.replacement)
        }
        return TranscriptTerminologyResult(text: corrected, edits: edits)
    }
}
