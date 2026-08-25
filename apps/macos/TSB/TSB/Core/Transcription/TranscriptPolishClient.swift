import Foundation

struct TranscriptPolishRequest: Equatable, Sendable { let requestID: UUID; let candidates: [TranscriptCandidate]; let terminology: [TranscriptTerminologyEntry] }
struct TranscriptPolishEndpoint: Equatable, Sendable { let baseURL: URL; let model: String }
enum TranscriptPolishClientError: Error, Equatable { case insecureEndpoint, invalidRequest, responseTooLarge, invalidResponse, httpStatus(Int) }

struct TranscriptPolishClient: Sendable {
    static let maximumOuterBytes = 65_536
    static let maximumInnerBytes = 49_152
    private let endpoint: TranscriptPolishEndpoint; private let session: URLSession
    init(endpoint: TranscriptPolishEndpoint, session: URLSession = .shared) { self.endpoint = endpoint; self.session = session }
    func polish(_ request: TranscriptPolishRequest, apiKey: String) async throws -> TranscriptPolishOutcome {
        try Task.checkCancellation(); try validate(request)
        let host = endpoint.baseURL.host?.lowercased(); let loopback = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard endpoint.baseURL.scheme?.lowercased() == "https" || (endpoint.baseURL.scheme?.lowercased() == "http" && loopback) else { throw TranscriptPolishClientError.insecureEndpoint }
        let inner = try JSONSerialization.data(withJSONObject: ["schema_version": "tsb.transcript_polish.request.v1", "request_id": request.requestID.uuidString.lowercased(), "candidates": request.candidates.map { ["candidate_id": $0.id.rawValue, "text": $0.text, "text_sha256": $0.textSHA256] }, "terminology": request.terminology.map { ["canonical": $0.canonical, "aliases": $0.aliases] }], options: [.sortedKeys])
        guard inner.count <= Self.maximumInnerBytes else { throw TranscriptPolishClientError.invalidRequest }
        let body = try JSONSerialization.data(withJSONObject: ["model": endpoint.model, "messages": [["role": "system", "content": Self.systemContract], ["role": "user", "content": String(decoding: inner, as: UTF8.self)]], "response_format": ["type": "json_object"]], options: [.sortedKeys])
        guard body.count <= Self.maximumOuterBytes else { throw TranscriptPolishClientError.invalidRequest }
        var urlRequest = URLRequest(url: endpoint.baseURL); urlRequest.httpMethod = "POST"; urlRequest.httpBody = body; urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type"); if !apiKey.isEmpty { urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.bytes(for: urlRequest, delegate: TranscriptPolishRejectRedirectDelegate()); try Task.checkCancellation()
        guard response.expectedContentLength <= Int64(Self.maximumOuterBytes) else { throw TranscriptPolishClientError.responseTooLarge }
        var data = Data(); data.reserveCapacity(min(max(Int(response.expectedContentLength), 0), Self.maximumOuterBytes))
        for try await byte in bytes { guard data.count < Self.maximumOuterBytes else { throw TranscriptPolishClientError.responseTooLarge }; data.append(byte) }
        guard let http = response as? HTTPURLResponse else { throw TranscriptPolishClientError.invalidResponse }; guard (200..<300).contains(http.statusCode) else { throw TranscriptPolishClientError.httpStatus(http.statusCode) }
        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(outer.keys).isSubset(of: ["id", "object", "created", "model", "choices", "usage", "system_fingerprint"]), let choices = outer["choices"] as? [[String: Any]], choices.count == 1, Set(choices[0].keys).isSubset(of: ["index", "message", "finish_reason", "logprobs"]), let message = choices[0]["message"] as? [String: Any], Set(message.keys) == ["role", "content"], message["role"] as? String == "assistant", let content = message["content"] as? String, Data(content.utf8).count <= Self.maximumInnerBytes else { throw TranscriptPolishClientError.invalidResponse }
        return try TranscriptPolishValidator().validate(Data(content.utf8), for: request)
    }
    private func validate(_ request: TranscriptPolishRequest) throws { let relevant = request.terminology.allSatisfy { entry in !entry.canonical.isEmpty && !entry.aliases.isEmpty && entry.canonical.unicodeScalars.count <= 80 && entry.aliases.count <= 8 && entry.aliases.allSatisfy { !$0.isEmpty && $0.unicodeScalars.count <= 80 } && request.candidates.contains { candidate in candidate.text.contains(entry.canonical) || entry.aliases.contains(where: candidate.text.contains) } }; guard !request.candidates.isEmpty, request.candidates.count <= 2, request.candidates.map(\.id) == ([.offline, .streaming].filter { id in request.candidates.contains { $0.id == id } }), request.candidates.allSatisfy({ !$0.text.isEmpty && $0.text.unicodeScalars.count <= 8_000 }), request.candidates.reduce(0, { $0 + $1.text.unicodeScalars.count }) <= 12_000, request.terminology.count <= 64, relevant, request.terminology.flatMap({ [$0.canonical] + $0.aliases }).reduce(0, { $0 + $1.unicodeScalars.count }) <= 4_096 else { throw TranscriptPolishClientError.invalidRequest } }
    private static let systemContract = "Return only JSON: {schema_version:'tsb.transcript_polish.response.v1',request_id,candidate_hashes:[{candidate_id,text_sha256}],base_candidate_id,corrected_text,edits:[{kind,start_utf16,length_utf16,original,replacement,reason}]}. Echo request candidates/hashes in offline then streaming order. kind is formatting, terminology, or candidate_supported. Preserve numbers, URLs, emails, meaning; no summaries, answers, facts, examples, or context-only inference. Limits: corrected 8000 scalars, 128 edits, changed UTF16 <=20%. formatting only whitespace/punctuation/Latin case; terminology only submitted alias to canonical; candidate_supported requires contiguous left(4 Unicode scalars)+replacement+right(4 scalars) in the other candidate, with one side omitted only at that text boundary."
}

private final class TranscriptPolishRejectRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable { func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) } }
