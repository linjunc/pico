import AppKit
import ApplicationServices
import Foundation

extension Notification.Name {
    /// 辅助功能未授权，粘贴无法模拟 ⌘V
    static let picoPasteNeedsAccessibility = Notification.Name("picoPasteNeedsAccessibility")
    static let picoPasteFailed = Notification.Name("picoPasteFailed")
}

@MainActor
final class PasteService {
    static let shared = PasteService()
    private let pasteboard = NSPasteboard.general

    func copy(_ entry: ClipboardEntry, plainText: Bool = false) {
        pasteboard.clearContents()
        if let text = entry.text {
            pasteboard.setString(text, forType: .string)
        } else if let data = entry.imageData {
            pasteboard.setData(data, forType: .png)
        }
    }

    /// 粘贴时序：面板 hide（调用方完成）→ previousActiveApp.activate() 归还焦点（异步生效）
    /// → 轮询等目标 app 真正成为 frontmost → 再发 ⌘V。
    /// activate 是异步的，固定延时不可靠（这正是之前粘贴失败的原因之一）。
    func paste(_ entry: ClipboardEntry, plainText: Bool = false, targetApplication: NSRunningApplication?) {
        copy(entry, plainText: plainText)
        guard AXIsProcessTrusted() else {
            NotificationCenter.default.post(name: .picoPasteNeedsAccessibility, object: nil)
            return
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            NotificationCenter.default.post(name: .picoPasteFailed, object: nil)
            return
        }
        targetApplication.activate(options: [.activateIgnoringOtherApps])
        waitForFocusReturn(targetPID: targetApplication.processIdentifier,
                           deadline: Date().addingTimeInterval(1.5), attempts: 0)
    }

    private func waitForFocusReturn(targetPID: pid_t, deadline: Date, attempts: Int) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == targetPID {
            // 目标 app 已是 frontmost，再等一小拍让它的 firstResponder 稳定。
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
                self?.postCommandV()
            }
            return
        }
        if Date() < deadline, attempts < 40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in
                self?.waitForFocusReturn(targetPID: targetPID, deadline: deadline, attempts: attempts + 1)
            }
        } else {
            // 绝不把 ⌘V 发给 Pico 或未知窗口；宁可提示用户重试。
            NotificationCenter.default.post(name: .picoPasteFailed, object: nil)
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
