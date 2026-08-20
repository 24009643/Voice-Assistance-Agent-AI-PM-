import Foundation
import XCTest
@testable import TSB

final class OrganizationClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSendsOnlyExactEndpointTextSegmentsAndExplicitlySelectedHistory() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let recordID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
        let endpointURL = URL(string: "https://example.test/custom/chat")!
        let response = makeValidChatResponse(requestID: requestID)
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url, endpointURL)
            XCTAssertEqual(request.timeoutInterval, 20, accuracy: 0.01)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer header-only-secret")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["model", "messages", "response_format"])
            XCTAssertEqual(json["model"] as? String, "test-model")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 2)
            let content = try XCTUnwrap(messages.last?["content"] as? String)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            XCTAssertEqual(Set(payload.keys), ["schema_version", "request_id", "current_segments", "history_summaries"])
            XCTAssertEqual(payload["schema_version"] as? String, "tsb.organization.request.v1")
            XCTAssertEqual(payload["request_id"] as? String, requestID.uuidString.lowercased())
            XCTAssertEqual(payload["current_segments"] as? [[String: String]], [
                ["segment_id": "c1", "text": "alpha"],
                ["segment_id": "c2", "text": "beta"]
            ])
            XCTAssertEqual(payload["history_summaries"] as? [[String: String]], [
                ["candidate_id": "h1", "summary": "selected summary"]
            ])

            let wireText = String(decoding: body, as: UTF8.self)
            for forbiddenValue in [
                "header-only-secret", "zh-CN", "sensitive-keyword", "2026-08-20",
                "/private/audio.wav", "00000000-0000-0000-0000-000000000201",
                "full old transcript", "clipboard contents"
            ] {
                XCTAssertFalse(wireText.contains(forbiddenValue), "Leaked \(forbiddenValue)")
            }
            return (200, response)
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: endpointURL, model: "test-model"),
            session: makeSession()
        )
        let suggestions = HistorySuggestions(
            suggestedSummaries: [
                HistorySummaryDTO(candidateID: "h1", summary: "selected summary"),
                HistorySummaryDTO(candidateID: "h2", summary: "not selected")
            ],
            localRecordByCandidateID: ["h1": recordID, "h2": SessionID(rawValue: UUID())]
        )

        let output = try await client.organize(
            requestID: requestID,
            segments: [
                try TextSegment(id: "c1", text: "alpha"),
                try TextSegment(id: "c2", text: "beta")
            ],
            historySuggestions: suggestions,
            userSelectedCandidateIDs: ["h1"],
            apiKey: "header-only-secret"
        )

        XCTAssertEqual(output.knownRecordLinks.map(\.recordID), [recordID])
    }

    func testEmptySelectionSendsNoHistoryEvenWhenSuggestionsExist() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        URLProtocolStub.handler = { request in
            let body = try requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.last?["content"] as? String)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            XCTAssertEqual(payload["history_summaries"] as? [[String: String]], [])
            return (200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )
        let suggestions = HistorySuggestions(
            suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "relevant but unselected")],
            localRecordByCandidateID: ["h1": SessionID(rawValue: UUID())]
        )

        _ = try await client.organize(
            requestID: requestID,
            segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
            historySuggestions: suggestions,
            userSelectedCandidateIDs: [],
            apiKey: "secret"
        )
    }

    func testRejectsInvalidJSONAndInsecureNonLoopbackHTTP() async throws {
        URLProtocolStub.handler = { _ in (200, Data("not-json".utf8)) }
        let invalidJSONClient = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )

        await XCTAssertThrowsErrorAsync {
            try await invalidJSONClient.organize(
                requestID: UUID(),
                segments: [try TextSegment(id: "c1", text: "text")],
                historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                userSelectedCandidateIDs: [],
                apiKey: "secret"
            )
        }

        let insecureClient = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "http://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )
        await XCTAssertThrowsErrorAsync {
            try await insecureClient.organize(
                requestID: UUID(),
                segments: [try TextSegment(id: "c1", text: "text")],
                historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                userSelectedCandidateIDs: [],
                apiKey: "secret"
            )
        }
    }

    func testLoopbackHTTPUsesSixtySecondTimeout() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.timeoutInterval, 60, accuracy: 0.01)
            return (200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!, model: "local"),
            session: makeSession()
        )

        _ = try await client.organize(
            requestID: requestID,
            segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
            historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
            userSelectedCandidateIDs: [],
            apiKey: ""
        )
    }

    func testCancellationAndTimeoutDoNotReturnLateOutput() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        URLProtocolStub.handler = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return (200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )
        let task = Task {
            try await client.organize(
                requestID: requestID,
                segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
                historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                userSelectedCandidateIDs: [],
                apiKey: "secret"
            )
        }
        task.cancel()

        await XCTAssertThrowsErrorAsync { try await task.value }

        URLProtocolStub.handler = { _ in throw URLError(.timedOut) }
        await XCTAssertThrowsErrorAsync {
            try await client.organize(
                requestID: requestID,
                segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
                historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                userSelectedCandidateIDs: [],
                apiKey: "secret"
            )
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    nonisolated(unsafe) static var handler: Handler?

    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        DispatchQueue.global().async { [self] in
            do {
                let (status, data) = try handler(request)
                guard !isStopped else { return }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }

    private var isStopped: Bool { stateLock.withLock { stopped } }
}

private func makeValidChatResponse(requestID: UUID, includeLinks: Bool = true) -> Data {
    let links = includeLinks
        ? "[{\"candidate_id\":\"h1\",\"reason\":\"same topic\",\"source_segment_ids\":[\"c1\"]}]"
        : "[]"
    let content = """
    {
      "schema_version": "tsb.organization.output.v1",
      "request_id": "\(requestID.uuidString.lowercased())",
      "source_text_hash": "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9",
      "no_result_reason": null,
      "numbered_points": [
        {"number":1,"text":"alpha","source_segment_ids":["c1"]},
        {"number":2,"text":"beta","source_segment_ids":["c2"]}
      ],
      "known_record_links": \(links),
      "speculative_connections": []
    }
    """
    let outer: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
    return try! JSONSerialization.data(withJSONObject: outer)
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
