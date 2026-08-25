import Foundation

enum IslandMode: Equatable, Sendable {
    case idle
    case recording
    case localDelivered
    case organizing
    case organized
    case failed
}

enum IslandLayout: Equatable, Sendable {
    case compact
    case threeChambers
    case singleChamber
}

enum IslandChamber: String, CaseIterable, Hashable, Sendable {
    case original
    case points
    case connections

    var title: String {
        switch self {
        case .original: "原文"
        case .points: "要点"
        case .connections: "关联"
        }
    }
}

enum IslandAction: Hashable, Sendable {
    case stopRecording
    case setLocalOnly(Bool)
    case cancelOrganization(UUID)
    case retryOrganization(UUID)
    case selectChamber(IslandChamber)
    case reopenLatest
    case dismiss
    case copyChamber(IslandChamber)
    case generateLinks
    case openSettings
}

enum IslandIntent: Equatable, Sendable {
    case stopRecording(sessionID: SessionID)
    case setLocalOnly(sessionID: SessionID, enabled: Bool)
    case cancelOrganization(sessionID: SessionID, requestID: UUID)
    case retryOrganization(sessionID: SessionID, requestID: UUID)
    case generateLinks(sessionID: SessionID, selectedRecordIDs: Set<SessionID>)
    case copy(String)
    case openSettings
}

struct IslandControl: Equatable, Hashable, Sendable {
    let action: IslandAction
    let title: String
    let accessibilityLabel: String

    var chamberSelection: IslandChamber? {
        guard case let .selectChamber(chamber) = action else { return nil }
        return chamber
    }
}

struct IslandSpeculativeConnection: Equatable, Sendable {
    let statement: String
    let detail: String
    let label = "推测"
}

