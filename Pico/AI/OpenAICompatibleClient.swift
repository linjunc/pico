import Foundation

enum OpenAICompatibleError: LocalizedError {
    case invalidBaseURL, emptyResponse, server(String)
    var errorDescription: String? { switch self { case .invalidBaseURL: "Base URL 无效"; case .emptyResponse: "模型返回为空"; case .server(let message): message } }
}

actor OpenAICompatibleClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func models(configuration: AIModelConfiguration, apiKey: String) async throws -> [String] {
        let request = try makeRequest(configuration: configuration, apiKey: apiKey, path: "models", method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let payload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return payload.data.map(\.id)
    }

    func chat(configuration: AIModelConfiguration, apiKey: String, prompt: String) async throws -> String {
        let requestBody = ChatRequest(model: configuration.modelID, messages: [.init(role: "user", content: prompt)], temperature: 0.1)
        var request = try makeRequest(configuration: configuration, apiKey: apiKey, path: "chat/completions", method: "POST")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let payload = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = payload.choices.first?.message.content, !content.isEmpty else { throw OpenAICompatibleError.emptyResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeRequest(configuration: AIModelConfiguration, apiKey: String, path: String, method: String) throws -> URLRequest {
        let normalized = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        guard let base = URL(string: normalized), let url = URL(string: path, relativeTo: base) else { throw OpenAICompatibleError.invalidBaseURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); return request
    }
    private func validate(_ response: URLResponse, data: Data) throws { guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { let message = String(data: data, encoding: .utf8) ?? "请求失败"; throw OpenAICompatibleError.server(message.prefix(180).description) } }
}

private struct ModelListResponse: Decodable { let data: [ModelRecord] }
private struct ModelRecord: Decodable { let id: String }
private struct ChatRequest: Encodable { let model: String; let messages: [ChatMessage]; let temperature: Double }
private struct ChatMessage: Codable { let role: String; let content: String }
private struct ChatResponse: Decodable { let choices: [Choice] }
private struct Choice: Decodable { let message: ChatMessage }
