import SwiftUI
import SwiftData

/// Main content view - WhatsApp style
struct ContentView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showAlarms = false
    @State private var alarmManager = AlarmManager.shared
    
    var body: some View {
        NavigationStack {
            WhatsAppChatView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAlarms = true
                        } label: {
                            Image(systemName: "alarm")
                        }
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showSettings = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAlarms) {
            AlarmListView()
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                ConversationListView(
                    outlierClient: viewModel.getOutlierClient(),
                    onSelect: { conversation in
                        viewModel.loadConversation(conversation)
                        showHistory = false
                    },
                    onSelectRemote: { remoteConv in
                        viewModel.loadRemoteConversation(remoteConv)
                        showHistory = false
                    },
                    onNewConversation: {
                        viewModel.newConversation()
                        showHistory = false
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showHistory = false
                        }
                    }
                }
            }
        }
        // Models now load lazily on first use
        .fullScreenCover(item: Binding(
            get: { alarmManager.activeAlarm },
            set: { _ in }
        )) { alarm in
            AlarmTriggerView(alarm: alarm) {
                // Dismiss handled by AlarmManager
            }
        }
    }
}

#Preview {
    ContentView(viewModel: ChatViewModel())
}
