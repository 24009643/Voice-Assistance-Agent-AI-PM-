import SwiftUI
import XCTest
@testable import TSB

final class IslandPresentationTests: XCTestCase {
    func testIdleUsesTheCompactCandidate() {
        let presentation = IslandPresentation.make(
            for: snapshot(status: .idle),
            screenWidth: 1_440
        )

        XCTAssertEqual(presentation.mode, .idle)
        XCTAssertEqual(presentation.size, CGSize(width: 120, height: 30))
    }

    func testRecordingUsesLiveCandidateAndExposesStopAndLocalOnly() {
        let sessionID = SessionID(rawValue: UUID())
        let presentation = IslandPresentation.make(
            for: snapshot(
                sessionID: sessionID,
                status: .recording,
                previewText: "a live one-line draft",
                audioLevel: 0.6
            ),
            screenWidth: 1_440
        )

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

    func testUnavailableLivePreviewIsVisibleWithoutPretendingItIsTranscriptText() {
        let value = snapshot(
            status: .recording,
            livePreviewAvailability: .unavailable
        )
        let presentation = IslandPresentation.make(for: value)

        XCTAssertEqual(value.previewText, "")
        XCTAssertEqual(presentation.statusText, "实时草稿不可用")
        XCTAssertEqual(presentation.draft, "停止后仍会生成全文")
        XCTAssertEqual(presentation.accessibilityLabel, "实时草稿不可用，停止后仍会生成全文")
        XCTAssertTrue(presentation.controls.map(\.action).contains(.stopRecording))
    }

    func testLocalDeliveryStaysCompactAndOrganizingNeverAutoHides() {
        let requestID = UUID()
        let presentation = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "saved locally",
                message: "已复制 · 按 ⌘V 粘贴",
                organizationPhase: .organizing,
                organizationRequestID: requestID
            ),
            screenWidth: 1_440
        )

