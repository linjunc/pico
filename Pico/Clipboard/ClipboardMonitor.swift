import AppKit
import Foundation

@MainActor
final class ClipboardMonitor: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private var task: Task<Void, Never>?
    private var lastChangeCount: Int = 0
    private(set) var isPaused = false
    private var ignoredBundleIDs: Set<String> = []
    var repository: ClipboardRepository

    init(repository: ClipboardRepository = .shared) { self.repository = repository }

    func start() {
        lastChangeCount = pasteboard.changeCount
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                self?.poll()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
    func setPaused(_ paused: Bool) { isPaused = paused; if !paused { lastChangeCount = pasteboard.changeCount } }
    func setIgnoredBundleIDs(_ ids: Set<String>) { ignoredBundleIDs = ids }

    private func poll() {
        guard !isPaused else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard let app = NSWorkspace.shared.frontmostApplication,
              !(app.bundleIdentifier.map(ignoredBundleIDs.contains) ?? false) else { return }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            repository.captureImage(data, sourceBundleID: app.bundleIdentifier, sourceAppName: app.localizedName)
        } else if let file = pasteboard.string(forType: NSPasteboard.PasteboardType("public.file-url")) {
            repository.capture(text: file, sourceBundleID: app.bundleIdentifier, sourceAppName: app.localizedName)
        } else if let text = pasteboard.string(forType: .string) {
            repository.capture(text: text, sourceBundleID: app.bundleIdentifier, sourceAppName: app.localizedName)
        }
    }
}
