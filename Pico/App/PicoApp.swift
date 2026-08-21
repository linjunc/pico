import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePicoPanel = Self("togglePicoPanel", default: .init(.v, modifiers: [.command, .shift]))
    static let translateClipboard = Self("translateClipboard", default: .init(.t, modifiers: [.option, .shift]))
}

@MainActor
final class PicoAppState: ObservableObject {
    let repository = ClipboardRepository.shared
    lazy var monitor = ClipboardMonitor(repository: repository)
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var selectedLayout = "横向"
    @Published var isPaused = false
    init() { monitor.start() }
    var filteredEntries: [ClipboardEntry] { guard !query.isEmpty else { return repository.entries }; let q = query.localizedLowercase; return repository.entries.filter { ($0.text?.localizedLowercase.contains(q) ?? false) || ($0.ocrText?.localizedLowercase.contains(q) ?? false) || ($0.sourceAppName?.localizedLowercase.contains(q) ?? false) } }
    var selectedEntry: ClipboardEntry? { if let selectedID, let item = filteredEntries.first(where: { $0.id == selectedID }) { return item }; return filteredEntries.first }
    func selectRelative(_ offset: Int) { let items = filteredEntries; guard !items.isEmpty else { return }; let index = items.firstIndex { $0.id == selectedEntry?.id } ?? 0; selectedID = items[(index + offset + items.count) % items.count].id }
    func togglePause() { isPaused.toggle(); monitor.setPaused(isPaused) }
}

@MainActor
final class PicoAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: PicoAppState?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        KeyboardShortcuts.onKeyDown(for: .togglePicoPanel) { [weak self] in Task { @MainActor in self?.togglePanel() } }
        KeyboardShortcuts.onKeyDown(for: .translateClipboard) { [weak self] in Task { @MainActor in self?.translateCurrentClipboard() } }
    }
    func togglePanel() { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.title == "Pico" })?.makeKeyAndOrderFront(nil) }
    func translateCurrentClipboard() { guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }; if let entry = state?.repository.capture(text: text, sourceAppName: "系统剪贴板") { TranslationCoordinator.shared.translate(entry: entry) } }
}

@main
struct PicoApp: App {
    @NSApplicationDelegateAdaptor(PicoAppDelegate.self) private var delegate
    @StateObject private var state = PicoAppState()
    var body: some Scene {
        WindowGroup("Pico") { PicoMainView().environmentObject(state).onAppear { delegate.state = state } }.defaultSize(width: 980, height: 560)
        MenuBarExtra("Pico", systemImage: "doc.on.clipboard") { Button("打开剪贴板") { delegate.togglePanel() }; Button(state.isPaused ? "恢复监听" : "暂停监听") { state.togglePause() }; Divider(); Button("退出 Pico") { NSApp.terminate(nil) } }
    }
}
