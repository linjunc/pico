import Foundation

struct TranslationResult: Sendable { let source: String; let translated: String; let direction: TranslationDirection }
struct TranslationFailure: Sendable { let message: String }

@MainActor
final class TranslationCoordinator {
    static let shared = TranslationCoordinator()
    private var running: [UUID: Task<Void, Never>] = [:]
    private let client = OpenAICompatibleClient()

    func translate(entry: ClipboardEntry) {
        guard let source = entry.text, !source.isEmpty else { postFailure("只有文本内容可以翻译"); return }
        if running[entry.id] != nil { return }
        let direction = TranslationDirection.forText(source)
        guard let configuration = Self.loadConfiguration(), let key = AIKeyStore.shared.load(for: configuration.id), !key.isEmpty else { postFailure("请先在 AI 模型设置中配置模型"); return }
        let prompt = direction == .english ? "Translate the following text into Simplified Chinese. Return only the translation:\n\n\(source)" : "Translate the following text into natural English. Return only the translation:\n\n\(source)"
        running[entry.id] = Task { [weak self] in
            do { let translated = try await self?.client.chat(configuration: configuration, apiKey: key, prompt: prompt); guard let translated else { return }; self?.postSuccess(TranslationResult(source: source, translated: translated, direction: direction)) }
            catch { self?.postFailure(error.localizedDescription) }
            self?.clear(entry.id)
        }
    }

    func cancel(entryID: UUID) { running[entryID]?.cancel(); running[entryID] = nil }
    private func clear(_ id: UUID) { running[id] = nil }
    private func postSuccess(_ result: TranslationResult) { NotificationCenter.default.post(name: .picoTranslationSucceeded, object: result) }
    private func postFailure(_ message: String) { NotificationCenter.default.post(name: .picoTranslationFailed, object: TranslationFailure(message: message)) }

    static func loadConfiguration() -> AIModelConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: "pico.ai.model"), let config = try? JSONDecoder().decode(AIModelConfiguration.self, from: data) else { return nil }
        return config
    }
}
