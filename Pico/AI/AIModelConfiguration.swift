import Foundation
import Security

struct AIModelConfiguration: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var baseURL: String
    var modelID: String
    var isDefault: Bool

    init(id: UUID = UUID(), name: String, baseURL: String, modelID: String, isDefault: Bool = true) {
        self.id = id; self.name = name; self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines); self.modelID = modelID; self.isDefault = isDefault
    }
}

enum AIKeyStoreError: Error { case unexpectedStatus(OSStatus) }

final class AIKeyStore: Sendable {
    static let shared = AIKeyStore()
    private let service = "com.linjunc.pico.ai-model"

    func save(_ key: String, for configurationID: UUID) throws {
        let account = configurationID.uuidString
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = Data(key.utf8)
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AIKeyStoreError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess { throw AIKeyStoreError.unexpectedStatus(status) }
    }

    func load(for configurationID: UUID) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: configurationID.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
