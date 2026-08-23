import Foundation

struct OrganizationEndpoint: Equatable, Sendable {
    let baseURL: URL
    let model: String
}

enum OrganizationClientError: Error, Equatable {
    case insecureEndpoint
    case invalidHTTPResponse
    case httpStatus(Int)
    case missingResponseContent
}

struct OrganizationClient: Sendable {
    private let endpoint: OrganizationEndpoint
    private let session: URLSession
    private let timeoutSleeper: @Sendable (Duration) async throws -> Void

    init(
        endpoint: OrganizationEndpoint,
        session: URLSession = .shared,
        timeoutSleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.timeoutSleeper = timeoutSleeper
    }

    func organize(
        requestID: UUID,
        segments: [TextSegment],
        historySuggestions: HistorySuggestions,
        userSelectedCandidateIDs: Set<String>,
        apiKey: String
    ) async throws -> OrganizationOutput {
        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(endpoint.baseURL.host?.lowercased())
        let scheme = endpoint.baseURL.scheme?.lowercased()
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw OrganizationClientError.insecureEndpoint
        }

        let canonicalSegments = try segments.enumerated().map {
            try TextSegment(id: "c\($0.offset + 1)", text: $0.element.text)
        }
        var selected: [SelectedHistory] = []
        for suggestion in historySuggestions.suggestedSummaries {
            guard userSelectedCandidateIDs.contains(suggestion.candidateID),
                  let recordID = historySuggestions.localRecordByCandidateID[suggestion.candidateID] else { continue }
            selected.append(SelectedHistory(
                candidateID: "h\(selected.count + 1)",
                summary: suggestion.summary,
                recordID: recordID
            ))
        }
        let inputTextSHA256 = OrganizationValidator.inputTextSHA256(for: canonicalSegments)
        let payload = OrganizationRequestDTO(
            schemaVersion: "tsb.organization.request.v1",
            requestID: requestID.uuidString.lowercased(),
            sourceTextHash: inputTextSHA256,
            currentSegments: canonicalSegments.map { .init(segmentID: $0.id, text: $0.text) },
            historySummaries: selected.map { .init(candidateID: $0.candidateID, summary: $0.summary) }
        )
        let userContent = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        let body = ChatRequestDTO(
            model: endpoint.model,
            messages: [
                .init(role: "system", content: Self.systemContract),
                .init(role: "user", content: userContent)
            ],
            responseFormat: .init(type: "json_object")
        )
        var request = URLRequest(url: endpoint.baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = isLoopback ? 60 : 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await data(
            for: request,
            timeout: isLoopback ? .seconds(60) : .seconds(20)
        )
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OrganizationClientError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OrganizationClientError.httpStatus(httpResponse.statusCode)
        }
        let chatResponse = try JSONDecoder().decode(ChatResponseDTO.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OrganizationClientError.missingResponseContent
        }
        let organizationResponse = try OrganizationResponseDTO.decodeStrictly(from: Data(content.utf8))
        try Task.checkCancellation()
        let output = try OrganizationValidator(
            requestID: requestID,
            inputTextSHA256: inputTextSHA256,
            currentSegmentByID: Dictionary(uniqueKeysWithValues: canonicalSegments.map { ($0.id, $0) }),
            recordByCandidateID: Dictionary(uniqueKeysWithValues: selected.map { ($0.candidateID, $0.recordID) })
        ).validate(organizationResponse)
        try Task.checkCancellation()
        return output
    }

    private func data(for request: URLRequest, timeout: Duration) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: NetworkRaceResult.self) { group in
            group.addTask {
                let value = try await session.data(for: request, delegate: RejectRedirectDelegate())
                return .response(value.0, value.1)
            }
            group.addTask {
                try await timeoutSleeper(timeout)
                return .timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            switch first {
            case let .response(data, response): return (data, response)
            case .timedOut: throw URLError(.timedOut)
            }
        }
    }

    private static let systemContract = """
    Return only this JSON shape:
    {"schema_version":"tsb.organization.output.v1","request_id":"same request UUID","source_text_hash":"lowercase SHA-256","no_result_reason":null,"numbered_points":[{"number":1,"text":"faithful point","source_segment_ids":["c1"]}],"known_record_links":[{"candidate_id":"h1","reason":"supported relationship","source_segment_ids":["c1"]}],"speculative_connections":[{"statement":"possible connection","why_speculative":"why it is unconfirmed","source_segment_ids":["c1"],"candidate_ids":["h1"]}]}
    Echo request_id and source_text_hash exactly as provided. Number points from 1 without gaps. Use only source_segment_ids and candidate_ids present in the request. Keep known links separate from speculative connections. If every result array is empty, set no_result_reason to insufficient_content or no_reliable_structure; otherwise set it to null.
    """
}

private enum NetworkRaceResult: @unchecked Sendable {
    case response(Data, URLResponse)
    case timedOut
}

private struct SelectedHistory {
    let candidateID: String
    let summary: String
    let recordID: SessionID
}

private final class RejectRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct OrganizationRequestDTO: Encodable {
    let schemaVersion: String
    let requestID: String
    let sourceTextHash: String
    let currentSegments: [CurrentSegmentDTO]
    let historySummaries: [HistorySummaryRequestDTO]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case sourceTextHash = "source_text_hash"
        case currentSegments = "current_segments"
        case historySummaries = "history_summaries"
    }
}

private struct CurrentSegmentDTO: Encodable {
    let segmentID: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id"
        case text
    }
}

private struct HistorySummaryRequestDTO: Encodable {
    let candidateID: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case summary
    }
}

private struct ChatRequestDTO: Encodable {
    let model: String
    let messages: [ChatMessageDTO]
    let responseFormat: ResponseFormatDTO

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
    }
}

private struct ChatMessageDTO: Codable {
    let role: String
    let content: String
}

private struct ResponseFormatDTO: Encodable {
    let type: String
}

private struct ChatResponseDTO: Decodable {
    let choices: [ChoiceDTO]

    struct ChoiceDTO: Decodable {
        let message: ChatMessageDTO
    }
}
