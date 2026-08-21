import AppKit
import KeyboardShortcuts
import SwiftUI

struct PicoSettingsView: View {
    @EnvironmentObject private var state: PicoAppState
    @State private var selected = "常规"
    private let pages = ["常规", "快捷键", "隐私与忽略", "AI 模型", "历史导入", "更新与关于"]
    var body: some View { NavigationSplitView { List(pages, id: \.self, selection: $selected) { Text($0) }.navigationTitle("Pico 设置") } detail: { Form { switch selected { case "快捷键": ShortcutSettings(); case "隐私与忽略": PrivacySettings(state: state); case "AI 模型": AIModelSettings(); default: GeneralSettings(state: state) } }.formStyle(.grouped).frame(minWidth: 560) }.frame(width: 780, height: 500).preferredColorScheme(.dark) }
}

private struct GeneralSettings: View { @ObservedObject var state: PicoAppState; var body: some View { Section("启动与历史") { Toggle("登录时启动 Pico", isOn: .constant(true)); Picker("历史保留", selection: .constant(HistoryRetentionPolicy.month)) { Text("一周").tag(HistoryRetentionPolicy.week); Text("一个月").tag(HistoryRetentionPolicy.month); Text("三个月").tag(HistoryRetentionPolicy.threeMonths); Text("永久").tag(HistoryRetentionPolicy.forever) }; Toggle("本地图片 OCR", isOn: .constant(true)) } } }
private struct ShortcutSettings: View { var body: some View { Section("快捷键") { KeyboardShortcuts.Recorder("打开剪贴板历史", name: .togglePicoPanel); KeyboardShortcuts.Recorder("翻译当前剪贴板", name: .translateClipboard); Text("面板内：← → 切换，Return 粘贴，Shift + Return 纯文本，T 翻译，Esc 关闭").font(.caption).foregroundStyle(.secondary) } } }
private struct PrivacySettings: View { @ObservedObject var state: PicoAppState; var body: some View { Section("监听") { Toggle("剪贴板监听", isOn: Binding(get: { !state.isPaused }, set: { _ in state.togglePause() })); Button("打开辅助功能设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) } }; Section("说明") { Text("Pico 的历史只保存在本机；可在后续版本中添加忽略应用列表。") } } }
private struct AIModelSettings: View { @State private var baseURL = "https://api.openai.com/v1"; @State private var modelID = "gpt-4.1-mini"; @State private var key = ""; var body: some View { Section("OpenAI-compatible 模型") { TextField("Base URL", text: $baseURL); SecureField("API Key（存储在 Keychain）", text: $key); TextField("模型 ID", text: $modelID); Button("测试 Chat") {}; Text("/models 仅作为可选辅助；无法访问时可以直接填写模型 ID。\n翻译主动触发：面板内 T，或全局 ⌥ ⇧ T。").font(.caption).foregroundStyle(.secondary) } } }

