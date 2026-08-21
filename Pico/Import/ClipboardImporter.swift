import Foundation
import CryptoKit
import SQLite3

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
        var database: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw ClipboardImportError.unreadableFile }
        defer { sqlite3_close(database) }
        let tables = ["history", "clips", "items", "ZHISTORYITEM", "clipboard"]
        var imported: [ImportedClipboardItem] = []; var duplicates = 0; var failures: [String] = []
        for table in tables {
            let query = "SELECT * FROM \(table) LIMIT 100000"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else { continue }
            defer { sqlite3_finalize(statement) }
            let columnCount = sqlite3_column_count(statement)
            let names = (0..<columnCount).map { String(cString: sqlite3_column_name(statement, $0)) .lowercased() }
            let textIndex = names.firstIndex { $0.contains("text") || $0.contains("value") || $0.contains("content") || $0.contains("title") }
            guard let textIndex else { continue }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pointer = sqlite3_column_text(statement, Int32(textIndex)) else { continue }
                let text = String(cString: pointer)
                guard !text.isEmpty else { continue }
                let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                if existingHashes.contains(hash) { duplicates += 1; continue }
                imported.append(ImportedClipboardItem(text: text, createdAt: nil, type: ClipboardClassifier.classify(text)))
            }
            if !imported.isEmpty { break }
        }
        if imported.isEmpty { failures.append("未找到可识别的文本字段") }
        return ImportPreview(source: source, items: imported, duplicateCount: duplicates, failures: failures)
    }
}
