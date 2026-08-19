import XCTest
@testable import TSB

@MainActor
final class LivePreviewPipelineTests: XCTestCase {
    func testChunksStayOrderedAndNextSessionWaitsForPreviousFinish() async {
        let harness = PipelineOperationsHarness(blockFirstFinish: true)
        let pipeline = LivePreviewPipeline(operations: harness.operations)
        let firstID = SessionID(rawValue: UUID())
        let secondID = SessionID(rawValue: UUID())

        let firstFeed = pipeline.start(sessionID: firstID) { _, _ in }
        firstFeed([1])
        firstFeed([2])
        let firstFinish = Task { await pipeline.finish(sessionID: firstID) }
        await harness.waitForFirstFinishStart()

        let secondFeed = pipeline.start(sessionID: secondID) { _, _ in }
        secondFeed([3])
        await Task.yield()
        let beforeRelease = await harness.snapshot()
        XCTAssertFalse(beforeRelease.contains("accept:3"))

        await harness.releaseFirstFinish()
        let firstResult = await firstFinish.value
        let secondResult = await pipeline.finish(sessionID: secondID)
        let events = await harness.snapshot()
        XCTAssertEqual(firstResult, "final:1")
        XCTAssertEqual(secondResult, "final:2")
        XCTAssertEqual(
            events,
            ["accept:1", "accept:2", "finish:1:start", "finish:1:end", "accept:3", "finish:2:start", "finish:2:end"]
        )
    }

    func testFifthQueuedChunkDisablesOnlyOverflowedSession() async {
        let harness = PipelineOperationsHarness(blockFirstFinish: true)
        let pipeline = LivePreviewPipeline(operations: harness.operations)
        let firstID = SessionID(rawValue: UUID())
        let overflowedID = SessionID(rawValue: UUID())

        _ = pipeline.start(sessionID: firstID) { _, _ in }
        let firstFinish = Task { await pipeline.finish(sessionID: firstID) }
        await harness.waitForFirstFinishStart()

        let feed = pipeline.start(sessionID: overflowedID) { _, _ in }
        for value in 1 ... 5 { feed([Float(value)]) }
        let overflowedFinish = Task { await pipeline.finish(sessionID: overflowedID) }

        await harness.releaseFirstFinish()
        let firstResult = await firstFinish.value
        let overflowedResult = await overflowedFinish.value
        let overflowEvents = await harness.snapshot()
        XCTAssertEqual(firstResult, "final:1")
        XCTAssertEqual(overflowedResult, "")
        XCTAssertEqual(overflowEvents.last, "cancel:1")
        XCTAssertFalse(overflowEvents.contains(where: { $0.hasPrefix("accept:") }))

        let thirdID = SessionID(rawValue: UUID())
        let thirdFeed = pipeline.start(sessionID: thirdID) { _, _ in }
        thirdFeed([9])
        let thirdResult = await pipeline.finish(sessionID: thirdID)
        let finalEvents = await harness.snapshot()
        XCTAssertEqual(thirdResult, "final:2")
        XCTAssertTrue(finalEvents.contains("accept:9"))
    }

    func testFinishDrainsChunksBufferedBehindPreviousSession() async {
        let harness = PipelineOperationsHarness(blockFirstFinish: true)
        let pipeline = LivePreviewPipeline(operations: harness.operations)
        let firstID = SessionID(rawValue: UUID())
        let secondID = SessionID(rawValue: UUID())

        _ = pipeline.start(sessionID: firstID) { _, _ in }
        let firstFinish = Task { await pipeline.finish(sessionID: firstID) }
        await harness.waitForFirstFinishStart()

        let feed = pipeline.start(sessionID: secondID) { _, _ in }
        feed([3])
        feed([4])
        let secondFinish = Task { await pipeline.finish(sessionID: secondID) }
        await Task.yield()

        await harness.releaseFirstFinish()
        _ = await firstFinish.value
        let secondResult = await secondFinish.value
        let events = await harness.snapshot()

        XCTAssertEqual(secondResult, "final:2")
        XCTAssertEqual(Array(events.suffix(4)), ["accept:3", "accept:4", "finish:2:start", "finish:2:end"])
    }

    func testCancelDropsBufferedInputAndCancelsRecognizer() async {
        let harness = PipelineOperationsHarness()
        let pipeline = LivePreviewPipeline(operations: harness.operations)
        let sessionID = SessionID(rawValue: UUID())

        let feed = pipeline.start(sessionID: sessionID) { _, _ in }
        feed([1])
        await pipeline.cancel(sessionID: sessionID)

        let events = await harness.snapshot()
        let result = await pipeline.finish(sessionID: sessionID)
        XCTAssertEqual(events, ["cancel:1"])
        XCTAssertEqual(result, "")
    }