struct IslandPresentation: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case neutral
        case success
        case warning
    }

    let mode: IslandMode
    let size: CGSize
    let layout: IslandLayout
    let statusText: String
    let tone: Tone
    let systemImage: String?
    let accessibilityLabel: String
    let draft: String
    let audioLevel: Float
    let originalText: String
    let numberedPoints: [NumberedPoint]
    let knownRecordLinks: [KnownRecordLink]
    let speculativeConnections: [IslandSpeculativeConnection]
    let suggestions: [SuggestedRecordSnapshot]
    let privacyReceiptText: String
    let chambers: [IslandChamber]
    let controls: [IslandControl]
    let autoHideDelay: TimeInterval?
    let targetSessionID: SessionID?

    static func make(
        for snapshot: AppSnapshot,
        screenWidth: CGFloat = 1_440,
        hasLatestResult: Bool = false
    ) -> Self {
        let mode = mode(for: snapshot)
        let maximumWidth = max(1, screenWidth - 24)
        let preferredSize: CGSize
        let layout: IslandLayout
        switch mode {
        case .idle:
            preferredSize = CGSize(width: 120, height: 30)
            layout = .compact
        case .organized:
            preferredSize = CGSize(width: 890, height: 154)
            layout = maximumWidth >= 720 ? .threeChambers : .singleChamber
        default:
            preferredSize = CGSize(width: 520, height: 82)
            layout = .compact
        }

        let output: OrganizationOutput?
        if case let .organized(record) = snapshot.organizationPhase {
            output = record.output
        } else {
            output = nil
        }
        let speculative = output?.speculativeConnections.map {
            IslandSpeculativeConnection(statement: $0.statement, detail: $0.whySpeculative)
        } ?? []
        let status = status(for: snapshot, mode: mode)
        let controls = controls(
            for: snapshot,
            mode: mode,
            layout: layout,
            hasLatestResult: hasLatestResult
        )
        return Self(
            mode: mode,
            size: CGSize(
                width: min(preferredSize.width, maximumWidth),
                height: preferredSize.height
            ),
            layout: layout,
            statusText: status.text,
            tone: status.tone,
            systemImage: status.systemImage,
            accessibilityLabel: status.accessibilityLabel,
            draft: snapshot.previewText,
            audioLevel: snapshot.audioLevel,
            originalText: snapshot.originalText,
            numberedPoints: output?.numberedPoints ?? [],
            knownRecordLinks: output?.knownRecordLinks ?? [],
            speculativeConnections: speculative,
            suggestions: snapshot.suggestedRecords,
            privacyReceiptText: privacyReceipt(for: snapshot),
            chambers: mode == .organized ? IslandChamber.allCases : [],
            controls: controls,
            autoHideDelay: autoHideDelay(for: snapshot, mode: mode),
            targetSessionID: snapshot.sessionID
        )
    }

    func intent(
        for action: IslandAction,
        selectedRecordIDs: Set<SessionID> = []
    ) -> IslandIntent? {
        switch action {
        case .stopRecording:
            guard let targetSessionID else { return nil }
            return .stopRecording(sessionID: targetSessionID)
        case let .setLocalOnly(enabled):
            guard let targetSessionID else { return nil }
            return .setLocalOnly(sessionID: targetSessionID, enabled: enabled)
        case let .cancelOrganization(requestID):
            guard let targetSessionID else { return nil }
            return .cancelOrganization(sessionID: targetSessionID, requestID: requestID)
        case let .retryOrganization(requestID):
            guard let targetSessionID else { return nil }
            return .retryOrganization(sessionID: targetSessionID, requestID: requestID)
        case let .copyChamber(chamber):
            let text = copyText(for: chamber)
            return text.isEmpty ? nil : .copy(text)
        case .generateLinks:
            guard let targetSessionID else { return nil }
            let allowed = selectedRecordIDs.intersection(Set(suggestions.map(\.id)))
            return allowed.isEmpty
                ? nil
                : .generateLinks(sessionID: targetSessionID, selectedRecordIDs: allowed)
        case .openSettings:
            return .openSettings
        case .selectChamber, .reopenLatest, .dismiss:
            return nil
        }
    }

    private func copyText(for chamber: IslandChamber) -> String {
        switch chamber {
        case .original:
            originalText
        case .points:
            numberedPoints.map { "\($0.number). \($0.text)" }.joined(separator: "\n")
        case .connections:
            (knownRecordLinks.map(\.reason) + speculativeConnections.map {
                "推测：\($0.statement)（\($0.detail)）"
            }).joined(separator: "\n")
        }
    }

    private static func mode(for snapshot: AppSnapshot) -> IslandMode {
        if case .organized = snapshot.organizationPhase { return .organized }
        if case .queued = snapshot.organizationPhase { return .organizing }
        if case .organizing = snapshot.organizationPhase { return .organizing }
        if case .failed = snapshot.organizationPhase { return .failed }
        if case .authorizationRequired = snapshot.organizationPhase { return .failed }
        return switch snapshot.status {
        case .idle: .idle
        case .recording: .recording
        case .delivered: .localDelivered
        case .failed, .cancelled: .failed
        case .transcribing, .saving: .organizing
        }
    }

    private static func privacyReceipt(for snapshot: AppSnapshot) -> String {
        guard case let .organized(record) = snapshot.organizationPhase,
              let characterCount = record.sentCharacterCount else { return "" }
        let historyCount = record.selectedRecordIDs.count
        let action = record.providerKind == .local ? "本地处理" : "已发送"
        let historyIDs = record.selectedRecordIDs.map(\.rawValue.uuidString).joined(separator: "、")
        let historyReceipt = historyIDs.isEmpty
            ? "\(historyCount) 条历史摘要"
            : "\(historyCount) 条历史摘要（\(historyIDs)）"
        return "\(action) \(characterCount) 个字符 · \(historyReceipt)"
    }

    private static func status(
        for snapshot: AppSnapshot,
        mode: IslandMode
    ) -> (text: String, tone: Tone, systemImage: String?, accessibilityLabel: String) {
        switch mode {
        case .idle:
            return ("Ready", .neutral, nil, "TSB ready")
        case .recording:
            let text = snapshot.previewText.isEmpty ? "正在录音" : "实时草稿"
            return (text, .neutral, "waveform", "正在录音，\(snapshot.previewText)")
        case .localDelivered:
            let text = snapshot.message ?? snapshot.previewText
            if snapshot.message == localCopySuccessMessage {
                return (text, .success, "checkmark.circle.fill", "本地稿已复制")
            }
            let warning = text.isEmpty ? "需要处理" : text
            return (warning, .warning, "exclamationmark.triangle.fill", warning)
        case .organizing:
            let text = snapshot.status == .delivered ? "本地稿已复制 · 正在整理" : "本地复核中"
            return (text, .neutral, "ellipsis.circle", text)
        case .organized:
            return ("整理完成", .success, "checkmark.circle.fill", "整理完成，原文、要点、关联")
        case .failed:
            let text: String
            if case let .failed(message) = snapshot.organizationPhase {
                text = message
            } else if case .authorizationRequired = snapshot.organizationPhase {
                text = "需要在设置中授权整理"
            } else {
                text = snapshot.message ?? "需要处理"
            }
            return (text, .warning, "exclamationmark.triangle.fill", text)
        }
    }

    private static func controls(
        for snapshot: AppSnapshot,
        mode: IslandMode,
        layout: IslandLayout,
        hasLatestResult: Bool
    ) -> [IslandControl] {
        switch mode {
        case .idle:
            return hasLatestResult
                ? [control(.reopenLatest, "最近结果", "重新打开最近整理结果")]
                : []
        case .recording:
            let localOnlyEnabled = snapshot.organizationPhase == .localOnly
            return [
                control(.stopRecording, "停止", "停止录音"),
                control(
                    .setLocalOnly(!localOnlyEnabled),
                    localOnlyEnabled ? "恢复整理" : "仅本地",
                    localOnlyEnabled ? "本次录音恢复自动整理" : "本次录音仅在本地处理"
                ),
            ]
        case .organizing:
            var result = [control(.dismiss, "收起", "收起灵动岛")]
            if !snapshot.originalText.isEmpty {
                result.insert(control(.copyChamber(.original), "复制原文", "手动复制本地原文"), at: 0)
            }
            if let requestID = snapshot.organizationRequestID {
                result.insert(control(.cancelOrganization(requestID), "停止等待", "停止等待整理结果"), at: 0)
            }
            return result
        case .localDelivered:
            var result = [control(.dismiss, "收起", "收起灵动岛")]
            if !snapshot.originalText.isEmpty {
                result.insert(control(.copyChamber(.original), "复制原文", "手动复制本地原文"), at: 0)
            }
            return result
        case .organized:
            var result: [IslandControl] = []
            if layout == .singleChamber {
                result += IslandChamber.allCases.map {
                    control(.selectChamber($0), $0.title, "显示\($0.title)舱")
                }
            }
            result += IslandChamber.allCases.map {
                control(.copyChamber($0), "复制\($0.title)", "手动复制\($0.title)舱内容")
            }
            if !snapshot.suggestedRecords.isEmpty,
               case let .organized(record) = snapshot.organizationPhase,
               record.provider != "deterministic" {
                result.append(control(.generateLinks, "生成关联", "使用已选择的本地建议生成关联"))
            }
            result.append(control(.dismiss, "收起", "收起灵动岛"))
            return result
        case .failed:
            var result = [control(.dismiss, "收起", "收起灵动岛")]
            if case .authorizationRequired = snapshot.organizationPhase {
                result.insert(control(.openSettings, "打开设置", "打开整理模型设置"), at: 0)
            }
            if !snapshot.originalText.isEmpty {
                result.insert(control(.copyChamber(.original), "复制原文", "手动复制保留的本地原文"), at: 0)
            }
            if let requestID = snapshot.organizationRequestID,
               case .failed = snapshot.organizationPhase {
                result.insert(control(.retryOrganization(requestID), "重试", "重试整理"), at: 0)
            }
            return result
        }
    }

    private static func control(
        _ action: IslandAction,
        _ title: String,
        _ accessibilityLabel: String
    ) -> IslandControl {
        IslandControl(action: action, title: title, accessibilityLabel: accessibilityLabel)
    }

    private static func autoHideDelay(for snapshot: AppSnapshot, mode: IslandMode) -> TimeInterval? {
        if snapshot.status == .cancelled { return 1.2 }
        guard mode == .localDelivered,
              snapshot.message == localCopySuccessMessage,
              snapshot.suggestedRecords.isEmpty,
              !snapshot.secondaryProcessing.contains(where: { item in
                  item.status == .recording
                      || item.status == .transcribing
                      || item.status == .saving
                      || item.organizationPhase == .queued
                      || item.organizationPhase == .organizing
              }) else { return nil }
        return 1.2
    }

    private static let localCopySuccessMessage = "已复制 · 按 ⌘V 粘贴"
}
