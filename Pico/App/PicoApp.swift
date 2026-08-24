import AppKit
import KeyboardShortcuts
import Sparkle
import ServiceManagement
import SwiftUI
import SwiftData

extension KeyboardShortcuts.Name {
    static let togglePicoPanel = Self("togglePicoPanel", default: .init(.v, modifiers: [.command, .shift]))
    static let translateClipboard = Self("translateClipboard", default: .init(.t, modifiers: [.option, .shift]))
}

@MainActor
final class PicoAppState: ObservableObject {
    /// SwiftUI 可能多次实例化 App struct（MenuBarExtra scene 特性），
    //  导致 @StateObject autoclosure 跑两次 → 两个 PicoAppState：
    //  面板 UI 渲染实例 A，键盘 monitor 操作实例 B —— 高亮永远不动（实测踩坑）。
    //  必须全局唯一。
    static let shared = PicoAppState()

    let repository = ClipboardRepository.shared
    lazy var monitor = ClipboardMonitor(repository: repository)
    lazy var keyHandler = PicoKeyHandler(state: self)

    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var selectedLayout = "横条"
    @Published var isPaused = false
    @Published var selection: PicoSelection = .all

    init() { monitor.start(); keyHandler.install() }

    enum PicoSelection: Hashable {
        case all
        case favorites
        case group(UUID)
    }

    var scopedEntries: [ClipboardEntry] {
        switch selection {
        case .all: return repository.entries
        case .favorites: return repository.favoriteEntries
        case .group(let id): return repository.entries(inGroupID: id)
        }
    }

    var filteredEntries: [ClipboardEntry] {
        let scoped = scopedEntries
        guard !query.isEmpty else { return scoped }
        let q = query.localizedLowercase
        return scoped.filter {
            ($0.text?.localizedLowercase.contains(q) ?? false)
            || ($0.ocrText?.localizedLowercase.contains(q) ?? false)
            || ($0.sourceAppName?.localizedLowercase.contains(q) ?? false)
        }
    }

    var selectedEntry: ClipboardEntry? {
        if let selectedID, let item = filteredEntries.first(where: { $0.id == selectedID }) { return item }
        return filteredEntries.first
    }

    /// 当前布局的列数（和 entryGrid 中保持一致）
    var gridColumnCount: Int {
        switch selectedLayout {
        case "紧凑": return 5
        case "纵向": return 2
        default: return 4
        }
    }

    /// ←/→ 同行水平移动；
    /// 末尾行不足 cols 时：按 → 静止在原位（不再越界多跳一行），按 ← 跨到上一行末尾
    func selectHorizontal(_ offset: Int) {
        let items = filteredEntries
        guard !items.isEmpty else { return }
        let cols = max(1, gridColumnCount)
        let total = items.count
        let currentIndex = items.firstIndex { $0.id == selectedEntry?.id } ?? 0
        let col = currentIndex % cols
        let row = currentIndex / cols
        let targetCol = col + offset
        if offset < 0 {
            if targetCol >= 0 {
                selectedID = items[row * cols + targetCol].id
            } else if row > 0 {
                selectedID = items[(row - 1) * cols + cols - 1].id
            }
            return
        }
        if targetCol < cols {
            let idx = row * cols + targetCol
            if idx < total { selectedID = items[idx].id }
        } else {
            let nextRowStart = (row + 1) * cols
            if nextRowStart < total { selectedID = items[nextRowStart].id }
        }
    }

    /// ↑/↓ 同列垂直移动；越界则停在边缘
    func selectVertical(_ offset: Int) {
        let items = filteredEntries
        guard !items.isEmpty else { return }
        let cols = max(1, gridColumnCount)
        let total = items.count
        let currentIndex = items.firstIndex { $0.id == selectedEntry?.id } ?? 0
        let col = currentIndex % cols
        var row = currentIndex / cols
        row += offset
        row = max(0, min(row, (total - 1) / cols))
        let target = row * cols + col
        selectedID = items[min(target, total - 1)].id
    }

    func togglePause() { isPaused.toggle(); monitor.setPaused(isPaused) }

    /// 回车粘贴：面板关闭 + 内容粘回原输入框（PasteService 负责发 ⌘V）
    func pasteSelected(plainText: Bool = false) {
        guard let entry = selectedEntry else { return }
        let target = PicoPanelController.shared.hide()
        PasteService.shared.paste(entry, plainText: plainText, targetApplication: target)
    }

    func translateSelected() {
        if let entry = selectedEntry { NotificationCenter.default.post(name: .picoTranslateEntry, object: entry) }
    }
}

@MainActor
final class PicoKeyHandler {
    private weak var state: PicoAppState?
    nonisolated(unsafe) private var monitorToken: Any?
    init(state: PicoAppState) { self.state = state }

