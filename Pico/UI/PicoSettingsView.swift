import AppKit
import KeyboardShortcuts
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct PicoSettingsView: View {
    @EnvironmentObject private var state: PicoAppState
    @State private var selected = "常规"

    private let pages = ["常规", "快捷键", "隐私与忽略", "AI 模型", "历史导入", "更新与关于"]

    var body: some View {
        NavigationSplitView {
            List(pages, id: \.self, selection: $selected) { Text($0) }
                .navigationTitle("Pico 设置")
        } detail: {
            // Settings scene 自带原生标题栏和红绿灯关闭按钮，不需要自定义关闭栏
            Form {
                switch selected {
                case "快捷键":          ShortcutSettings()
                case "隐私与忽略":      PrivacySettings(state: state)
                case "AI 模型":         AIModelSettings()
                case "历史导入":        ImportSettings(state: state)
                case "更新与关于":      UpdateAboutSettings()
                default:                GeneralSettings(state: state)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 560)
        }
        .frame(minWidth: 760, minHeight: 500)
        .preferredColorScheme(.dark)
        // 注意：不要在 onAppear 里 bootstrap Sparkle —— SPUStandardUpdaterController 的
        // startingUpdater 会同步等待 XPC，在主线程上把整个 app 卡死（主队列饿死，面板全废）。
        // 检查更新时才惰性初始化。
    }
}

// MARK: - 各页

private struct GeneralSettings: View {
    @ObservedObject var state: PicoAppState
    @State private var launchAtLogin = PicoLaunchAtLogin.shared.isEnabled
    var body: some View {
        Section("启动与历史") {
            Toggle("登录时启动 Pico", isOn: Binding(
                get: { launchAtLogin },
                set: {
                    launchAtLogin = $0
                    PicoLaunchAtLogin.shared.setEnabled($0)
                }
            ))
            Text("Pico 将以菜单栏应用运行，不占用 Dock。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("历史保留", selection: .constant(HistoryRetentionPolicy.month)) {
                Text("一周").tag(HistoryRetentionPolicy.week)
                Text("一个月").tag(HistoryRetentionPolicy.month)
                Text("三个月").tag(HistoryRetentionPolicy.threeMonths)
                Text("永久").tag(HistoryRetentionPolicy.forever)
            }
            Toggle("本地图片 OCR", isOn: .constant(true))
        }
        Section("面板位置") {
            Picker("显示位置", selection: Binding(
                get: { PicoPanelController.shared.position.rawValue },
                set: { rawValue in
                    guard let position = PicoPanelController.PanelPosition(rawValue: rawValue) else { return }
                    PicoPanelController.shared.position = position
                }
            )) {
                ForEach(PicoPanelController.PanelPosition.allCases, id: \.rawValue) { position in
                    Text(position.rawValue).tag(position.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("快捷键打开时，面板会显示在所选区域；面板也可以直接拖动。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Section("全局快捷键") {
            KeyboardShortcuts.Recorder("打开剪贴板历史", name: .togglePicoPanel)
            KeyboardShortcuts.Recorder("翻译当前剪贴板", name: .translateClipboard)
            Text("全局快捷键可在 macOS 系统设置 › 键盘 › 快捷键 中重置。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("面板内") {
            Text("↑ / ↓  上下移动选中条目\n← / →  同行左右移动条目\nReturn  粘贴选中条目并关闭面板\nT  翻译选中条目\nEsc  关闭面板 / 退出搜索编辑")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrivacySettings: View {
    @ObservedObject var state: PicoAppState
    var body: some View {
        Section("监听") {
            Toggle("剪贴板监听", isOn: Binding(get: { !state.isPaused }, set: { _ in state.togglePause() }))
            Button("打开辅助功能设置") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        Section("说明") {
            Text("Pico 的历史只保存在本机；可在后续版本中添加忽略应用列表。")
        }
    }
}

private struct AIModelSettings: View {
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var modelID = "gpt-4.1-mini"
    @State private var key = ""
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Section("OpenAI-compatible 模型") {
            TextField("Base URL", text: $baseURL)
            SecureField("API Key（存储在 Keychain）", text: $key)
            TextField("模型 ID", text: $modelID)
            Button(testing ? "测试中…" : "测试 Chat") {
                Task { await runTest() }
            }
            .disabled(testing)
            if let testResult {
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
            Text("/models 仅作为可选辅助；无法访问时可以直接填写模型 ID。\n翻译主动触发：面板内 T，或全局 ⌥ ⇧ T。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        let configuration = AIModelConfiguration(name: "测试", baseURL: baseURL, modelID: modelID)
        guard !key.isEmpty else { testResult = "请先填写 API Key"; return }
        do {
            let reply = try await OpenAICompatibleClient().chat(configuration: configuration, apiKey: key, prompt: "ping")
            testResult = "Chat 接口连接成功：\(reply.prefix(60))"
        } catch {
            testResult = "失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 历史导入

private struct ImportSettings: View {
    @ObservedObject var state: PicoAppState
    @State private var status: ImportStatus = .idle

    enum ImportStatus {
        case idle
        case preview(ImportPreview)
        case importing
        case done(inserted: Int)
        case failed(String)
    }

    var body: some View {
        Section("支持的来源") {
            ForEach(ClipboardImportSource.allCases, id: \.rawValue) { source in
                HStack {
                    Text(source.rawValue)
                    Spacer()
                    Button("选择文件…") { importFrom(source: source) }
                }
            }
        }
        Section("结果") {
            switch status {
            case .idle:
                Text("尚未导入")
                    .font(.caption).foregroundStyle(.secondary)
            case .preview(let p):
                VStack(alignment: .leading, spacing: 6) {
                    Text("解析到 \(p.items.count) 条，重复 \(p.duplicateCount) 条")
                    if !p.failures.isEmpty {
                        ForEach(p.failures, id: \.self) { Text($0).foregroundStyle(.orange).font(.caption) }
                    }
                    HStack {
                        Button("开始导入") {
                            commit(p)
                        }
                        Button("取消") { status = .idle }
                    }
                }
            case .importing:
                ProgressView("正在导入…")
            case .done(let n):
                Text("完成 · 共导入 \(n) 条").foregroundStyle(.cyan)
                Button("清除结果") { status = .idle }
            case .failed(let msg):
                Text(msg).foregroundStyle(.red)
                Button("重试") { status = .idle }
            }
        }
    }

    private func importFrom(source: ClipboardImportSource) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        if source == .pasteNow {
            panel.allowedContentTypes = [UTType.json]
        } else {
            panel.allowedContentTypes = [UTType.database]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runPreview(source: source, fileURL: url)
    }

    private func runPreview(source: ClipboardImportSource, fileURL: URL) {
        let existingHashes = Set(state.repository.entries.map(\.contentHash))
        let importer: ClipboardImporter
        switch source {
        case .pasteNow: importer = PasteNowJSONImporter()
        default: importer = LegacyDatabaseImporter(source: source)
        }
        Task.detached {
            do {
                let preview = try importer.preview(fileURL: fileURL, existingHashes: existingHashes)
                await MainActor.run { status = .preview(preview) }
            } catch {
                await MainActor.run { status = .failed(error.localizedDescription) }
            }
        }
    }

    private func commit(_ preview: ImportPreview) {
        status = .importing
        let candidates = preview.items.map {
            ImportCandidate(text: $0.text, sourceAppName: "历史导入·\(preview.source.rawValue)", type: $0.type)
        }
        Task {
            let n = await MainActor.run { state.repository.bulkCapture(candidates) }
            status = .done(inserted: n)
        }
    }
}

// MARK: - 更新与关于

private struct UpdateAboutSettings: View {
    @State private var checking = false
    @State private var lastResult: String?

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        Section("软件更新") {
            HStack {
                Text("当前版本")
                Spacer()
                Text("Pico \(version) (\(build))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(checking ? "检查中…" : "检查更新") {
                checking = true
                lastResult = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    PicoUpdaterController.shared.checkForUpdates()
                    checking = false
                    lastResult = "已在后台请求更新检查；通过 Sparkle 弹窗反馈结果。"
                }
            }
            .disabled(checking)
            Text("当前签名公钥为占位值；正式发布时需替换 `Info.plist` 中的 `SUPublicEDKey`。")
                .font(.caption).foregroundStyle(.secondary)
            if let lastResult { Text(lastResult).font(.caption).foregroundStyle(.secondary) }
        }
        Section("关于 Pico") {
            LabeledContent("名称", value: "Pico")
            LabeledContent("定位", value: "暗黑冰蓝风格的 macOS 本地剪贴板工具")
            LabeledContent("主页", value: "https://github.com/linjunc/pico")
            Text("Pico 的历史只保存在本机；模型 API Key 写入 macOS Keychain。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
