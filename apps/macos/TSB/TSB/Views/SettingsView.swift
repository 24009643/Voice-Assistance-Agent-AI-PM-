import SwiftUI

struct SettingsDraft: Equatable {
    var baseURL = ""
    var model = ""
    var apiKey = ""
    var cloudConsent = false
    var allowSelectedHistorySummaries = false
}

enum SettingsOperationStatus: Equatable {
    case saved
    case revoked
    case deleted
    case failed
}

private enum SettingsValidationError: Error {
    case endpointRequired
    case modelRequired
    case cloudConsentRequired
    case apiKeyRequired
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft = SettingsDraft()
    @Published private(set) var hasPersistedAPIKey = false
    @Published private(set) var status: SettingsOperationStatus?
    @Published private(set) var errorMessage: String?

    private let store: OrganizationSettingsStore

    init(store: OrganizationSettingsStore = OrganizationSettingsStore()) {
        self.store = store
        do {
            try reloadPersistedState()
        } catch {
            fail("无法读取已保存的密钥状态。")
        }
    }

    func confirmCloudConsent() {
        draft.cloudConsent = true
    }

    func save() {
        do {
            let endpoint = try validatedEndpoint()
            let enteredKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : draft.apiKey
            if endpoint.isRemote {
                guard draft.cloudConsent else { throw SettingsValidationError.cloudConsentRequired }
                guard enteredKey != nil || hasPersistedAPIKey else { throw SettingsValidationError.apiKeyRequired }
            }
            try store.save(
                OrganizationSettings(
                    endpoint: endpoint,
                    cloudConsentVersion: endpoint.isRemote
                        ? OrganizationSettings.currentCloudConsentVersion
                        : nil,
                    allowUserSelectedHistorySummaries: endpoint.isRemote
                        && draft.allowSelectedHistorySummaries
                ),
                apiKey: enteredKey
            )
            try reloadPersistedState()
            status = .saved
            errorMessage = nil
        } catch {
            fail(message(for: error))
        }
    }

    func cancel() {
        do {
            try reloadPersistedState()
            status = nil
            errorMessage = nil
        } catch {
            fail("无法重新载入已保存的配置。")
        }
    }

    func revokeCloudAccess() {
        do {
            try store.revokeCloudConsent()
            try reloadPersistedState()
            status = .revoked
            errorMessage = nil
        } catch {
            reloadAfterFailedDestructiveAction("撤销失败；未确认密钥已删除。")
        }
    }

    func deleteProfile() {
        do {
            try store.delete()
            try reloadPersistedState()
            status = .deleted
            errorMessage = nil
        } catch {
            reloadAfterFailedDestructiveAction("删除失败；未确认密钥已删除。")
        }
    }

