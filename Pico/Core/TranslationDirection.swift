import Foundation

public enum TranslationDirection: String, Codable, Sendable {
    case english
    case simplifiedChinese

    public static func forText(_ text: String) -> Self {
        text.range(of: #"[\u{3400}-\u{9FFF}]"#, options: .regularExpression) == nil
            ? .simplifiedChinese
            : .english
    }
}

