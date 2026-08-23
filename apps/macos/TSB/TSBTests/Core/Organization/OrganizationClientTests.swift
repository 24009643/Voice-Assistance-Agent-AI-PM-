import Foundation
import XCTest
@testable import TSB

final class OrganizationClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        URLProtocolStub.stopHandler = nil
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
            XCTAssertEqual(Set(payload.keys), [
                "schema_version", "request_id", "source_text_hash", "current_segments", "history_summaries"
            ])
            XCTAssertEqual(payload["schema_version"] as? String, "tsb.organization.request.v1")
            XCTAssertEqual(payload["request_id"] as? String, requestID.uuidString.lowercased())
            XCTAssertEqual(
                payload["source_text_hash"] as? String,
                "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9"
            )
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
            return .response(200, response)
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
            return .response(200, makeValidChatResponse(requestID: requestID, includeLinks: false))
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
        URLProtocolStub.handler = { _ in .response(200, Data("not-json".utf8)) }
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
        let deadlines = DurationRecorder()
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.timeoutInterval, 60, accuracy: 0.01)
            Thread.sleep(forTimeInterval: 0.05)
            return .response(200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!, model: "local"),
            session: makeSession(),
            timeoutSleeper: { duration in
                deadlines.append(duration)
                try await Task.sleep(for: .seconds(1))
            }
        )

        _ = try await client.organize(
            requestID: requestID,
            segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
            historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
            userSelectedCandidateIDs: [],
            apiKey: ""
        )
        XCTAssertEqual(deadlines.values, [.seconds(60)])
    }

    func testCancellationStopsStartedRequestBeforeLateHandlerOutput() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let lifecycle = RequestLifecycle()
        let completed = TaskCompletion()
        URLProtocolStub.handler = { _ in
            lifecycle.requestStarted.fulfill()
            lifecycle.waitForRelease()
            lifecycle.lateHandlerOutput.fulfill()
            return .response(200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        URLProtocolStub.stopHandler = { lifecycle.stopObserved() }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )
        let task = Task { () -> Result<OrganizationOutput, Error> in
            defer { completed.finish() }
            do {
                return .success(try await client.organize(
                    requestID: requestID,
                    segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
                    historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                    userSelectedCandidateIDs: [],
                    apiKey: "secret"
                ))
            } catch {
                return .failure(error)
            }
        }

        defer { lifecycle.release() }
        await fulfillment(of: [lifecycle.requestStarted], timeout: 1)
        task.cancel()
        await fulfillment(of: [lifecycle.requestStopped], timeout: 1)
        lifecycle.release()
        await fulfillment(of: [lifecycle.lateHandlerOutput], timeout: 1)
        guard lifecycle.didStop else {
            task.cancel()
            return
        }
        await fulfillment(of: [completed.expectation], timeout: 1)
        guard completed.didFinish else {
            task.cancel()
            await fulfillment(of: [completed.expectation], timeout: 1)
            return
        }
        let result = await task.value
        if case .success = result { XCTFail("Expected cancellation") }
    }

    func testTimeoutStopsStartedRequestBeforeLateHandlerOutput() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let lifecycle = RequestLifecycle()
        let completed = TaskCompletion()
        let deadlines = DurationRecorder()
        URLProtocolStub.handler = { _ in
            lifecycle.requestStarted.fulfill()
            lifecycle.waitForRelease()
            lifecycle.lateHandlerOutput.fulfill()
            return .response(200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        URLProtocolStub.stopHandler = { lifecycle.stopObserved() }
        let timeoutClient = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession(),
            timeoutSleeper: { duration in
                deadlines.append(duration)
                lifecycle.waitForTimeout()
            }
        )

        let task = Task { () -> Result<OrganizationOutput, Error> in
            defer { completed.finish() }
            do {
                return .success(try await timeoutClient.organize(
                    requestID: requestID,
                    segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
                    historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                    userSelectedCandidateIDs: [],
                    apiKey: "secret"
                ))
            } catch {
                return .failure(error)
            }
        }

        defer { lifecycle.release() }
        await fulfillment(of: [lifecycle.requestStarted], timeout: 1)
        lifecycle.startTimeout()
        await fulfillment(of: [lifecycle.requestStopped], timeout: 1)
        lifecycle.release()
        await fulfillment(of: [lifecycle.lateHandlerOutput], timeout: 1)
        guard lifecycle.didStop else {
            task.cancel()
            return
        }
        await fulfillment(of: [completed.expectation], timeout: 1)
        guard completed.didFinish else {
            task.cancel()
            await fulfillment(of: [completed.expectation], timeout: 1)
            return
        }
        let result = await task.value
        switch result {
        case .success:
            XCTFail("Expected timeout")
        case let .failure(error as URLError):
            XCTAssertEqual(error.code, .timedOut)
        case let .failure(error):
            XCTFail("Expected timedOut, got \(error)")
        }
        XCTAssertEqual(deadlines.values, [.seconds(20)])
    }

    func testRejectsRedirectBeforeAnySecondRequestCanCarryText() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let origin = URL(string: "https://origin.test/exact-chat-endpoint")!
        let redirected = URL(string: "https://attacker.test/collect")!
        let recorder = URLRecorder()
        URLProtocolStub.handler = { request in
            recorder.append(request.url!)
            if request.url == origin { return .redirect(redirected) }
            return .response(200, makeValidChatResponse(requestID: requestID, includeLinks: false))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: origin, model: "test-model"),
            session: makeSession()
        )

        await XCTAssertThrowsErrorAsync {
            try await client.organize(
                requestID: requestID,
                segments: [try TextSegment(id: "c1", text: "must stay at origin")],
                historySuggestions: HistorySuggestions(suggestedSummaries: [], localRecordByCandidateID: [:]),
                userSelectedCandidateIDs: [],
                apiKey: "secret"
            )
        }

        XCTAssertEqual(recorder.urls, [origin])
    }

    func testRegeneratesSequentialEphemeralIDsBeforeSendingInternalShapedIDs() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let internalCandidateID = "00000000-0000-0000-0000-000000000201"
        let recordID = SessionID(rawValue: UUID(uuidString: internalCandidateID)!)
        URLProtocolStub.handler = { request in
            let body = try requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.last?["content"] as? String)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            XCTAssertEqual(payload["current_segments"] as? [[String: String]], [
                ["segment_id": "c1", "text": "alpha"],
                ["segment_id": "c2", "text": "beta"]
            ])
            XCTAssertEqual(payload["history_summaries"] as? [[String: String]], [
                ["candidate_id": "h1", "summary": "selected summary"]
            ])
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(internalCandidateID))
            return .response(200, makeValidChatResponse(requestID: requestID))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )
        let suggestions = HistorySuggestions(
            suggestedSummaries: [HistorySummaryDTO(candidateID: internalCandidateID, summary: "selected summary")],
            localRecordByCandidateID: [internalCandidateID: recordID]
        )

        let output = try await client.organize(
            requestID: requestID,
            segments: [
                try TextSegment(id: internalCandidateID, text: "alpha"),
                try TextSegment(id: "arbitrary-segment", text: "beta")
            ],
            historySuggestions: suggestions,
            userSelectedCandidateIDs: [internalCandidateID],
            apiKey: "secret"
        )

        XCTAssertEqual(output.knownRecordLinks.map(\.recordID), [recordID])
    }

    func testRejectsMismatchedEchoedSourceHash() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        URLProtocolStub.handler = { _ in
            .response(200, makeValidChatResponse(
                requestID: requestID,
                includeLinks: false,
                sourceTextHash: "wrong"
            ))
        }
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )

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

    func testRejectsUnknownOrganizationKeysAtEveryObjectLevel() async throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let recordID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
        let client = OrganizationClient(
            endpoint: OrganizationEndpoint(baseURL: URL(string: "https://example.test/chat")!, model: "test-model"),
            session: makeSession()
        )
        let suggestions = HistorySuggestions(
            suggestedSummaries: [HistorySummaryDTO(candidateID: "h1", summary: "selected summary")],
            localRecordByCandidateID: ["h1": recordID]
        )

        for location in UnknownFieldLocation.allCases {
            URLProtocolStub.handler = { _ in
                .response(200, makeValidChatResponse(requestID: requestID, unknownFieldAt: location))
            }
            await XCTAssertThrowsErrorAsync {
                try await client.organize(
                    requestID: requestID,
                    segments: [try TextSegment(id: "c1", text: "alpha"), try TextSegment(id: "c2", text: "beta")],
                    historySuggestions: suggestions,
                    userSelectedCandidateIDs: ["h1"],
                    apiKey: "secret"
                )
            }
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case response(Int, Data)
        case redirect(URL)
    }

    typealias Handler = @Sendable (URLRequest) throws -> Response
    nonisolated(unsafe) static var handler: Handler?
    nonisolated(unsafe) static var stopHandler: (@Sendable () -> Void)?

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
                let result = try handler(request)
                guard !isStopped else { return }
                switch result {
                case let .response(status, data):
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                case let .redirect(url):
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 302,
                        httpVersion: nil,
                        headerFields: ["Location": url.absoluteString]
                    )!
                    var redirectedRequest = request
                    redirectedRequest.url = url
                    client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
                }
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        let didStop = stateLock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        if didStop { Self.stopHandler?() }
    }

    private var isStopped: Bool { stateLock.withLock { stopped } }
}

