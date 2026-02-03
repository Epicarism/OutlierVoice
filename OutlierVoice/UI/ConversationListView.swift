import SwiftUI
import SwiftData

/// List of past conversations - shows both local and Outlier API conversations
struct ConversationListView: View {
    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var localConversations: [Conversation]
    
    @Environment(\.modelContext) private var modelContext
    
    // Remote conversations from Outlier API
    @State private var remoteConversations: [OutlierConversation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    let outlierClient: OutlierClient
    let onSelect: (Conversation) -> Void
    let onSelectRemote: (OutlierConversation) -> Void
    let onNewConversation: () -> Void
    
    var body: some View {
        List {
            Section {
                Button {
                    onNewConversation()
                } label: {
                    Label("New Conversation", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            
            // Remote Outlier conversations
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading from Outlier...")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if remoteConversations.isEmpty {
                    Text("No conversations on Outlier")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(remoteConversations) { conv in
                        RemoteConversationRow(conversation: conv)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectRemote(conv)
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Outlier Cloud")
                    Spacer()
                    Button {
                        Task { await loadRemoteConversations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(isLoading)
                }
            }
            
            // Local conversations
            Section("Local") {
                if localConversations.isEmpty {
                    Text("No local conversations")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(localConversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(conversation)
                            }
                    }
                    .onDelete(perform: deleteConversations)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .navigationTitle("History")
        .task {
            await loadRemoteConversations()
        }
        .refreshable {
            await loadRemoteConversations()
        }
    }
    
    private func loadRemoteConversations() async {
        isLoading = true
        errorMessage = nil
        
        do {
            remoteConversations = try await outlierClient.fetchConversations()
            print("[ConversationListView] Loaded \(remoteConversations.count) remote conversations")
        } catch {
            errorMessage = error.localizedDescription
            print("[ConversationListView] Error: \(error)")
        }
        
        isLoading = false
    }
    
    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(localConversations[index])
        }
    }
}

/// Row for remote Outlier conversation
struct RemoteConversationRow: View {
    let conversation: OutlierConversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if let starred = conversation.isStarred, starred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }
            
            HStack {
                Image(systemName: "cloud")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                
                if let updatedAt = conversation.updatedAt {
                    Text(formatDate(updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            return relFormatter.localizedString(for: date, relativeTo: Date())
        }
        return dateString
    }
}

/// Single conversation row
struct ConversationRow: View {
    let conversation: Conversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                // Model badge
                if let model = LLMModel(rawValue: conversation.modelUsed) {
                    Text(model.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }
                
                // Message count
                Text("\(conversation.messages.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ConversationListView(
            outlierClient: OutlierClient(),
            onSelect: { _ in },
            onSelectRemote: { _ in },
            onNewConversation: {}
        )
    }
}
