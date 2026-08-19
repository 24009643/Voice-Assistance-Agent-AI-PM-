import Foundation

struct ConservativeCleaner {
    func clean(_ source: String) -> CleanResult {
        let edits = plannedEdits(for: source)
        let output = NSMutableString(string: source)

        for edit in edits.sorted(by: { $0.startUTF16 > $1.startUTF16 }) {
            output.replaceCharacters(
                in: NSRange(location: edit.startUTF16, length: edit.lengthUTF16),
                with: edit.replacement
            )
        }

        return CleanResult(text: output as String, edits: edits)
    }

    private func plannedEdits(for source: String) -> [EditOperation] {
        let contentRange = trimmedContentRange(in: source)
        var edits = trimEdits(for: source, contentRange: contentRange)
        edits.append(contentsOf: interiorEdits(for: source, contentRange: contentRange))
        return edits.sorted { $0.startUTF16 < $1.startUTF16 }
    }

    private func trimmedContentRange(in source: String) -> Range<String.Index> {
        guard let first = source.firstIndex(where: { !Self.isTrimWhitespace($0) }),
              let last = source.lastIndex(where: { !Self.isTrimWhitespace($0) }) else {
            return source.startIndex..<source.startIndex
        }

        return first..<source.index(after: last)
    }

    private func trimEdits(for source: String, contentRange: Range<String.Index>) -> [EditOperation] {
        guard source.startIndex != contentRange.lowerBound || source.endIndex != contentRange.upperBound else {
            return []
        }

        if contentRange.isEmpty {
            return [edit(kind: .trim, source: source, range: source.startIndex..<source.endIndex, replacement: "")]
        }

        var edits: [EditOperation] = []
        if source.startIndex != contentRange.lowerBound {
            edits.append(edit(kind: .trim, source: source, range: source.startIndex..<contentRange.lowerBound, replacement: ""))
        }
        if contentRange.upperBound != source.endIndex {
            edits.append(edit(kind: .trim, source: source, range: contentRange.upperBound..<source.endIndex, replacement: ""))
        }
        return edits
    }

    private func interiorEdits(for source: String, contentRange: Range<String.Index>) -> [EditOperation] {
        guard !contentRange.isEmpty else { return [] }

        var edits: [EditOperation] = []
        var index = contentRange.lowerBound

        while index < contentRange.upperBound {
            let character = source[index]
            if Self.isHorizontalWhitespace(character) {
                let end = runEnd(in: source, from: index, through: contentRange.upperBound, matching: Self.isHorizontalWhitespace)
                if source.distance(from: index, to: end) > 1 {
                    edits.append(edit(kind: .whitespace, source: source, range: index..<end, replacement: String(character)))
                }
                index = end
            } else if Self.repeatablePunctuation.contains(character) {
                let end = runEnd(
                    in: source,
                    from: index,
                    through: contentRange.upperBound,
                    matching: { $0 == character }
                )
                if source.distance(from: index, to: end) > 1 {
                    edits.append(edit(kind: .repeatedPunctuation, source: source, range: index..<end, replacement: String(character)))
                }
                index = end
            } else {
                index = source.index(after: index)
            }
        }

        return edits
    }

    private func runEnd(
        in source: String,
        from start: String.Index,
        through limit: String.Index,
        matching predicate: (Character) -> Bool
    ) -> String.Index {
        var index = start
        while index < limit, predicate(source[index]) {
            index = source.index(after: index)
        }
        return index
    }

    private func edit(kind: EditOperation.Kind, source: String, range: Range<String.Index>, replacement: String) -> EditOperation {
        let utf16 = source.utf16
        let start = range.lowerBound.samePosition(in: utf16)!
        let end = range.upperBound.samePosition(in: utf16)!
        return EditOperation(
            kind: kind,
            startUTF16: utf16.distance(from: utf16.startIndex, to: start),
            lengthUTF16: utf16.distance(from: start, to: end),
            original: String(source[range]),
            replacement: replacement
        )
    }

    private static let repeatablePunctuation: Set<Character> = ["，", "。", "！", "？", "；", "：", ",", ".", "!", "?", ";", ":"]

    private static func isTrimWhitespace(_ character: Character) -> Bool {
        !character.unicodeScalars.isEmpty && character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        !character.unicodeScalars.isEmpty && character.unicodeScalars.allSatisfy {
            CharacterSet.whitespaces.contains($0) && !CharacterSet.newlines.contains($0)
        }
    }
}