    func testPreviewFromSupersededSessionIsNotDelivered() async {
        let harness = PipelineOperationsHarness(blockFirstAccept: true)
        let pipeline = LivePreviewPipeline(operations: harness.operations)
        let firstID = SessionID(rawValue: UUID())
        let secondID = SessionID(rawValue: UUID())
        var previews: [(SessionID, String)] = []

        let firstFeed = pipeline.start(sessionID: firstID) { previews.append(($0, $1)) }
        firstFeed([1])
        await harness.waitForFirstAcceptStart()

        _ = pipeline.start(sessionID: secondID) { previews.append(($0, $1)) }
        await harness.releaseFirstAccept()
        let result = await pipeline.finish(sessionID: firstID)
        XCTAssertEqual(result, "final:1")
        XCTAssertTrue(previews.isEmpty)
        await pipeline.cancel(sessionID: secondID)
    }

    func testOnlyChangedPreviewIsDeliveredWithSessionID() async {
        let harness = PipelineOperationsHarness(preview: "same")
        let pipeline = LivePreviewPipeline(operations: harness.operations)
        let sessionID = SessionID(rawValue: UUID())
        var previews: [(SessionID, String)] = []

        let feed = pipeline.start(sessionID: sessionID) { previews.append(($0, $1)) }
        feed([1])
        feed([2])
        _ = await pipeline.finish(sessionID: sessionID)

        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews.first?.0, sessionID)
        XCTAssertEqual(previews.first?.1, "same")
    }

    func testUnavailableModelIsNoOpAndReturnsEmpty() async {
        let pipeline = LivePreviewPipeline(operations: nil)
        let sessionID = SessionID(rawValue: UUID())
        var previews: [String] = []

        let feed = pipeline.start(sessionID: sessionID) { previews.append($1) }
        feed([1])

        let result = await pipeline.finish(sessionID: sessionID)
        XCTAssertEqual(result, "")
        XCTAssertTrue(previews.isEmpty)
        await pipeline.cancel(sessionID: sessionID)
    }
}

private actor PipelineOperationsHarness {
    private(set) var events: [String] = []
    private let blockFirstFinish: Bool
    private let blockFirstAccept: Bool
    private let preview: String?
    private var finishCount = 0
    private var cancelCount = 0
    private var firstFinishStarted = false
    private var firstFinishStartWaiter: CheckedContinuation<Void, Never>?
    private var firstFinishRelease: CheckedContinuation<Void, Never>?
    private var firstAcceptStarted = false
    private var firstAcceptStartWaiter: CheckedContinuation<Void, Never>?
    private var firstAcceptRelease: CheckedContinuation<Void, Never>?

    init(blockFirstFinish: Bool = false, blockFirstAccept: Bool = false, preview: String? = nil) {
        self.blockFirstFinish = blockFirstFinish
        self.blockFirstAccept = blockFirstAccept
        self.preview = preview
    }

    nonisolated var operations: LivePreviewPipeline.Operations {
        LivePreviewPipeline.Operations(
            accept: { [self] samples in await accept(samples) },
            finish: { [self] in await finish() },
            cancel: { [self] in await cancel() }
        )
    }

    func snapshot() -> [String] { events }

    func waitForFirstFinishStart() async {
        guard !firstFinishStarted else { return }
        await withCheckedContinuation { firstFinishStartWaiter = $0 }
    }

    func releaseFirstFinish() {
        firstFinishRelease?.resume()
        firstFinishRelease = nil
    }

    func waitForFirstAcceptStart() async {
        guard !firstAcceptStarted else { return }
        await withCheckedContinuation { firstAcceptStartWaiter = $0 }
    }

    func releaseFirstAccept() {
        firstAcceptRelease?.resume()
        firstAcceptRelease = nil
    }

    private func accept(_ samples: [Float]) async -> String? {
        let value = Int(samples.first ?? -1)
        events.append("accept:\(value)")
        if blockFirstAccept, !firstAcceptStarted {
            firstAcceptStarted = true
            firstAcceptStartWaiter?.resume()
            firstAcceptStartWaiter = nil
            await withCheckedContinuation { firstAcceptRelease = $0 }
        }
        return preview ?? "preview:\(value)"
    }

    private func finish() async -> String {
        finishCount += 1
        let current = finishCount
        events.append("finish:\(current):start")
        if blockFirstFinish, current == 1 {
            firstFinishStarted = true
            firstFinishStartWaiter?.resume()
            firstFinishStartWaiter = nil
            await withCheckedContinuation { firstFinishRelease = $0 }
        }
        events.append("finish:\(current):end")
        return "final:\(current)"
    }

    private func cancel() {
        cancelCount += 1
        events.append("cancel:\(cancelCount)")
    }
}