    func install() {
        // PicoAppState 可能因 SwiftUI App 重建被创建多次；monitor 只装一份，重复安装会泄漏旧 monitor
        guard monitorToken == nil else { return }
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state else { return event }
            // 只接管 Pico 自己的面板上的按键
            guard let window = NSApp.keyWindow, window is PicoPanel else { return event }

            // 只在真实文本控件编辑时让系统处理按键（SwiftUI view 会响应 hasMarkedText，不能用它判断）
            let fr = window.firstResponder
            let isEditingText = (fr is NSText) || (fr is NSTextField) || (fr is NSSearchField)

            let key = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""
            if key == 53 /* Esc */ {
                if isEditingText {
                    window.makeFirstResponder(nil)
                } else {
                    PicoPanelController.shared.hide()
                    return nil
                }
                return event
            }
            if isEditingText { return event }
            switch key {
            case 123: state.selectHorizontal(-1); return nil   // ←
            case 124: state.selectHorizontal(1); return nil    // →
            case 125: state.selectVertical(1); return nil      // ↓
            case 126: state.selectVertical(-1); return nil     // ↑
            case 36, 76: state.pasteSelected(); return nil     // Return / 小键盘回车
            default:
                if chars.lowercased() == "t" {
                    state.translateSelected(); return nil
                }
                return event
            }
        }
    }

    func uninstall() {
        if let token = monitorToken { NSEvent.removeMonitor(token) }
        monitorToken = nil
    }
}

@MainActor
final class PicoAppDelegate: NSObject, NSApplicationDelegate {
    var state: PicoAppState?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：Xcode 调试残留的旧实例会抢占全局热键（RegisterEventHotKey 先到先得），
        // 导致新实例按 ⌘⇧V 完全没反应。发现已有实例在跑时，激活旧实例并退出自己。
        let myPID = ProcessInfo.processInfo.processIdentifier
        let otherPicos = NSRunningApplication.runningApplications(withBundleIdentifier: "com.linjunc.pico")
            .filter { $0.processIdentifier != myPID }
        if let existing = otherPicos.first {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = makeBrandIcon(size: 512)
        installStatusItem()
        KeyboardShortcuts.onKeyDown(for: .togglePicoPanel) { [weak self] in Task { @MainActor in self?.togglePanel() } }
        KeyboardShortcuts.onKeyDown(for: .translateClipboard) { [weak self] in Task { @MainActor in self?.translateCurrentClipboard() } }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = makeBrandIcon(size: 18)
        item.button?.image = icon
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func makeBrandIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: size - 2, height: size - 2)
        NSColor.systemCyan.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.24, yRadius: size * 0.24).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.62, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.03, alpha: 1),
            .paragraphStyle: paragraph
        ]
        ("P" as NSString).draw(in: NSRect(x: 0, y: size * 0.13, width: size, height: size * 0.7), withAttributes: attributes)
        image.unlockFocus()
        return image
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        togglePanel()
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: PicoPanelController.shared.isVisible ? "关闭面板" : "打开剪贴板", action: #selector(togglePanelFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: state?.isPaused == true ? "恢复监听" : "暂停监听", action: #selector(togglePauseFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Pico", action: #selector(quitFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        statusItem?.popUpMenu(menu)
    }

    @objc private func togglePanelFromMenu() { togglePanel() }
    @objc private func openSettingsFromMenu() { toggleSettings() }
    @objc private func togglePauseFromMenu() { state?.togglePause() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    func togglePanel() {
        guard let state else { return }
        PicoPanelController.shared.toggle(content: {
            PicoMainView()
                .environmentObject(state)
        })
    }

    func toggleSettings() {
        guard let state else { return }
        PicoSettingsWindowController.shared.toggle(state: state)
    }

    func translateCurrentClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        // 全局翻译时结果岛显示在面板里：面板没开的话先打开，否则用户看不到翻译结果
        if !PicoPanelController.shared.isVisible {
            togglePanel()
        }
        if let entry = state?.repository.capture(text: text, sourceAppName: "系统剪贴板") {
            TranslationCoordinator.shared.translate(entry: entry)
        }
    }
}

@main
struct PicoApp: App {
    @NSApplicationDelegateAdaptor(PicoAppDelegate.self) private var delegate
    @StateObject private var state = PicoAppState.shared

    init() {
        // PicoMainView 不在 WindowGroup 里（面板由 PicoPanelController 管理），
        // 在这里一次性注入 state，确保菜单栏操作始终可用。
        delegate.state = state
    }

    var body: some Scene {
        // 状态栏按钮由 AppKit 管理：左键直接打开面板，不再弹出下拉菜单。
        Settings { EmptyView() }
    }
}

@MainActor
final class PicoLaunchAtLogin {
    static let shared = PicoLaunchAtLogin()

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("[Pico] launch at login update failed: %@", error.localizedDescription)
        }
    }
}

// MARK: - Sparkle 控制器封装

@MainActor
final class PicoUpdaterController: ObservableObject {
    static let shared = PicoUpdaterController()
    private var controller: SPUStandardUpdaterController?

    /// 惰性 bootstrap：绝不在 app 启动路径上调用 ——
    /// SPUStandardUpdaterController(startingUpdater: true) 会在主线程同步等待 XPC，
    /// 卡死整个 app（面板/热键全废）。只在用户点「检查更新」时才初始化。
    private func bootstrapIfNeeded() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        // SUPublicEDKey 还是占位符时 Sparkle 会直接报 fatal 错误，先拦截给出友好提示
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           key.isEmpty || key.contains("REPLACE_WITH") {
            let alert = NSAlert()
            alert.messageText = "更新功能尚未配置"
            alert.informativeText = "发布前需要在 Info.plist 中配置真实的 Sparkle EdDSA 公钥（SUPublicEDKey）和更新源（SUFeedURL）。"
            alert.runModal()
            return
        }
        bootstrapIfNeeded()
        controller?.updater.checkForUpdates()
    }
}
