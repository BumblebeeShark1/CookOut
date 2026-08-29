import Foundation
import Security

enum GroqModel: String, CaseIterable, Identifiable {
    case gptOSS120B = "openai/gpt-oss-120b"
    case gptOSS20B = "openai/gpt-oss-20b"
    case llama70B = "llama-3.3-70b-versatile"
    case llama8B = "llama-3.1-8b-instant"
    case qwen38_27B = "qwen/qwen3.8-27b"

    var id: Self { self }
    var name: String {
        switch self {
        case .gptOSS120B: "GPT-OSS 120B"
        case .gptOSS20B: "GPT-OSS 20B"
        case .llama70B: "Llama 3.3 70B"
        case .llama8B: "Llama 3.1 8B"
        case .qwen38_27B: "Qwen 3.8 27B · Preview"
        }
    }
    var detail: String {
        switch self {
        case .gptOSS120B: "Best reasoning · ~500 tok/s"
        case .gptOSS20B: "Fast reasoning · ~1,000 tok/s"
        case .llama70B: "Versatile answers · ~280 tok/s"
        case .llama8B: "Fastest everyday help · ~560 tok/s"
        case .qwen38_27B: "Advanced reasoning · ~450 tok/s"
        }
    }
    var symbol: String {
        switch self { case .gptOSS120B: "brain.head.profile"; case .gptOSS20B: "bolt.brain"; case .llama70B: "wand.and.sparkles"; case .llama8B: "hare.fill"; case .qwen38_27B: "sparkle.magnifyingglass" }
    }
}

enum GroqKeychain {
    private static let service = "Mom.CookOut.Groq"
    private static let account = "GROQ_API_KEY"

    static func save(_ key: String) throws {
        let data = Data(normalized(key).utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw GroqChatError.keychain(status) }
    }

    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8).map(normalized)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }

    nonisolated static func normalized(_ key: String) -> String {
        key.replacingOccurrences(of: "\\_", with: "_")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

struct ChatMessage: Identifiable, Encodable, Equatable {
    let id: UUID
    let role: String
    let content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id; self.role = role; self.content = content
    }

    private enum CodingKeys: String, CodingKey { case role, content }
}

enum GroqChatError: LocalizedError {
    case missingKey, invalidKey, keychain(OSStatus), server(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Groq API key to start chatting."
        case .invalidKey: "Groq rejected the API key. Replace it and try again."
        case .keychain(let status): "The API key could not be saved securely (\(status))."
        case .server(let message): message
        case .invalidResponse: "Groq returned an unreadable response."
        }
    }
}

struct GroqChatService {
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    func reply(to conversation: [ChatMessage], cookbook: [CookingNote], apiKey: String? = nil, model: GroqModel = .gptOSS120B) async throws -> String {
        guard let key = apiKey.map(GroqKeychain.normalized) ?? GroqKeychain.load(), !key.isEmpty else { throw GroqChatError.missingKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let context = cookbook.prefix(10).map { note in
            "- \(note.title): \(note.ingredients.prefix(5).joined(separator: ", "))"
        }.joined(separator: "\n")
        let system = ChatMessage(role: "system", content: """
        You are CookOut's practical cooking assistant. Give clear, specific, concise help with recipes, substitutions, technique, planning, and troubleshooting. Ask a short clarifying question when essential. Use numbered steps for procedures. Never invent a safe internal temperature; distinguish food-safety guidance from preference, mention allergy and cross-contamination risks when relevant, and tell the user when uncertainty requires checking an authoritative local source. The user's cookbook summary follows; use it only when helpful.\n\(context.isEmpty ? "No saved recipes yet." : context)
        """)
        let messages = [system] + Array(conversation.suffix(12))
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model.rawValue, messages: messages, maxCompletionTokens: 1000))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroqChatError.invalidResponse }
        if http.statusCode == 401 { throw GroqChatError.invalidKey }
        guard (200...299).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw GroqChatError.server(apiError?.error.message ?? "Groq request failed (HTTP \(http.statusCode)).")
        }
        guard let content = try? JSONDecoder().decode(ResponseBody.self, from: data).choices.first?.message.content,
              !content.isEmpty else { throw GroqChatError.invalidResponse }
        return content
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [ChatMessage]
        let maxCompletionTokens: Int
        enum CodingKeys: String, CodingKey {
            case model, messages
            case maxCompletionTokens = "max_completion_tokens"
        }
    }
    private struct ResponseBody: Decodable { let choices: [Choice] }
    private struct Choice: Decodable { let message: ResponseMessage }
    private struct ResponseMessage: Decodable { let content: String }
    private struct ErrorEnvelope: Decodable { let error: APIError }
    private struct APIError: Decodable { let message: String }
}