private enum UnknownFieldLocation: CaseIterable, Sendable {
    case topLevel
    case point
    case link
    case connection
}

private func makeValidChatResponse(
    requestID: UUID,
    includeLinks: Bool = true,
    sourceTextHash: String = "bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9",
    unknownFieldAt location: UnknownFieldLocation? = nil
) -> Data {
    let topLevelExtra = location == .topLevel ? ",\"unexpected\":true" : ""
    let pointExtra = location == .point ? ",\"candidate_id\":\"h1\"" : ""
    let linkExtra = location == .link ? ",\"statement\":\"mixed category\"" : ""
    let links = includeLinks
        ? "[{\"candidate_id\":\"h1\",\"reason\":\"same topic\",\"source_segment_ids\":[\"c1\"]\(linkExtra)}]"
        : "[]"
    let connections = location == .connection
        ? "[{\"statement\":\"possible\",\"why_speculative\":\"unconfirmed\",\"source_segment_ids\":[\"c1\"],\"candidate_ids\":[\"h1\"],\"reason\":\"mixed category\"}]"
        : "[]"
    let content = """
    {
      "schema_version": "tsb.organization.output.v1",
      "request_id": "\(requestID.uuidString.lowercased())",
      "source_text_hash": "\(sourceTextHash)",
      "no_result_reason": null,
      "numbered_points": [
        {"number":1,"text":"alpha","source_segment_ids":["c1"]\(pointExtra)},
        {"number":2,"text":"beta","source_segment_ids":["c2"]}
      ],
      "known_record_links": \(links),
      "speculative_connections": \(connections)\(topLevelExtra)
    }
    """
    let outer: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
    return try! JSONSerialization.data(withJSONObject: outer)
}

