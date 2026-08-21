import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteService {
    static let shared = PasteService()
    private let pasteboard = NSPasteboard.general

    func copy(_ entry: ClipboardEntry, plainText: Bool = false) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text ?? "", forType: .string)
    }

    func paste(_ entry: ClipboardEntry, plainText: Bool = false, completion: @escaping () -> Void) {
        copy(entry, plainText: plainText)
        guard AXIsProcessTrusted() else { completion(); return }
        completion()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(70)) {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }
}