    private func validatedEndpoint() throws -> OrganizationEndpointSettings {
        let rawURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty, let url = URL(string: rawURL) else {
            throw SettingsValidationError.endpointRequired
        }
        let model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw SettingsValidationError.modelRequired }
        return try OrganizationEndpointSettings(baseURL: url, model: model)
    }

    private func reloadPersistedState() throws {
        let settings = store.load()
        draft = SettingsDraft(
            baseURL: settings.endpoint?.baseURL.absoluteString ?? "",
            model: settings.endpoint?.model ?? "",
            cloudConsent: settings.isRemoteDispatchEligible,
            allowSelectedHistorySummaries: settings.canSendUserSelectedHistorySummaries
        )
        hasPersistedAPIKey = try store.hasAPIKey()
    }

    private func reloadAfterFailedDestructiveAction(_ fallback: String) {
        do {
            try reloadPersistedState()
            fail(fallback)
        } catch {
            fail("\(fallback) 同时无法确认当前配置状态。")
        }
    }

    private func fail(_ message: String) {
        status = .failed
        errorMessage = message
    }

    private func message(for error: Error) -> String {
        switch error {
        case SettingsValidationError.endpointRequired:
            "请输入完整的 Base URL。"
        case SettingsValidationError.modelRequired:
            "请输入 Model。"
        case SettingsValidationError.cloudConsentRequired:
            "远程端点需先查看并确认云端授权范围。"
        case SettingsValidationError.apiKeyRequired:
            "远程端点需输入 API Key；已有密钥时留空会继续保留。"
        case OrganizationEndpointSettingsError.insecureEndpoint:
            "远程端点必须使用 HTTPS；只有本机回环地址可使用 HTTP。"
        default:
            "保存失败；旧配置和旧密钥未被标记为已替换。"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var showsConsent = false
    @State private var destructiveAction: DestructiveAction?

    var body: some View {
        Form {
            Section("整理模型") {
                LabeledContent("Provider", value: "OpenAI-compatible")
                TextField("Base URL", text: $model.draft.baseURL)
                    .textContentType(.URL)
                TextField("Model", text: $model.draft.model)
                SecureField("API Key", text: $model.draft.apiKey)
                    .accessibilityHint("密钥只写入 Keychain，界面不会回读或显示真实内容。")
                LabeledContent("API Key", value: model.hasPersistedAPIKey ? "已保存（不会显示）" : "未保存")
            }

            Section("云端授权") {
                LabeledContent("当前状态", value: model.draft.cloudConsent ? "已确认，保存后自动整理" : "未授权")
                Button("查看授权范围") {
                    showsConsent = true
                }
                Toggle(
                    "另行授权：发送我本次明确选择的 TSB 历史摘要",
                    isOn: $model.draft.allowSelectedHistorySummaries
                )
                .disabled(!model.draft.cloudConsent)
            }

            Section("出站预览") {
                Text("允许：当前文本。只有开启另行授权，并在单次操作中明确选择后，才发送对应的 TSB 历史摘要。")
                Text("禁止：音频、文件路径、完整记忆库。")
                Text("整理结果不会覆盖剪贴板；每次录音仍可选择“仅本地”。")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityLabel("设置错误：\(errorMessage)")
            } else if let status = model.status {
                Text(successMessage(for: status))
                    .foregroundStyle(.green)
            }

            HStack {
                Button("保存", action: model.save)
                    .keyboardShortcut(.defaultAction)
                Button("取消", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("撤销云端授权", role: .destructive) {
                    destructiveAction = .revoke
                }
                Button("删除配置与密钥", role: .destructive) {
                    destructiveAction = .delete
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 600)
        .sheet(isPresented: $showsConsent) {
            consentSheet
        }
        .confirmationDialog(
            "确认操作",
            isPresented: Binding(
                get: { destructiveAction != nil },
                set: { if !$0 { destructiveAction = nil } }
            )
        ) {
            if destructiveAction == .revoke {
                Button("撤销云端授权并删除密钥", role: .destructive) {
                    model.revokeCloudAccess()
                    destructiveAction = nil
                }
            } else if destructiveAction == .delete {
                Button("删除配置与密钥", role: .destructive) {
                    model.deleteProfile()
                    destructiveAction = nil
                }
            }
        }
    }

    private var consentSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("云端整理授权")
                .font(.title2.bold())
            Text("允许发送当前文本。只有开启另行授权，并在每次明确选择后，才发送对应的 TSB 历史摘要。")
            Text("不会发送音频、文件路径或完整记忆库。")
            Text("整理结果不会覆盖剪贴板。你可以为单次录音选择“仅本地”，也可以随时撤销云端授权。")
            HStack {
                Spacer()
                Button("暂不授权") {
                    showsConsent = false
                }
                Button("同意并启用") {
                    model.confirmCloudConsent()
                    showsConsent = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func successMessage(for status: SettingsOperationStatus) -> String {
        switch status {
        case .saved: "已保存。"
        case .revoked: "已撤销云端授权并删除密钥。"
        case .deleted: "已删除配置与密钥。"
        case .failed: ""
        }
    }
}

private enum DestructiveAction {
    case revoke
    case delete
}
