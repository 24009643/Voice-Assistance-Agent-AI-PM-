import XCTest
@testable import TSB

final class IslandPresentationTests: XCTestCase {
    func testIdleUsesTheCompactCandidate() throws {
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(status: .idle),
            screenWidth: 1_440
        ))

        XCTAssertEqual(presentation.mode, .idle)
        XCTAssertEqual(presentation.size, CGSize(width: 120, height: 30))
    }

    func testRecordingUsesLiveCandidateAndExposesStopAndLocalOnly() throws {
        let sessionID = SessionID(rawValue: UUID())
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                sessionID: sessionID,
                status: .recording,
                previewText: "a live one-line draft",
                audioLevel: 0.6
            ),
            screenWidth: 1_440
        ))

        XCTAssertEqual(presentation.mode, .recording)
        XCTAssertEqual(presentation.size, CGSize(width: 520, height: 82))
        XCTAssertEqual(presentation.draft, "a live one-line draft")
        XCTAssertEqual(presentation.audioLevel, 0.6)
        XCTAssertTrue(presentation.controls.map(\.action).contains(.stopRecording))
        XCTAssertTrue(presentation.controls.map(\.action).contains(.setLocalOnly(true)))
        XCTAssertEqual(presentation.intent(for: .stopRecording), .stopRecording(sessionID: sessionID))
        XCTAssertEqual(
            presentation.intent(for: .setLocalOnly(true)),
            .setLocalOnly(sessionID: sessionID, enabled: true)
        )
    }

    func testLocalDeliveryStaysCompactAndOrganizingNeverAutoHides() throws {
        let requestID = UUID()
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "saved locally",
                message: "已复制 · 按 ⌘V 粘贴",
                organizationPhase: .organizing,
                organizationRequestID: requestID
            ),
            screenWidth: 1_440
        ))

        XCTAssertEqual(presentation.mode, .organizing)
        XCTAssertEqual(presentation.size, CGSize(width: 520, height: 82))
        XCTAssertNil(presentation.autoHideDelay)
        XCTAssertTrue(presentation.controls.map(\.action).contains(.cancelOrganization(requestID)))
    }

    func testExactLocalDeliveryUsesAccessibleCopyConfirmation() throws {
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "local result",
                message: "已复制 · 按 ⌘V 粘贴"
            )
        ))

        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
        XCTAssertFalse(presentation.accessibilityLabel.isEmpty)
        XCTAssertEqual(presentation.autoHideDelay, 1.2)
    }

    func testDeliveryWarningsNeverUseSuccessToneOrAutoHide() throws {
        let snapshots = [
            snapshot(
                status: .delivered,
                message: "已复制，但未能记录复制状态"
            ),
            snapshot(
                status: .delivered,
                previewText: "已复制 · 按 ⌘V 粘贴"
            ),
        ]

        for snapshot in snapshots {
            let presentation = try XCTUnwrap(IslandPresentation.make(for: snapshot))
            XCTAssertNotEqual(presentation.tone, .success)
            XCTAssertNil(presentation.autoHideDelay)
        }
    }

    func testDeliveryDoesNotAutoHideWhileAnOlderOrganizationIsRunning() throws {
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: AppSnapshot(
                status: .delivered,
                elapsedMilliseconds: 0,
                previewText: "new local result",
                message: "已复制 · 按 ⌘V 粘贴",
                secondaryProcessing: [
                    SecondaryProcessingSnapshot(
                        id: SessionID(rawValue: UUID()),
                        status: .delivered,
                        previewText: "older local result",
                        message: "已复制 · 按 ⌘V 粘贴",
                        organizationPhase: .organizing,
                        organizationRequestID: UUID()
                    ),
                ]
            ),
            screenWidth: 1_440
        ))

        XCTAssertNil(presentation.autoHideDelay)
    }

    func testDeliveryDoesNotAutoHideWhileAnOlderLocalTranscriptIsRunning() throws {
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: AppSnapshot(
                status: .delivered,
                elapsedMilliseconds: 0,
                previewText: "new local result",
                message: "已复制 · 按 ⌘V 粘贴",
                secondaryProcessing: [
                    SecondaryProcessingSnapshot(
                        id: SessionID(rawValue: UUID()),
                        status: .transcribing,
                        previewText: "older draft",
                        message: "本地复核中"
                    ),
                ]
            ),
            screenWidth: 1_440
        ))

        XCTAssertNil(presentation.autoHideDelay)
    }

    func testOrganizedUsesThreeChambersAtTheClampedMaximum() throws {
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "cleaned local text",
                originalText: "raw original text",
                organizationPhase: .organized(organizedRecord())
            ),
            screenWidth: 800
        ))

        XCTAssertEqual(presentation.mode, .organized)
        XCTAssertEqual(presentation.size, CGSize(width: 776, height: 154))
        XCTAssertEqual(presentation.layout, .threeChambers)
        XCTAssertEqual(presentation.originalText, "raw original text")
        XCTAssertEqual(presentation.draft, "cleaned local text")
        XCTAssertEqual(presentation.chambers, IslandChamber.allCases)
        XCTAssertEqual(presentation.numberedPoints.map(\.text), ["First point", "Second point"])
        XCTAssertEqual(presentation.speculativeConnections.map(\.label), ["推测"])
    }

    func testNarrowOrganizedLayoutUsesOneChamberAndVisibleSegments() throws {
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "original local text",
                organizationPhase: .organized(organizedRecord())
            ),
            screenWidth: 620
        ))

        XCTAssertEqual(presentation.layout, .singleChamber)
        XCTAssertEqual(
            presentation.controls.compactMap(\.chamberSelection),
            IslandChamber.allCases
        )
    }

    func testGestureNavigationAlwaysHasVisibleAccessibleControls() throws {
        let idle = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(status: .idle),
            screenWidth: 620,
            hasLatestResult: true
        ))
        let result = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "original local text",
                organizationPhase: .organized(organizedRecord())
            ),
            screenWidth: 620
        ))

        XCTAssertEqual(idle.controls.map(\.action), [.reopenLatest])
        XCTAssertEqual(result.controls.compactMap(\.chamberSelection), IslandChamber.allCases)
        XCTAssertTrue((idle.controls + result.controls).allSatisfy {
            !$0.title.isEmpty && !$0.accessibilityLabel.isEmpty
        })
    }

    @MainActor
    func testActualIslandAndWaveformReduceMotionAnimationChoices() {
        XCTAssertNotNil(IslandView.animation(reduceMotion: false))
        XCTAssertNotNil(IslandView.animation(reduceMotion: true))
        XCTAssertNotNil(NotchWaveformView.animation(reduceMotion: false))
        XCTAssertNil(NotchWaveformView.animation(reduceMotion: true))
    }

    func testSuggestionsStayLocalUntilGenerateLinksIsExplicitlyActivated() throws {
        let suggestedID = SessionID(rawValue: UUID())
        let targetID = SessionID(rawValue: UUID())
        let presentation = try XCTUnwrap(IslandPresentation.make(
            for: snapshot(
                sessionID: targetID,
                status: .delivered,
                previewText: "original local text",
                organizationPhase: .organized(organizedRecord()),
                suggestedRecords: [SuggestedRecordSnapshot(id: suggestedID, summary: "related local note")]
            ),
            screenWidth: 1_440
        ))

        XCTAssertEqual(presentation.suggestions.map(\.id), [suggestedID])
        XCTAssertTrue(presentation.controls.map(\.action).contains(.generateLinks))
        XCTAssertNil(presentation.intent(for: .generateLinks, selectedRecordIDs: []))
        XCTAssertEqual(
            presentation.intent(for: .generateLinks, selectedRecordIDs: [suggestedID]),
            .generateLinks(sessionID: targetID, selectedRecordIDs: [suggestedID])
        )
    }

    private func snapshot(
        sessionID: SessionID? = nil,
        status: SessionStatus,
        previewText: String = "",
        originalText: String = "",
        message: String? = nil,
        audioLevel: Float = 0,
        organizationPhase: OrganizationPhase = .notRequested,
        organizationRequestID: UUID? = nil,
        suggestedRecords: [SuggestedRecordSnapshot] = []
    ) -> AppSnapshot {
        AppSnapshot(
            sessionID: sessionID,
            status: status,
            elapsedMilliseconds: 0,
            previewText: previewText,
            originalText: originalText,
            message: message,
            audioLevel: audioLevel,
            organizationPhase: organizationPhase,
            organizationRequestID: organizationRequestID,
            suggestedRecords: suggestedRecords
        )
    }

    private func organizedRecord() -> OrganizationRecord {
        OrganizationRecord(
            requestID: UUID(),
            inputTextSHA256: String(repeating: "a", count: 64),
            state: .succeeded,
            provider: "local",
            model: "deterministic",
            providerKind: .local,
            selectedRecordIDs: [],
            output: OrganizationOutput(
                noResultReason: nil,
                numberedPoints: [
                    NumberedPoint(number: 1, text: "First point", sourceSegmentIDs: ["c1"]),
                    NumberedPoint(number: 2, text: "Second point", sourceSegmentIDs: ["c2"]),
                ],
                knownRecordLinks: [],
                speculativeConnections: [
                    SpeculativeConnection(
                        statement: "Possible connection",
                        whySpeculative: "Not confirmed",
                        sourceSegmentIDs: ["c1"],
                        relatedRecordIDs: []
                    ),
                ]
            ),
            errorCode: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
