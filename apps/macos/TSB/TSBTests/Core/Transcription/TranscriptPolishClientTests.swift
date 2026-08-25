import XCTest
@testable import TSB

final class TranscriptPolishClientTests: XCTestCase {
    override func tearDown() { PolishURLProtocol.handler = nil; super.tearDown() }

    func testRequestContainsOnlyTextCandidatesAndTerminologyInExactOrder() async throws {
        let request = fixtureRequest()
        PolishURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.httpBody ?? readBody(request.httpBodyStream))
            XCTAssertLessThanOrEqual(body.count, TranscriptPolishClient.maximumOuterBytes)
            let outer = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Array(outer.keys).sorted(), ["messages", "model", "response_format"])
            let messages = try XCTUnwrap(outer["messages"] as? [[String: String]])
            XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
            let system = try XCTUnwrap(messages.first?["content"])
            for clause in ["schema_version, request_id, candidate_hashes, base_candidate_id, corrected_text, edits", "tsb.transcript_polish.response.v1", "offline then streaming", "kind,start_utf16,length_utf16,original,replacement,reason", "<=8000 Unicode scalars", "edits <=128", "<=256 scalars", "reason <=120", "ceil(20%", "nonoverlapping", "Numbers, URLs, and emails are immutable", "whitespace, punctuation, or Latin case", "exact submitted alias to canonical", "corresponding contiguous location", "Do not summarize, answer, add examples/new facts, or make context-only inference"] { XCTAssertTrue(system.contains(clause), clause) }
            let inner = try XCTUnwrap(messages.last?["content"])
            XCTAssertLessThanOrEqual(Data(inner.utf8).count, TranscriptPolishClient.maximumInnerBytes)
            XCTAssertFalse(inner.contains("audio")); XCTAssertFalse(inner.contains("session")); XCTAssertFalse(inner.contains("history"))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String: Any])
            XCTAssertEqual(Array(payload.keys).sorted(), ["candidates", "request_id", "schema_version", "terminology"])
            XCTAssertEqual((payload["candidates"] as? [[String: String]])?.map { $0["candidate_id"] }, ["offline", "streaming"])
            return .response(self.makeOuterResponse(content: self.makeInnerResponse(for: self.fixtureRequest())))
        }
        let result = try await client().polish(request, apiKey: "synthetic-key")
        guard case .accepted = result else { return XCTFail("expected accepted") }
    }

    func testRejectsInsecureEndpointOuterUnknownKeysAndMoreThanOneChoice() async throws {
        await XCTAssertThrowsErrorAsync { try await self.client(url: "http://example.test/chat").polish(self.fixtureRequest(), apiKey: "key") }
        for response in [Data("{\"choices\":[],\"leak\":true}".utf8), Data("{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"{}\"}},{\"message\":{\"role\":\"assistant\",\"content\":\"{}\"}}]}".utf8)] {
            PolishURLProtocol.handler = { _ in .response(response) }
            await XCTAssertThrowsErrorAsync { try await self.client().polish(self.fixtureRequest(), apiKey: "key") }
        }
    }

    func testRejectsOuterAndInnerOverflowAndCancellation() async throws {
        PolishURLProtocol.handler = { _ in .chunks([Data(repeating: 0x20, count: 32_768), Data(repeating: 0x20, count: 32_769)]) }
        do { _ = try await self.client().polish(self.fixtureRequest(), apiKey: "secret"); XCTFail("expected streamed overflow") } catch { XCTAssertEqual(error as? TranscriptPolishClientError, .responseTooLarge) }
        let oversized = TranscriptPolishRequest(requestID: UUID(), candidates: [.init(id: .offline, text: String(repeating: "x", count: 8_001))], terminology: [])
        await XCTAssertThrowsErrorAsync { try await self.client().polish(oversized, apiKey: "secret") }
        let client = client()
        let request = fixtureRequest()
        let task = Task { try await client.polish(request, apiKey: "secret") }
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testAllowsLoopbackAndRejectsEmptyOrIrrelevantTerminology() async throws {
        PolishURLProtocol.handler = { _ in .response(self.makeOuterResponse(content: self.makeInnerResponse(for: self.fixtureRequest()))) }
        _ = try await client(url: "http://127.0.0.1:11434/chat").polish(fixtureRequest(), apiKey: "")
        let invalid = TranscriptPolishRequest(requestID: UUID(), candidates: [.init(id: .offline, text: "alpha")], terminology: [.init(canonical: "", aliases: ["x"]), .init(canonical: "unused", aliases: ["never"])])
        PolishURLProtocol.handler = { _ in XCTFail("invalid terminology must not reach network"); throw URLError(.badServerResponse) }
        await XCTAssertThrowsErrorAsync { try await self.client().polish(invalid, apiKey: "key") }
    }

    func testRejectsRedirectBeforeTargetReceivesTranscript() async throws {
        let origin = URL(string: "https://origin.test/chat")!, target = URL(string: "https://attacker.test/collect")!
        let urls = URLList()
        let observed = expectation(description: "origin observed"), rejected = expectation(description: "delegate rejected redirect")
        PolishURLProtocol.handler = { request in urls.append(request.url!); observed.fulfill(); return .redirect(target) }
        let client = client(url: origin.absoluteString, onRedirectRejected: { rejected.fulfill() }), request = fixtureRequest()
        let task = Task { try await client.polish(request, apiKey: "key") }
        await fulfillment(of: [observed], timeout: 1)
        await fulfillment(of: [rejected], timeout: 1)
        XCTAssertEqual(urls.values, [origin])
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError || error is URLError) }
    }

    private func fixtureRequest() -> TranscriptPolishRequest { TranscriptPolishRequest(requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!, candidates: [.init(id: .offline, text: "Use TB for this dictation"), .init(id: .streaming, text: "Use TSB for this dictation")], terminology: [.init(canonical: "TSB", aliases: ["TB"])]) }
    private func client(url: String = "https://example.test/chat", onRedirectRejected: @escaping @Sendable () -> Void = {}) -> TranscriptPolishClient { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [PolishURLProtocol.self]; return TranscriptPolishClient(endpoint: .init(baseURL: URL(string: url)!, model: "test-model"), session: URLSession(configuration: c), onRedirectRejected: onRedirectRejected) }
    private func makeInnerResponse(for request: TranscriptPolishRequest) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: ["schema_version": "tsb.transcript_polish.response.v1", "request_id": request.requestID.uuidString.lowercased(), "candidate_hashes": request.candidates.map { ["candidate_id": $0.id.rawValue, "text_sha256": $0.textSHA256] }, "base_candidate_id": "offline", "corrected_text": "Use TSB for this dictation", "edits": [["kind": "terminology", "start_utf16": 4, "length_utf16": 2, "original": "TB", "replacement": "TSB", "reason": "approved"]]], options: [.sortedKeys]), as: UTF8.self) }
    private func makeOuterResponse(content: String) -> Data { try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": content]]]]) }
}

