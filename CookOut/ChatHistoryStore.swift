import Foundation
import Combine

struct ChatConversation: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var messages: [ChatMessage]
    var modelRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var preview: String {
        messages.last(where: { $0.role == "assistant" })?.content
            ?? messages.last?.content
            ?? "Empty conversation"
    }
}

@MainActor
final class ChatHistoryStore: ObservableObject {
    @Published private(set) var conversations: [ChatConversation] = []
    private let fileURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CookOut", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("groq-conversations.json")
        load()
    }

    @discardableResult
    func save(id: UUID?, messages: [ChatMessage], modelRawValue: String) -> UUID? {
        guard !messages.isEmpty else { return id }
        let conversationID = id ?? UUID()
        let now = Date.now
        let title = Self.title(for: messages)

        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].messages = messages
            conversations[index].title = title
            conversations[index].modelRawValue = modelRawValue
            conversations[index].updatedAt = now
        } else {
            conversations.append(ChatConversation(id: conversationID,
                                                  title: title,
                                                  messages: messages,
                                                  modelRawValue: modelRawValue,
                                                  createdAt: now,
                                                  updatedAt: now))
        }
        persist()
        return conversationID
    }

    func delete(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        persist()
    }

    func deleteAll() {
        conversations.removeAll()
        persist()
    }

    private static func title(for messages: [ChatMessage]) -> String {
        let text = messages.first(where: { $0.role == "user" })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Cooking chat"
        guard text.count > 44 else { return text.isEmpty ? "Cooking chat" : text }
        return String(text.prefix(44)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ChatConversation].self, from: data) else { return }
        conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
