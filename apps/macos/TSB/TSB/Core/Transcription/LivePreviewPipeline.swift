import Foundation

@MainActor
final class LivePreviewPipeline {
    struct Operations: Sendable {
        let accept: @Sendable ([Float]) async -> String?
        let finish: @Sendable () async -> String
        let cancel: @Sendable () async -> Void
    }

    typealias Feed = @Sendable ([Float]) -> Void
    typealias Preview = @MainActor (SessionID, String) -> Void

    private let operations: Operations?
    private var sessions: [SessionID: Session] = [:]
    private var tail: Task<String, Never>?
    private var latestSessionID: SessionID?

    init(transcriber: ParaformerPreviewTranscriber?) {
        operations = transcriber.map { transcriber in
            Operations(
                accept: { await transcriber.accept(samples: $0) },
                finish: { await transcriber.finish() },
                cancel: { await transcriber.cancel() }
            )
        }
    }

    init(operations: Operations?) {
        self.operations = operations
    }

    func start(sessionID: SessionID, onPreview: @escaping Preview) -> Feed {
        latestSessionID = sessionID
        guard let operations else { return { _ in } }

        let input = SessionInput()
        let previous = tail
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self else { return "" }
            return await self.run(
                sessionID: sessionID,
                input: input,
                operations: operations,
                onPreview: onPreview
            )
        }
        let session = Session(input: input, task: task)
        sessions[sessionID] = session
        tail = task
        return { input.feed($0) }
    }

    func finish(sessionID: SessionID) async -> String {
        guard let session = sessions[sessionID] else { return "" }
        session.input.end(.finish)
        let result = await session.task.value
        remove(sessionID: sessionID, session: session)
        return result
    }

    func cancel(sessionID: SessionID) async {
        guard let session = sessions[sessionID] else { return }
        session.input.end(.cancel)
        _ = await session.task.value
        remove(sessionID: sessionID, session: session)
    }

    private func run(
        sessionID: SessionID,
        input: SessionInput,
        operations: Operations,
        onPreview: @escaping Preview
    ) async -> String {
        for await chunk in input.stream {
            guard !input.discardsBufferedInput else { continue }
            guard let preview = await operations.accept(chunk), !input.discardsBufferedInput else { continue }
            publish(preview, sessionID: sessionID, onPreview: onPreview)
        }

        switch input.endReason {
        case .finish:
            return await operations.finish()
        case .cancel, .overflow, nil:
            await operations.cancel()
            return ""
        }
    }

    private func publish(_ preview: String, sessionID: SessionID, onPreview: Preview) {
        guard latestSessionID == sessionID,
              let session = sessions[sessionID],
              preview != session.lastPreview else { return }
        session.lastPreview = preview
        onPreview(sessionID, preview)
    }

    private func remove(sessionID: SessionID, session: Session) {
        guard sessions[sessionID] === session else { return }
        sessions.removeValue(forKey: sessionID)
        if latestSessionID == sessionID { latestSessionID = nil }
    }
}

private extension LivePreviewPipeline {
    final class Session {
        let input: SessionInput
        let task: Task<String, Never>
        var lastPreview = ""

        init(input: SessionInput, task: Task<String, Never>) {
            self.input = input
            self.task = task
        }
    }

    final class SessionInput: @unchecked Sendable {
        enum EndReason {
            case finish
            case cancel
            case overflow
        }

        let stream: AsyncStream<[Float]>
        private let continuation: AsyncStream<[Float]>.Continuation
        private let lock = NSLock()
        private var storedEndReason: EndReason?

        init() {
            let pair = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingOldest(4))
            stream = pair.stream
            continuation = pair.continuation
        }

        var endReason: EndReason? {
            lock.withLock { storedEndReason }
        }

        var discardsBufferedInput: Bool {
            lock.withLock {
                storedEndReason == .cancel || storedEndReason == .overflow
            }
        }

        func feed(_ samples: [Float]) {
            guard !samples.isEmpty else { return }
            lock.withLock {
                guard storedEndReason == nil else { return }
                if case .dropped = continuation.yield(samples) {
                    storedEndReason = .overflow
                    continuation.finish()
                }
            }
        }

        func end(_ reason: EndReason) {
            lock.withLock {
                guard storedEndReason == nil else { return }
                storedEndReason = reason
                continuation.finish()
            }
        }
    }
}