private func readBody(_ stream: InputStream?) -> Data? { guard let stream else { return nil }; stream.open(); defer { stream.close() }; var result = Data(); let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buffer.deallocate() }; while stream.hasBytesAvailable { let count = stream.read(buffer, maxLength: 4096); guard count >= 0 else { return nil }; result.append(buffer, count: count) }; return result }

private final class PolishURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Result)?
    enum Result { case response(Data), chunks([Data]), redirect(URL) }
    private let stateLock = NSLock(); private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { guard let handler = Self.handler else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }; DispatchQueue.global().async { [self] in do { let result = try handler(request); guard !isStopped else { return }; switch result { case let .response(data): deliver([data]); case let .chunks(parts): deliver(parts); case let .redirect(url): var redirected = request; redirected.url = url; client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": url.absoluteString])!) } } catch { client?.urlProtocol(self, didFailWithError: error) } } }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
    private var isStopped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return stopped }
    private func deliver(_ parts: [Data]) { let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!; client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); for part in parts { guard !isStopped else { return }; client?.urlProtocol(self, didLoad: part) }; client?.urlProtocolDidFinishLoading(self) }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @escaping () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) } catch {} }
private final class URLList: @unchecked Sendable { private let lock = NSLock(); private var urls: [URL] = []; func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }; var values: [URL] { lock.lock(); defer { lock.unlock() }; return urls } }
