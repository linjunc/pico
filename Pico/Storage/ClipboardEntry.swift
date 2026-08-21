import Foundation
import SwiftData

@Model
final class ClipboardEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var contentHash: String = ""
    var contentTypeRawValue: String = ClipboardContentType.text.rawValue
    var text: String?
    @Attribute(.externalStorage) var richTextData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var sourceBundleID: String?
    var sourceAppName: String?
    var ocrText: String?
    var customTitle: String?
    var isFavorite: Bool = false

    init(text: String? = nil, type: ClipboardContentType = .text, hash: String, sourceBundleID: String? = nil, sourceAppName: String? = nil) {
        self.text = text
        self.contentTypeRawValue = type.rawValue
        self.contentHash = hash
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }

    var contentType: ClipboardContentType { ClipboardContentType(rawValue: contentTypeRawValue) ?? .text }
}

@Model
final class ClipboardGroup {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "folder"
    var colorHex: String = "#65CFFF"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(name: String, iconName: String = "folder", colorHex: String = "#65CFFF", sortOrder: Int = 0) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}

@Model
final class GroupMembership {
    var id: UUID = UUID()
    var entryID: UUID = UUID()
    var groupID: UUID = UUID()
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(entryID: UUID, groupID: UUID, sortOrder: Int = 0) {
        self.entryID = entryID
        self.groupID = groupID
        self.sortOrder = sortOrder
    }
}
