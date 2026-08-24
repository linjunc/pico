import AppKit
import SwiftUI

/// 剪贴板快捷面板：即选即用即关闭。
/// 参考 Clipaste 的成熟方案：
/// - `.nonactivatingPanel`：面板可以接收键盘输入（搜索框能打字、方向键能选中），
///   但不会抢走目标 App 的 app 级焦点 —— 这是回车粘贴能命中原输入框的关键。
/// - 永远不调用 NSApp.activate —— 面板只做窗口级 makeKey，不动菜单栏归属。
/// - 全局鼠标监听：点面板外部任意位置即隐藏。
@MainActor
final class PicoPanelController {
    static let shared = PicoPanelController()

    private var panel: PicoPanel?
    private var outsideClickMonitor: Any?
    /// 记录呼出面板前正在活跃的 App（粘贴目标），需要时归还焦点
    private var previousActiveApp: NSRunningApplication?
    private(set) var isVisible: Bool = false
    private let positionKey = "pico.panel.position"

    enum PanelPosition: String, CaseIterable {
        case top = "上方"
        case center = "中间"
        case bottom = "下方"
    }

    var position: PanelPosition {
        get { PanelPosition(rawValue: UserDefaults.standard.string(forKey: positionKey) ?? "中间") ?? .center }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: positionKey) }
    }

    private init() {}

    private func ensurePanel(content: some View) -> PicoPanel {
        if let panel { return panel }
        let p = PicoPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        // 由 SwiftUI 内容提供柔和阴影，避免 NSPanel 默认阴影在圆角外形成硬边。
        p.hasShadow = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.level = .floating
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isMovable = true
        p.isMovableByWindowBackground = true
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [] // 禁止 SwiftUI 内容反向撑大面板，由 setFrame 控制
        p.contentViewController = host
        panel = p
        return p
    }

    // MARK: - 显示 / 隐藏

    func toggle(content: () -> some View) {
        if isVisible {
            hide()
        } else {
            show(content: content())
        }
    }

    func show(content: some View) {
        let panel = ensurePanel(content: content)
        guard !isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        // 0. 在 makeKey 之前记录当前活跃 App（这就是粘贴目标）
        previousActiveApp = NSWorkspace.shared.frontmostApplication

        // 1. 计算面板位置：跟随鼠标所在屏幕，屏幕内居中；小屏自适应缩小
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.visibleFrame
        // 剪贴板面板保持原来的宽屏浏览密度，小屏才按可视区域收缩。
        let width = min(980, max(720, sf.width - 48))
        let height = min(500, max(360, sf.height - 48))
        let x = sf.midX - width / 2
        let y: CGFloat = {
            switch position {
            case .top: return sf.maxY - height - 42
            case .bottom: return sf.minY + 42
            case .center: return sf.midY - height / 2
            }
        }()
        let clampedX = max(sf.minX + 24, min(x, sf.maxX - width - 24))
        let clampedY = max(sf.minY + 24, min(y, sf.maxY - height - 24))
        panel.setFrame(NSRect(x: clampedX, y: clampedY, width: width, height: height), display: true)

        // 2. 显示。键盘事件只路由给 active app 的 key window —— accessory app 若从未
        // activate，nonactivating panel 拿不到键盘（实测 monitor 收不到任何 keyDown）。
        // Alfred / Raycast 的做法：呼出时短暂 activate（粘贴路径会归还焦点，不影响回车粘贴）。
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil) // 阻止 SwiftUI 自动聚焦搜索框
        // activate 是异步的：立即检查 isKeyWindow 会是 false（实测）。
        // 重试直到面板真正拿到 key status（键盘事件路由的前提）。
        makeKeyWithRetry(panel, remaining: 10)
        // SwiftUI 的布局是异步的，可能稍后把焦点塞给搜索框 —— 隔一拍再清一次保险
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak panel] in
            panel?.makeFirstResponder(nil)
        }
        // SwiftUI hosting 内容的 intrinsic size 会异步把面板尺寸反向撑掉（实测被撑成 900x708），
        // 下一 runloop tick 再强制改回目标尺寸
        DispatchQueue.main.async { [weak panel] in
            panel?.setFrame(NSRect(x: clampedX, y: clampedY, width: width, height: height), display: true)
        }
        isVisible = true
        installOutsideClickMonitor()
    }

    /// 每隔 50ms 重试 makeKey，直到 isKeyWindow == true（activate 异步生效前的窗口拿不到 key）
    private func makeKeyWithRetry(_ panel: PicoPanel, remaining: Int) {
        if panel.isKeyWindow { return }
        if remaining <= 0 {
            NSLog("[Pico] WARN: panel failed to become key window — 面板将无法接收键盘")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            self.makeKeyWithRetry(panel, remaining: remaining - 1)
        }
    }

    /// - Parameter restoreFocus: 仅在「粘贴 / Esc / 关闭按钮」路径传 true（精准归还焦点）。
    ///   点击外部关闭必须 false：用户点的是另一个 app，那个 app 自己会 activate，
    ///   此时若再 activate 之前的 app 会出现焦点竞争。
    @discardableResult
    func hide(restoreFocus: Bool = true) -> NSRunningApplication? {
        guard let panel else { return nil }
        removeOutsideClickMonitor()
        panel.orderOut(nil)
        isVisible = false
        let target = previousActiveApp
        if restoreFocus, let target, !target.isTerminated {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        previousActiveApp = nil
        return target
    }

    // MARK: - 外部点击自动关闭

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                // 用户点的是面板外的其他 app/区域：让点击自然落到目标上，不归还旧焦点
                self?.hide(restoreFocus: false)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) }
    }
}

/// 强制 `.nonactivatingPanel` 的 NSPanel：
/// 可收键盘但不激活 App —— 目标 App（微信/Safari 等）保持焦点，⌘V 才能粘回原输入框。
final class PicoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask.union(.nonactivatingPanel),
            backing: backing,
            defer: flag
        )
    }
}
