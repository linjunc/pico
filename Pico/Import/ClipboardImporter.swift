import Foundation

enum ClipboardImportSource: String, CaseIterable, Sendable { case paste = "Paste"; case pasteNow = "PasteNow"; case maccy = "Maccy"; case iCopy = "iCopy"; case ecoPaste = "EcoPaste" }
struct ImportedClipboardItem: Sendable { let text: String; let createdAt: Date?; let type: ClipboardContentType }
struct ImportPreview: Sendable { let source: ClipboardImportSource; let items: [ImportedClipboardItem]; let duplicateCount: Int; let failures: [String] }
enum ClipboardImportError: LocalizedError { case unsupportedFormat, unreadableFile; var errorDescription: String? { switch self { case .unsupportedFormat: "无法识别该导出格式"; case .unreadableFile: "无法读取导入文件" } } }

protocol ClipboardImporter: Sendable {
    var source: ClipboardImportSource { get }
    func preview(fileURL: URL, existingHashes: Set<String>) throws -> ImportPreview
}

struct PasteNowJSONImporter: ClipboardImporter {
    let source: ClipboardImportSource = .pasteNow
    func preview(fileURL: URL, existingHashes: Set<String>) throws -> ImportPreview {
        guard let data = try? Data(contentsOf: fileURL), let value = try? JSONSerialization.jsonObject(with: data) else { throw ClipboardImportError.unreadableFile }
        let candidates = Self.extractStrings(value)
        var seen = Set<String>(); var items: [ImportedClipboardItem] = []; var duplicates = 0
        for text in candidates where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hash = text.data(using: .utf8)!.base64EncodedString()
            if existingHashes.contains(hash) || !seen.insert(hash).inserted { duplicates += 1; continue }
            items.append(ImportedClipboardItem(text: text, createdAt: nil, type: ClipboardClassifier.classify(text)))
        }
        return ImportPreview(source: source, items: items, duplicateCount: duplicates, failures: [])
    }
    private static func extractStrings(_ value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap(extractStrings) }
        if let dictionary = value as? [String: Any] { return dictionary.values.flatMap(extractStrings) }
        return []
    }
}

struct LegacyDatabaseImporter: ClipboardImporter {
    let source: ClipboardImportSource
    func preview(fileURL: URL, existingHashes: Set<String>) throws -> ImportPreview {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else { throw ClipboardImportError.unreadableFile }
        return ImportPreview(source: source, items: [], duplicateCount: 0, failures: ["数据库导入适配器已注册，等待选择具体版本 schema"])
    }
}

