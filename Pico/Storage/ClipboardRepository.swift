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
    @Published private(set) var membershipsByGroup: [UUID: Set<UUID>] = [:]
    @Published private(set) var groupsByEntry: [UUID: [ClipboardGroup]] = [:]

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
        refreshGroups()
    }

    /// 轻量刷新：只重拉分组和成员关系，不触碰条目列表。
    /// 新建/重命名/删除分组时用这个，避免全量 entries 刷新带来的 UI 卡顿。
    private func refreshGroups() {
        groups = (try? context.fetch(FetchDescriptor<ClipboardGroup>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        rebuildMemberships()
    }

    private func rebuildMemberships() {
        let raw: [GroupMembership] = (try? context.fetch(FetchDescriptor<GroupMembership>())) ?? []
        var byGroup: [UUID: Set<UUID>] = [:]
        var byEntry: [UUID: [UUID]] = [:]
        for m in raw {
            byGroup[m.groupID, default: []].insert(m.entryID)
            byEntry[m.entryID, default: []].append(m.groupID)
        }
        membershipsByGroup = byGroup
        let resolvedGroups = groups
        groupsByEntry = byEntry.mapValues { ids in
            let idSet = Set(ids)
            return resolvedGroups.filter { idSet.contains($0.id) }
        }
    }

    func entries(inGroupID groupID: UUID?) -> [ClipboardEntry] {
        guard let groupID else { return entries }
        let ids = membershipsByGroup[groupID] ?? []
        let entrySet = Set(entries.map(\.id))
        return entries.filter { ids.contains($0.id) && entrySet.contains($0.id) }
    }

    var favoriteEntries: [ClipboardEntry] {
        entries.filter(\.isFavorite)
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
        let entryID = entry.id
        // 先清 memberships（外键残余）
        let descriptor = FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.entryID == entryID })
        if let ms = try? context.fetch(descriptor) { for m in ms { context.delete(m) } }
        context.delete(entry)
        try? context.save()
        refresh()
    }

    func addGroup(name: String, iconName: String = "folder") {
        context.insert(ClipboardGroup(name: name, iconName: iconName, sortOrder: groups.count))
        try? context.save()
        refreshGroups()
    }

    func renameGroup(_ group: ClipboardGroup, to name: String) {
        group.name = name
        try? context.save()
        refreshGroups()
    }

    func deleteGroup(_ group: ClipboardGroup) {
        let groupID = group.id
        // 先更新发布状态，让侧栏立即响应；SwiftData 持久化随后完成。
        groups.removeAll { $0.id == groupID }
        membershipsByGroup.removeValue(forKey: groupID)
        groupsByEntry = groupsByEntry.mapValues { $0.filter { $0.id != groupID } }
        let descriptor = FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.groupID == groupID })
        if let ms = try? context.fetch(descriptor) { for m in ms { context.delete(m) } }
        context.delete(group)
        try? context.save()
        refreshGroups()
    }

    func add(_ entry: ClipboardEntry, to group: ClipboardGroup) {
        let entryID = entry.id
        let groupID = group.id
        let descriptor = FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.entryID == entryID && $0.groupID == groupID })
        guard (try? context.fetch(descriptor).isEmpty) == true else { return }
        context.insert(GroupMembership(entryID: entry.id, groupID: group.id))
        try? context.save()
        refreshGroups()
    }

    func remove(_ entry: ClipboardEntry, from group: ClipboardGroup) {
        let entryID = entry.id
        let groupID = group.id
        let descriptor = FetchDescriptor<GroupMembership>(predicate: #Predicate { $0.entryID == entryID && $0.groupID == groupID })
        if let membership = try? context.fetch(descriptor).first { context.delete(membership); try? context.save(); refreshGroups() }
    }

    func groupsContaining(_ entry: ClipboardEntry) -> [ClipboardGroup] {
        groupsByEntry[entry.id] ?? []
    }

    func bulkCapture(_ items: [ImportCandidate]) -> Int {
        var inserted = 0
        for item in items {
            if capture(text: item.text, sourceAppName: item.sourceAppName ?? "历史导入") != nil { inserted += 1 }
        }
        return inserted
    }
}

struct ImportCandidate: Sendable {
    let text: String
    let sourceAppName: String?
    let type: ClipboardContentType
}
