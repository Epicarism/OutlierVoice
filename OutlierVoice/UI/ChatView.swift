import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
typealias PlatformImageUI = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImageUI = NSImage
#endif

// Cross-platform color helpers
extension Color {
    static var systemBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    static var secondarySystemBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var systemGray5: Color {
        #if os(iOS)
        Color(UIColor.systemGray5)
        #else
        Color(NSColor.systemGray).opacity(0.3)
        #endif
    }
    
    static var systemGray6: Color {
        #if os(iOS)
        Color(UIColor.systemGray6)
        #else
        Color(NSColor.systemGray).opacity(0.2)
        #endif
    }
}

/// Main chat interface
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var textInput = ""
    @State private var showModelPicker = false
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    #else
    @State private var selectedImages: [NSImage] = []
    #endif
    @State private var showImagePicker = false
    @FocusState private var isTextFieldFocused: Bool
    
    // MARK: - Thinking Banner
    @ViewBuilder
    private var thinkingBannerView: some View {
        // DEBUG: Always show something to verify view is rendering
        let thinkingCount = viewModel.currentThinking.count
        let _ = print("[ThinkingBanner] Rendering, count=\(thinkingCount)")
        
        // Always show a debug indicator
        Text("🧠 Thinking: \(thinkingCount) chars")
            .font(.caption)
            .foregroundStyle(thinkingCount > 0 ? .purple : .gray)
            .padding(4)
            .background(thinkingCount > 0 ? Color.purple.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(4)
            .padding(.horizontal)
        
        if thinkingCount > 0 {
            Text(viewModel.currentThinking)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                thinkingBannerView
                
                if viewModel.messages.isEmpty {
                    emptyStateView
                } else {
                    messagesListView
                }
                
                Divider()
                
                // Show different UI based on voice mode
                if viewModel.voiceMode == .facetime {
                    FaceTimeClaudeView(viewModel: viewModel)
                } else if viewModel.voiceMode == .handsfree && viewModel.isRecording {
                    HandsfreeCallView(viewModel: viewModel)
                } else {
                    inputAreaView
                }
            }
            .background(Color.systemBackground)
        }
        .navigationTitle("Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPicker(selectedModel: $viewModel.currentModel)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.newConversation()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
            }
        }
        #endif
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "Unknown error")
        }
        #if os(iOS)
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                selectedImages = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
            }
        }
        #endif
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Claude avatar
            ClaudeAvatar(size: 100)
            
            VStack(spacing: 8) {
                Text("Hey! I'm Claude 👋")
                    .font(.title2)
                    .bold()
                
                Text("Tap the mic to speak, or type below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Quick suggestions
            VStack(spacing: 10) {
                suggestionButton("🧠 Explain quantum computing simply")
                suggestionButton("✍️ Write me a haiku about coding")
                suggestionButton("🐛 Help me debug my code")
                suggestionButton("📸 Analyze an image for me")
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.systemBackground)
    }
    
    private func suggestionButton(_ text: String) -> some View {
        Button {
            Task {
                await viewModel.sendMessage(text: text)
            }
        } label: {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.systemGray6)
                .foregroundStyle(.primary)
                .cornerRadius(20)
        }
    }
    
    // MARK: - Messages List
    
    private var messagesListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {  // Use VStack instead of LazyVStack to avoid caching issues
                    let _ = print("[ChatView] Rendering \(viewModel.messages.count) messages, refresh=\(viewModel.refreshTrigger)")
                    ForEach(viewModel.messages, id: \.id) { message in
                        MessageBubble(
                            message: message,
                            isPlaying: viewModel.isPlaying,
                            onReplay: {
                                Task {
                                    await viewModel.replayAudio(for: message)
                                }
                            }
                        )
                        // Include refresh trigger in ID to force re-render
                        .id("\(message.id)-\(viewModel.refreshTrigger)")
                    }
                    
                    // Claude typing/speaking indicator
                    if viewModel.isGenerating || viewModel.isPlaying {
                        HStack(spacing: 12) {
                            ClaudeAvatar(size: 36)
                            
                            if viewModel.isPlaying {
                                SpeakingWaveform()
                            } else {
                                TypingIndicator()
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .background(Color.systemBackground)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input Area
    
    private var inputAreaView: some View {
        VStack(spacing: 12) {
            // Image preview if selected
            if !selectedImages.isEmpty {
                imagePreviewRow
            }
            
            // Voice mode toggle
            VoiceModeToggle(mode: $viewModel.voiceMode)
                .padding(.horizontal)
                .padding(.top, 12)
            
            // Status indicators
            if viewModel.isTranscribing {
                StatusBadge(text: "Transcribing...", icon: "waveform", color: .orange)
            } else if viewModel.isPlaying {
                StatusBadge(text: "Claude is speaking...", icon: "speaker.wave.2.fill", color: .purple)
            }
            
            // Voice button
            VoiceButton(
                mode: viewModel.voiceMode,
                isRecording: viewModel.isRecording,
                isProcessing: viewModel.isTranscribing || viewModel.isGenerating,
                amplitude: viewModel.amplitude,
                onTapDown: { viewModel.startRecording() },
                onTapUp: { viewModel.stopRecording() },
                onTap: { viewModel.toggleHandsfreeListening() }
            )
            .padding(.vertical, 8)
            
            // Text input with image picker
            HStack(spacing: 12) {
                #if os(iOS)
                // Image picker button
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                #else
                // macOS: simple button (would need file picker)
                Button {
                    // TODO: Implement macOS file picker
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                #endif
                
                TextField("Type a message...", text: $textInput)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.systemGray6)
                    .cornerRadius(20)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        sendTextMessage()
                    }
                
                Button {
                    sendTextMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundStyle((textInput.isEmpty && selectedImages.isEmpty) ? .gray : .blue)
                }
                .disabled(textInput.isEmpty && selectedImages.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Color.secondarySystemBackground)
    }
    
    private var imagePreviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        #if os(iOS)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                        #else
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                        #endif
                        
                        Button {
                            selectedImages.remove(at: index)
                            #if os(iOS)
                            selectedPhotos.remove(at: index)
                            #endif
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
    
    private func sendTextMessage() {
        guard !textInput.isEmpty || !selectedImages.isEmpty else { return }
        let text = textInput
        let images = selectedImages
        textInput = ""
        selectedImages = []
        #if os(iOS)
        selectedPhotos = []
        #endif
        isTextFieldFocused = false
        
        Task {
            if images.isEmpty {
                await viewModel.sendMessage(text: text)
            } else {
                await viewModel.sendMessageWithImages(text: text, images: images)
            }
        }
    }
}

// MARK: - Claude Avatar

struct ClaudeAvatar: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Speaking Waveform

struct SpeakingWaveform: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.purple)
                    .frame(width: 4, height: animating ? CGFloat.random(in: 8...24) : 8)
                    .animation(
                        .easeInOut(duration: 0.3)
                        .repeatForever()
                        .delay(Double(i) * 0.1),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.purple.opacity(0.15))
        .cornerRadius(16)
        .onAppear { animating = true }
    }
}

// MARK: - Handsfree Call View

struct HandsfreeCallView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var callDuration: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Claude avatar with pulse
            ZStack {
                // Pulse rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                        .frame(width: 140 + CGFloat(i * 30), height: 140 + CGFloat(i * 30))
                        .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.0)
                            .repeatForever()
                            .delay(Double(i) * 0.2),
                            value: viewModel.isRecording
                        )
                }
                
                ClaudeAvatar(size: 120)
            }
            
            // Status
            VStack(spacing: 8) {
                Text(viewModel.isTranscribing ? "Processing..." :
                     viewModel.isGenerating ? "Claude is thinking..." :
                     viewModel.isPlaying ? "Claude is speaking..." :
                     "Listening...")
                    .font(.title3)
                    .bold()
                
                Text(formatDuration(callDuration))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            // Waveform
            LiveWaveform(amplitude: viewModel.amplitude, isActive: viewModel.isRecording)
                .frame(height: 60)
                .padding(.horizontal, 40)
            
            Spacer()
            
            // End call button
            Button {
                viewModel.stopAll()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.systemBackground, Color.purple.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onReceive(timer) { _ in
            callDuration += 1
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Live Waveform

struct LiveWaveform: View {
    let amplitude: Float
    let isActive: Bool
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { i in
                    let height = isActive ?
                        max(4, CGFloat(amplitude) * geo.size.height * CGFloat.random(in: 0.5...1.5)) :
                        4
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.purple.opacity(isActive ? 0.8 : 0.3))
                        .frame(width: (geo.size.width - 87) / 30, height: height)
                        .animation(.easeOut(duration: 0.1), value: amplitude)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @Bindable var message: Message  // @Bindable to observe property changes on @Model
    let isPlaying: Bool
    let onReplay: () -> Void
    
    @State private var showThinking = false
    @AppStorage("showThinkingInChat") private var showThinkingInChat = true
    
    private var isUser: Bool { message.role == .user }
    private var hasThinking: Bool { message.thinkingContent != nil && !message.thinkingContent!.isEmpty }
    
    var body: some View {
        let _ = print("[MessageBubble] 🧠 id=\(message.id.uuidString.prefix(8)), role=\(message.role.rawValue), hasThinking=\(hasThinking), thinkingLen=\(message.thinkingContent?.count ?? 0)")
        
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer(minLength: 50) }
            
            if !isUser {
                ClaudeAvatar(size: 36)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // ALWAYS show thinking for assistant messages that have it (debug)
                if !isUser && message.thinkingContent != nil && !(message.thinkingContent?.isEmpty ?? true) {
                    // Debug: show thinking length
                    Text("🧠 THINKING (\(message.thinkingContent?.count ?? 0) chars)")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .padding(4)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(4)
                }
                
                // Thinking content (collapsible, greyed out)
                if !isUser && hasThinking {
                    DisclosureGroup(isExpanded: $showThinking) {
                        Text(message.thinkingContent ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.purple.opacity(0.6))
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(12)
                }
                
                // Message content
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isUser ? Color.blue : Color.systemGray5)
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(20)
                
                // Actions row
                HStack(spacing: 12) {
                    // Timestamp
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    // Replay button for assistant messages
                    if !isUser {
                        Button {
                            onReplay()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle")
                                Text(isPlaying ? "Playing" : "Replay")
                            }
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            if isUser {
                // User avatar
                Image(systemName: "person.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            
            if !isUser { Spacer(minLength: 50) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == index ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.systemGray5)
        .cornerRadius(20)
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .cornerRadius(16)
    }
}

#Preview {
    NavigationStack {
        ChatView(viewModel: ChatViewModel())
    }
}
