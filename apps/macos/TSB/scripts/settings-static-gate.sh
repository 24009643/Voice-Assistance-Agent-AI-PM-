#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tsb_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
project_spec="$tsb_root/project.yml"
app_source="$tsb_root/TSB/App/TSBApp.swift"
delegate_source="$tsb_root/TSB/App/TSBAppDelegate.swift"
menu_source="$tsb_root/TSB/Views/MenuBarView.swift"
settings_source="$tsb_root/TSB/Views/SettingsView.swift"
controller_source="$tsb_root/TSB/App/AppController.swift"

require_text() {
    needle=$1
    file=$2
    if ! rg -F -U -q -- "$needle" "$file"; then
        echo "Missing required source boundary in $file: $needle" >&2
        exit 1
    fi
}

reject_text() {
    needle=$1
    file=$2
    if rg -F -U -q -- "$needle" "$file"; then
        echo "Forbidden source boundary in $file: $needle" >&2
        exit 1
    fi
}

require_text "NSApplicationDelegateAdaptor" "$app_source"
require_text "Settings {" "$app_source"
require_text "SettingsView(" "$app_source"
require_text "MenuBarExtra" "$app_source"
reject_text "WindowGroup" "$app_source"
reject_text "PlaceholderView" "$app_source"
reject_text "onDisappear" "$app_source"

require_text "⌥Space" "$menu_source"
require_text "开始录音" "$menu_source"
require_text "停止录音" "$menu_source"
require_text "取消录音" "$menu_source"
require_text "SettingsLink" "$menu_source"
require_text "退出 TSB" "$menu_source"
require_text "打开麦克风设置" "$menu_source"
require_text "openMicrophoneSettings" "$menu_source"
require_text 'state.snapshot.message == "Microphone access is required to record."' "$menu_source"
reject_text "coordinator" "$menu_source"
reject_text "recorder" "$menu_source"

require_text "AppController" "$delegate_source"
require_text "applicationDidFinishLaunching" "$delegate_source"
require_text "controller.start()" "$delegate_source"
require_text 'TSB_XCTEST_HOST: "1"' "$project_spec"
require_text 'loadPersistedState: ProcessInfo.processInfo.environment["TSB_XCTEST_HOST"] != "1"' "$delegate_source"
if [ -e "$tsb_root/TSB/Views/PlaceholderView.swift" ]; then
    echo "PlaceholderView.swift must remain absent" >&2
    exit 1
fi

for needle in \
    "OpenAI-compatible" \
    "完整 Chat Completions 接口地址" \
    "https://api.example.com/v1/chat/completions" \
    "Model" \
    "SecureField" \
    "已保存配置的 API Key" \
    "未保存" \
    "保存" \
    "取消" \
    "撤销云端授权" \
    "删除配置与密钥" \
    "出站预览" \
    "当前文本" \
    "TSB 历史摘要" \
    "音频" \
    "文件路径" \
    "完整记忆库" \
    "不会覆盖剪贴板" \
    "仅本地" \
    "另行授权" \
    "撤销云端整理授权" \
    "已撤销云端整理授权。" \
    "文本润色授权" \
    "查看润色授权范围" \
    "撤销文本润色授权" \
    "已确认，保存后启用" \
    "音频、录音历史、文件路径和完整记忆库不会发送" \
    "允许发送本次当前转录文本用于校正" \
    "最多会让剪贴板交付额外等待 1.5 秒" \
    "无法撤回已发送的文本" \
    'Button("查看润色授权范围") { showsPolishConsent = true }' \
    '.sheet(isPresented: $showsPolishConsent)'
do
    require_text "$needle" "$settings_source"
done
reject_text "state.snapshot" "$settings_source"
reject_text "previewText" "$settings_source"
api_key_field='SecureField("API Key", text: $model.draft.apiKey)
                    .textContentType(.oneTimeCode)'
require_text "$api_key_field" "$settings_source"
reject_text ".textContentType(.username)" "$settings_source"
reject_text ".textContentType(.password)" "$settings_source"

for needle in \
    "currentTerminology: {" \
    "organizationSettingsStore.load().transcriptTerminology" \
    "polish: { request, localOnly, willDispatch in" \
    "Self.makePolishDispatchSnapshot(" \
    "try await Task.detached(priority: .userInitiated)" \
    "try KeychainSecretStore().load(for: endpoint)" \
    "TranscriptPolishClient(endpoint:" \
    "onRequestPrepared:" \
    "store.updateDelivery(id: sessionID, status: status, receipt: receipt)"
do
    require_text "$needle" "$controller_source"
done

echo "TSB settings static gate passed"