private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []

    var urls: [URL] { lock.withLock { storedURLs } }
    func append(_ url: URL) { lock.withLock { storedURLs.append(url) } }
}

private final class DurationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Duration] = []

    var values: [Duration] { lock.withLock { storedValues } }
    func append(_ value: Duration) { lock.withLock { storedValues.append(value) } }
}

private final class RequestLifecycle: @unchecked Sendable {
    let requestStarted = XCTestExpectation(description: "request started")
    let requestStopped = XCTestExpectation(description: "request stopped")
    let lateHandlerOutput = XCTestExpectation(description: "late handler output")

    private let releaseGate = DispatchSemaphore(value: 0)
    private let timeout = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stopped = false

    var didStop: Bool { lock.withLock { stopped } }

    func waitForRelease() { releaseGate.wait() }
    func release() { releaseGate.signal() }
    func waitForTimeout() { timeout.wait() }
    func startTimeout() { timeout.signal() }
    func stopObserved() {
        let shouldFulfill = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        if shouldFulfill { requestStopped.fulfill() }
    }
}

private final class TaskCompletion: @unchecked Sendable {
    let expectation = XCTestExpectation(description: "operation completed")
    private let lock = NSLock()
    private var finished = false

    var didFinish: Bool { lock.withLock { finished } }
    func finish() {
        let shouldFulfill = lock.withLock { () -> Bool in
            guard !finished else { return false }
            finished = true
            return true
        }
        if shouldFulfill { expectation.fulfill() }
    }
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
