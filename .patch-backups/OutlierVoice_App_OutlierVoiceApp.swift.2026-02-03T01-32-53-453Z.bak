import SwiftUI
import SwiftData

@main
struct OutlierVoiceApp: App {
    let modelContainer: ModelContainer
    @State private var viewModel: ChatViewModel
    
    init() {
        // Setup SwiftData
        let schema = Schema([
            Message.self,
            Conversation.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            modelContainer = container
            
            // Configure conversation store synchronously
            ConversationStore.shared.configure(with: container)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        
        // Initialize view model
        _viewModel = State(initialValue: ChatViewModel())
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
            // REMOVED: .task { await viewModel.loadModels() }
            // Models load on-demand now, not at startup
        }
        .modelContainer(modelContainer)
    }
}