        XCTAssertEqual(presentation.mode, .organizing)
        XCTAssertEqual(presentation.size, CGSize(width: 520, height: 82))
        XCTAssertNil(presentation.autoHideDelay)
        XCTAssertTrue(presentation.controls.map(\.action).contains(.cancelOrganization(requestID)))
    }

    func testExactLocalDeliveryUsesAccessibleCopyConfirmation() {
        let presentation = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "local result",
                message: "已复制 · 按 ⌘V 粘贴"
            )
        )

        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
        XCTAssertFalse(presentation.accessibilityLabel.isEmpty)
        XCTAssertEqual(presentation.autoHideDelay, 1.2)
    }

    func testDeliveryWarningsNeverUseSuccessToneOrAutoHide() {
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
            let presentation = IslandPresentation.make(for: snapshot)
            XCTAssertNotEqual(presentation.tone, .success)
            XCTAssertNil(presentation.autoHideDelay)
        }
    }

    @MainActor
    func testStatusRenderingUsesCleanedDraftWhileRawTextRemainsSeparate() {
        let cases: [(snapshot: AppSnapshot, mode: IslandMode, cleaned: String, raw: String)] = [
            (
                snapshot(
                    status: .delivered,
                    previewText: "cleaned local delivered",
                    originalText: "raw local delivered",
                    message: "已复制 · 按 ⌘V 粘贴"
                ),
                .localDelivered,
                "cleaned local delivered",
                "raw local delivered"
            ),
            (
                snapshot(
                    status: .delivered,
                    previewText: "cleaned organizing",
                    originalText: "raw organizing",
                    organizationPhase: .organizing
                ),
                .organizing,
                "cleaned organizing",
                "raw organizing"
            ),
            (
                snapshot(
                    status: .failed,
                    previewText: "cleaned failed",
                    originalText: "raw failed",
                    message: "Needs attention"
                ),
                .failed,
                "cleaned failed",
                "raw failed"
            ),
        ]

        for testCase in cases {
            let presentation = IslandPresentation.make(for: testCase.snapshot)
            XCTAssertEqual(presentation.mode, testCase.mode)
            XCTAssertEqual(IslandView.statusDetailText(for: presentation), testCase.cleaned)
            XCTAssertNotEqual(IslandView.statusDetailText(for: presentation), testCase.raw)
            XCTAssertEqual(
                presentation.intent(for: .copyChamber(.original)),
                .copy(testCase.raw)
            )
        }
    }

    func testStatusControlsOfferCopyOriginalOnlyWhenRawTextExists() {
        let emptyRawSnapshots = [
            snapshot(status: .transcribing, previewText: "live draft"),
            snapshot(status: .failed, message: "Could not start recording."),
            snapshot(
                status: .delivered,
                previewText: "cleaned delivered",
                message: "已复制 · 按 ⌘V 粘贴"
            ),
        ]
        let rawSnapshots = [
            snapshot(
                status: .delivered,
                previewText: "cleaned organizing",
                originalText: "raw organizing",
                organizationPhase: .organizing
            ),
            snapshot(
                status: .failed,
                previewText: "cleaned failed",
                originalText: "raw failed",
                organizationPhase: .failed("Organization failed.")
            ),
        ]

        for snapshot in emptyRawSnapshots {
            XCTAssertFalse(
                IslandPresentation.make(for: snapshot).controls.map(\.action).contains(.copyChamber(.original))
            )
        }
        for snapshot in rawSnapshots {
            XCTAssertTrue(
                IslandPresentation.make(for: snapshot).controls.map(\.action).contains(.copyChamber(.original))
            )
        }
    }

    func testDeliveryDoesNotAutoHideWhileAnOlderOrganizationIsRunning() {
        let presentation = IslandPresentation.make(
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
        )

        XCTAssertNil(presentation.autoHideDelay)
    }

    func testDeliveryDoesNotAutoHideWhileAnOlderLocalTranscriptIsRunning() {
        let presentation = IslandPresentation.make(
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
        )

        XCTAssertNil(presentation.autoHideDelay)
    }

    func testOrganizedUsesThreeChambersAtTheClampedMaximum() {
        let presentation = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "cleaned local text",
                originalText: "raw original text",
                organizationPhase: .organized(organizedRecord())
            ),
            screenWidth: 800
        )

        XCTAssertEqual(presentation.mode, .organized)
        XCTAssertEqual(presentation.size, CGSize(width: 776, height: 154))
        XCTAssertEqual(presentation.layout, .threeChambers)
        XCTAssertEqual(presentation.originalText, "raw original text")
        XCTAssertEqual(presentation.draft, "cleaned local text")
        XCTAssertEqual(presentation.chambers, IslandChamber.allCases)
        XCTAssertEqual(presentation.numberedPoints.map(\.text), ["First point", "Second point"])
        XCTAssertEqual(presentation.speculativeConnections.map(\.label), ["推测"])
    }

    func testNarrowOrganizedLayoutUsesOneChamberAndVisibleSegments() {
        let presentation = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "original local text",
                organizationPhase: .organized(organizedRecord())
            ),
            screenWidth: 620
        )

        XCTAssertEqual(presentation.layout, .singleChamber)
        XCTAssertEqual(
            presentation.controls.compactMap(\.chamberSelection),
            IslandChamber.allCases
        )
    }

    func testGestureNavigationAlwaysHasVisibleAccessibleControls() {
        let idle = IslandPresentation.make(
            for: snapshot(status: .idle),
            screenWidth: 620,
            hasLatestResult: true
        )
        let result = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                previewText: "original local text",
                organizationPhase: .organized(organizedRecord())
            ),
            screenWidth: 620
        )

        XCTAssertEqual(idle.controls.map(\.action), [.reopenLatest])
        XCTAssertEqual(result.controls.compactMap(\.chamberSelection), IslandChamber.allCases)
        XCTAssertTrue((idle.controls + result.controls).allSatisfy {
            !$0.title.isEmpty && !$0.accessibilityLabel.isEmpty
        })
    }

    @MainActor
    func testActualIslandAndWaveformReduceMotionAnimationChoices() {
        let normalIsland = IslandView.animation(reduceMotion: false)
        let reducedIsland = IslandView.animation(reduceMotion: true)

        XCTAssertEqual(normalIsland, .spring(response: 0.28, dampingFraction: 0.86))
        XCTAssertEqual(reducedIsland, .easeOut(duration: 0.12))
        XCTAssertNotEqual(normalIsland, reducedIsland)
        XCTAssertEqual(
            NotchWaveformView.animation(reduceMotion: false),
            .easeOut(duration: 0.08)
        )
        XCTAssertNil(NotchWaveformView.animation(reduceMotion: true))
    }

    func testSuggestionsStayLocalUntilGenerateLinksIsExplicitlyActivated() {
        let suggestedID = SessionID(rawValue: UUID())
        let targetID = SessionID(rawValue: UUID())
        let presentation = IslandPresentation.make(
            for: snapshot(
                sessionID: targetID,
                status: .delivered,
                previewText: "original local text",
                organizationPhase: .organized(organizedRecord()),
                suggestedRecords: [SuggestedRecordSnapshot(id: suggestedID, summary: "related local note")]
            ),
            screenWidth: 1_440
        )

        XCTAssertEqual(presentation.suggestions.map(\.id), [suggestedID])
        XCTAssertTrue(presentation.controls.map(\.action).contains(.generateLinks))
        XCTAssertNil(presentation.intent(for: .generateLinks, selectedRecordIDs: []))
        XCTAssertEqual(
            presentation.intent(for: .generateLinks, selectedRecordIDs: [suggestedID]),
            .generateLinks(sessionID: targetID, selectedRecordIDs: [suggestedID])
        )
    }

    func testAuthorizationFailureOffersOpenSettings() {
        let presentation = IslandPresentation.make(
            for: snapshot(status: .delivered, organizationPhase: .authorizationRequired)
        )

        XCTAssertTrue(presentation.controls.map(\.action).contains(.openSettings))
        XCTAssertEqual(presentation.intent(for: .openSettings), .openSettings)
    }

    func testDeterministicResultDoesNotOfferImpossibleLinkGeneration() {
        let presentation = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                organizationPhase: .organized(organizedRecord(provider: "deterministic")),
                suggestedRecords: [
                    SuggestedRecordSnapshot(id: SessionID(rawValue: UUID()), summary: "local suggestion"),
                ]
            )
        )

        XCTAssertFalse(presentation.controls.map(\.action).contains(.generateLinks))
    }

    func testOrganizedResultShowsLocalPrivacyReceiptWithoutText() {
        let presentation = IslandPresentation.make(
            for: snapshot(status: .delivered, organizationPhase: .organized(organizedRecord())),
            screenWidth: 1_440
        )

        XCTAssertEqual(
            presentation.privacyReceiptText,
            "已发送 128 个字符 · 1 条历史摘要（00000000-0000-0000-0000-000000000201）"
        )
    }

    func testLoopbackOrganizationShowsLocalPrivacyReceipt() {
        let presentation = IslandPresentation.make(
            for: snapshot(
                status: .delivered,
                organizationPhase: .organized(organizedRecord(providerKind: .local))
            )
        )

        XCTAssertEqual(
            presentation.privacyReceiptText,
            "本地处理 128 个字符 · 1 条历史摘要（00000000-0000-0000-0000-000000000201）"
        )
    }

    private func snapshot(
        sessionID: SessionID? = nil,
        status: SessionStatus,
        previewText: String = "",
        originalText: String = "",
        message: String? = nil,
        audioLevel: Float = 0,
        livePreviewAvailability: LivePreviewAvailability = .available,
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
            livePreviewAvailability: livePreviewAvailability,
            organizationPhase: organizationPhase,
            organizationRequestID: organizationRequestID,
            suggestedRecords: suggestedRecords
        )
    }

    private func organizedRecord(
        provider: String = "openai-compatible",
        providerKind: ProviderKind = .remote
    ) -> OrganizationRecord {
        let selectedID = SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
        return OrganizationRecord(
            requestID: UUID(),
            inputTextSHA256: String(repeating: "a", count: 64),
            state: .succeeded,
            provider: provider,
            model: "test-model",
            providerKind: providerKind,
            selectedRecordIDs: [selectedID],
            sentCharacterCount: 128,
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
