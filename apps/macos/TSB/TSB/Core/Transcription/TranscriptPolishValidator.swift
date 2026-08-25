import Foundation

enum TranscriptPolishValidationError: Error, Equatable { case invalidShape, limitExceeded, mismatch, invalidEdit }

struct TranscriptPolishValidator {
    static let schemaVersion = "tsb.transcript_polish.response.v1"

    func validate(_ data: Data, for request: TranscriptPolishRequest) throws -> TranscriptPolishOutcome {
        guard data.count <= TranscriptPolishClient.maximumInnerBytes else { throw TranscriptPolishValidationError.limitExceeded }
        let object = try exact(data, keys: ["schema_version", "request_id", "candidate_hashes", "base_candidate_id", "corrected_text", "edits"])
        guard object["schema_version"] as? String == Self.schemaVersion,
              object["request_id"] as? String == request.requestID.uuidString.lowercased(),
              let baseRaw = object["base_candidate_id"] as? String, let base = TranscriptCandidate.ID(rawValue: baseRaw),
              let baseText = request.candidates.first(where: { $0.id == base })?.text,
              let corrected = object["corrected_text"] as? String, !corrected.isEmpty, corrected.unicodeScalars.count <= 8_000 else { throw TranscriptPolishValidationError.mismatch }
        guard hashes(object["candidate_hashes"], match: request.candidates), let rawEdits = object["edits"] as? [Any], rawEdits.count <= 128 else { throw TranscriptPolishValidationError.invalidShape }
        let edits = try rawEdits.map(decodeEdit)
        guard edits.allSatisfy({ $0.original.unicodeScalars.count <= 256 && $0.replacement.unicodeScalars.count <= 256 && $0.reason.unicodeScalars.count <= 120 }), let changed = changedUnits(edits),
              changed <= max(1, Int(ceil(Double(baseText.utf16.count) * 0.2))),
              immutableTokens(in: baseText) == immutableTokens(in: corrected),
              applying(edits, to: baseText) == corrected else { throw TranscriptPolishValidationError.invalidEdit }
        let automatic = edits.allSatisfy { isAutomatic($0, base: baseText, request: request) }
        return automatic ? .accepted(baseCandidateID: base, text: corrected, edits: edits) : .reviewRequired(baseCandidateID: base, text: corrected, edits: edits)
    }

    private func exact(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == keys else { throw TranscriptPolishValidationError.invalidShape }; return object
    }
    private func hashes(_ any: Any?, match candidates: [TranscriptCandidate]) -> Bool {
        guard let list = any as? [[String: Any]], list.count == candidates.count else { return false }
        return zip(list, candidates).allSatisfy { item, candidate in Set(item.keys) == ["candidate_id", "text_sha256"] && item["candidate_id"] as? String == candidate.id.rawValue && item["text_sha256"] as? String == candidate.textSHA256 }
    }
    private func decodeEdit(_ any: Any) throws -> TranscriptPolishEdit {
        guard let object = any as? [String: Any], Set(object.keys) == ["kind", "start_utf16", "length_utf16", "original", "replacement", "reason"], let kindRaw = object["kind"] as? String, let kind = TranscriptPolishEditKind(rawValue: kindRaw), let start = object["start_utf16"] as? Int, !isBoolean(object["start_utf16"]), let length = object["length_utf16"] as? Int, !isBoolean(object["length_utf16"]), let original = object["original"] as? String, let replacement = object["replacement"] as? String, let reason = object["reason"] as? String, start >= 0, length >= 0 else { throw TranscriptPolishValidationError.invalidShape }
        return .init(kind: kind, startUTF16: start, lengthUTF16: length, original: original, replacement: replacement, reason: reason)
    }
    private func isBoolean(_ value: Any?) -> Bool { guard let value else { return false }; return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() }
    private func applying(_ edits: [TranscriptPolishEdit], to text: String) -> String? {
        var prior = 0; var result = text
        for edit in edits { let end = edit.startUTF16.addingReportingOverflow(edit.lengthUTF16); guard edit.startUTF16 >= prior, !end.overflow, end.partialValue <= text.utf16.count, let range = Range(NSRange(location: edit.startUTF16, length: edit.lengthUTF16), in: text), text[range] == edit.original else { return nil }; prior = end.partialValue }
        for edit in edits.reversed() { guard let range = Range(NSRange(location: edit.startUTF16, length: edit.lengthUTF16), in: result) else { return nil }; result.replaceSubrange(range, with: edit.replacement) }
        return result
    }
    private func isAutomatic(_ edit: TranscriptPolishEdit, base: String, request: TranscriptPolishRequest) -> Bool {
        switch edit.kind {
        case .formatting: let allowed: (Unicode.Scalar) -> Bool = { CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) || ($0.value < 128 && CharacterSet.letters.contains($0)) }; return (edit.original.unicodeScalars.allSatisfy(allowed) && edit.replacement.unicodeScalars.allSatisfy(allowed) && edit.original.lowercased() == edit.replacement.lowercased()) || (edit.original.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) } && edit.replacement.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) })
        case .terminology: return request.terminology.contains {
            $0.canonical == edit.replacement
                && $0.aliases.contains(edit.original)
                && TranscriptTerminologyBoundary.matches(
                    edit.original,
                    at: NSRange(location: edit.startUTF16, length: edit.lengthUTF16),
                    in: base
                )
        }
        case .candidateSupported: return candidateSupported(edit, base: base, request: request)
        }
    }
    private func changedUnits(_ edits: [TranscriptPolishEdit]) -> Int? { var total = 0; for edit in edits { let result = total.addingReportingOverflow(max(edit.lengthUTF16, edit.replacement.utf16.count)); guard !result.overflow else { return nil }; total = result.partialValue }; return total }
    private func candidateSupported(_ edit: TranscriptPolishEdit, base: String, request: TranscriptPolishRequest) -> Bool {
        let other = request.candidates.first { $0.text != base }?.text ?? ""
        guard let range = Range(NSRange(location: edit.startUTF16, length: edit.lengthUTF16), in: base) else { return false }
        let left = String(base[..<range.lowerBound]).unicodeScalars.suffix(4), right = String(base[range.upperBound...]).unicodeScalars.prefix(4)
        guard range.lowerBound == base.startIndex || left.count == 4, range.upperBound == base.endIndex || right.count == 4 else { return false }
        let fragment = String(String.UnicodeScalarView(left + edit.replacement.unicodeScalars + right))
        if range.lowerBound == base.startIndex { return other.hasPrefix(fragment) }
        if range.upperBound == base.endIndex { return other.hasSuffix(fragment) }
        return other.contains(fragment)
    }
    private func immutableTokens(in text: String) -> [String] { (try? NSRegularExpression(pattern: #"https?://[^\s]+|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|(?<![\p{L}\p{N}_])[+\-−]?(?:\d+(?:[.,]\d+)*|[.,]\d+)(?![\p{L}\p{N}_])"#, options: [.caseInsensitive]))?.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) } ?? [] }
}
