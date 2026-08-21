import Foundation

public enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case link
    case code
    case color
    case image
    case fileURL
}

public enum ClipboardClassifier {
    public static func classify(_ text: String) -> ClipboardContentType {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if URL(string: value)?.scheme != nil { return .link }
        if isColor(value) { return .color }
        if looksLikeCode(value) { return .code }
        return .text
    }

    private static func looksLikeCode(_ value: String) -> Bool {
        let indicators = ["let ", "var ", "func ", "struct ", "class ", "import ", "=>", "{", "}"]
        return indicators.contains(where: value.contains) && value.contains(where: { $0 == "=" || $0 == "{" || $0 == "}" })
    }

    private static func isColor(_ value: String) -> Bool {
        guard value.first == "#", [4, 7, 9].contains(value.count) else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }
}
