import CryptoKit
import Foundation
import SwiftData

@MainActor
final class ClipboardRepository: ObservableObject {
    static let shared = ClipboardRepository()
    let container: ModelContainer
    private let context: ModelContext

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var groups: [ClipboardGroup] = []

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: ClipboardEntry.self, ClipboardGroup.self, GroupMembership.self, configurations: configuration)
            context = ModelContext(container)
            refresh()
        } catch {
            fatalError("Pico storage initialization failed: \(error)")
        }
    }

    func refresh() {
        entries = (try? context.fetch(FetchDescriptor<ClipboardEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        groups = (try? context.fetch(FetchDescriptor<ClipboardGroup>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    @discardableResult
    func capture(text: String, sourceBundleID: String? = nil, sourceAppName: String? = nil) -> ClipboardEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hash = SHA256.hash(data: Data(trimmed.utf8)).map { String(format: "%02x", $0) }.joined()
        let type = ClipboardClassifier.classify(trimmed)
        if let existing = entries.first(where: { $0.contentHash == hash }) {
            existing.updatedAt = Date()
            try? context.save()
            refresh()
            return existing
        }
        let entry = ClipboardEntry(text: trimmed, type: type, hash: hash, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName)
        context.insert(entry)
        try? context.save()
        refresh()
        return entry
    }

    @discardableResult
    func captureImage(_ data: Data, sourceBundleID: String? = nil, sourceAppName: String? = nil) -> ClipboardEntry? {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = entries.first(where: { $0.contentHash == hash }) { existing.updatedAt = Date(); try? context.save(); refresh(); return existing }
        let entry = ClipboardEntry(text: nil, type: .image, hash: hash, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName)
        entry.imageData = data
        context.insert(entry); try? context.save(); refresh(); return entry
    }

    func toggleFavorite(_ entry: ClipboardEntry) {
        entry.isFavorite.toggle()
        try? context.save()
        refresh()
    }

    func delete(_ entry: ClipboardEntry) {
        context.delete(entry)
        try? context.save()
        refresh()
    }

    func addGroup(name: String) {
        context.insert(ClipboardGroup(name: name, sortOrder: groups.count))
        try? context.save()
        refresh()
    }

    func add(_ entry: ClipboardEntry, to group: ClipboardGroup) {
        let entryID = entry.id
        let groupID = group.id
        let descriptor = FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.entryID == entryID && $0.groupID == groupID })
        guard (try? context.fetch(descriptor).isEmpty) == true else { return }
        context.insert(GroupMembership(entryID: entry.id, groupID: group.id))
        try? context.save()
    }

    func remove(_ entry: ClipboardEntry, from group: ClipboardGroup) {
        let entryID = entry.id
        let groupID = group.id
        let descriptor = FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.entryID == entryID && $0.groupID == groupID })
        if let membership = try? context.fetch(descriptor).first { context.delete(membership); try? context.save() }
    }

    func groupsContaining(_ entry: ClipboardEntry) -> [ClipboardGroup] {
        let entryID = entry.id
        let memberships = (try? context.fetch(FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.entryID == entryID }))) ?? []
        let ids = Set(memberships.map(\.groupID))
        return groups.filter { ids.contains($0.id) }
    }
}
