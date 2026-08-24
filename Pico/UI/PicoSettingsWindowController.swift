import AppKit
import SwiftUI

/// 独立设置窗口控制器。
///
/// 为什么不用 SwiftUI 的 Settings scene：
/// 1. app 只有 MenuBarExtra（无主窗口 scene）时，macOS 会在启动时**自动弹出** Settings 窗口；
/// 2. 之前 Settings 的 onAppear 里 bootstrap Sparkle，把主线程同步卡死（XPC 等待），
///    导致整个 app（热键/面板/交互）全部无响应 —— 这是「面板打不开」的真正根因。
/// 自管理 NSWindow 完全可控：用户点「设置…」才创建/显示，带原生红绿灯，可自由缩放。
@MainActor
final class PicoSettingsWindowController {
    static let shared = PicoSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func toggle(state: PicoAppState) {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show(state: state)
    }

    func show(state: PicoAppState) {
        if let window {
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true) // 设置是用户主动打开的常规窗口，正常抢焦点
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Pico 设置"
        w.level = .floating
        w.isReleasedWhenClosed = false // 复用，点红绿灯只是 orderOut
        w.setContentSize(NSSize(width: 860, height: 640))
        w.center()
        w.contentView = NSHostingView(rootView:
            PicoSettingsView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        )
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.orderFrontRegardless()
        w.makeKeyAndOrderFront(nil)
    }
}
