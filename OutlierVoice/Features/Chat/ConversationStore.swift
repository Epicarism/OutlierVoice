import Foundation
import SwiftData

/// Manages conversation persistence with SwiftData
@MainActor
final class ConversationStore {
    static let shared = ConversationStore()
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Initialize with model container
    func configure(with container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = container.mainContext
    }
    
    // MARK: - Conversation CRUD
    
    func createConversation(title: String = "New Conversation", model: LLMModel = .opus45) -> Conversation {
        let conversation = Conversation(
            title: title,
            modelUsed: model.rawValue
        )
        
        modelContext?.insert(conversation)
        try? modelContext?.save()
        
        return conversation
    }
    
    func fetchConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        do {
            return try modelContext?.fetch(descriptor) ?? []
        } catch {
            print("Failed to fetch conversations: \(error)")
            return []
        }
    }
    
    func fetchConversation(by id: UUID) -> Conversation? {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            return try modelContext?.fetch(descriptor).first
        } catch {
            print("Failed to fetch conversation: \(error)")
            return nil
        }
    }
    
    func updateConversation(_ conversation: Conversation) {
        conversation.updatedAt = Date()
        try? modelContext?.save()
    }
    
    func deleteConversation(_ conversation: Conversation) {
        modelContext?.delete(conversation)
        try? modelContext?.save()
    }
    
    func deleteAllConversations() {
        let conversations = fetchConversations()
        for conversation in conversations {
            modelContext?.delete(conversation)
        }
        try? modelContext?.save()
    }
    
    // MARK: - Message Operations
    
    func addMessage(to conversation: Conversation, role: MessageRole, content: String, audioURL: URL? = nil) -> Message {
        let message = Message(
            role: role,
            content: content,
            audioURL: audioURL,
            conversationID: conversation.id
        )
        
        conversation.messages.append(message)
        conversation.updatedAt = Date()
        
        // Auto-generate title from first user message
        if conversation.title == "New Conversation" {
            conversation.generateTitle(from: conversation.messages)
        }
        
        modelContext?.insert(message)
        try? modelContext?.save()
        
        return message
    }
    
    func save() {
        try? modelContext?.save()
    }
}
