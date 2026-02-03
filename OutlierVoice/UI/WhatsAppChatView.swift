import SwiftUI
import PhotosUI
import AVFoundation

/// WhatsApp-style chat interface
struct WhatsAppChatView: View {
    @Bindable var viewModel: ChatViewModel
    let callManager = CallManager.shared
    @State private var textInput = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isHoldingMic = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showVoiceCall = false
    @State private var showFaceTime = false
    @State private var playingMessageId: UUID? = nil
    @State private var showCurrentThinking = false
    @AppStorage("showThinkingInChat") private var showThinkingInChat = true
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Floating call indicator when call is minimized
            if callManager.isMinimized {
                FloatingCallIndicator {
                    // Return to call
                    if callManager.callType == .voice {
                        callManager.maximizeCall()
                        showVoiceCall = true
                    } else if callManager.callType == .facetime {
                        callManager.maximizeCall()
                        showFaceTime = true
                    }
                }
                .padding(.top, 8)
            }
            
            if showThinkingInChat && viewModel.isGenerating && !viewModel.currentThinking.isEmpty {
                thinkingBanner
            }
            
            // Messages
            messagesView
            
            // Input bar
            inputBar
        }
        .background(Color(.systemBackground))
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                claudeHeader
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 20) {
                    // Voice call button
                    Button {
                        showVoiceCall = true
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.title3)
                    }
                    
                    // FaceTime button
                    Button {
                        showFaceTime = true
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.title3)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showVoiceCall) {
            VoiceCallView(viewModel: viewModel, isPresented: $showVoiceCall)
        }
        .fullScreenCover(isPresented: $showFaceTime) {
            FaceTimeCallView(viewModel: viewModel, isPresented: $showFaceTime)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                selectedImages = [image]
                showCamera = false
            }
        }
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
    }
    
    // MARK: - Claude Header
    
    private var claudeHeader: some View {
        HStack(spacing: 10) {
            ClaudeAvatar(size: 36)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude")
                    .font(.headline)
                
                if viewModel.isGenerating {
                    Text("typing...")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if viewModel.isPlaying {
                    Text("speaking...")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("online")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Messages View
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.messages, id: \.id) { message in
                        WhatsAppBubble(
                            message: message,
                            isPlayingThis: playingMessageId == message.id,
                            onReplay: {
                                Task {
                                    await replayMessage(message)
                                }
                            }
                        )
                        .id(message.id)
                    }
                    
                    // Typing indicator
                    if viewModel.isGenerating {
                        HStack {
                            TypingBubble()
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Thinking Banner
    
    private var thinkingBanner: some View {
        DisclosureGroup(isExpanded: $showCurrentThinking) {
            Text(viewModel.currentThinking)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple.opacity(0.7))
                Text("Thinking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Replay Audio
    
    private func replayMessage(_ message: Message) async {
        guard message.role == .assistant && !message.content.isEmpty else { return }
        
        playingMessageId = message.id
        await viewModel.replayAudio(for: message)
        playingMessageId = nil
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Image preview
            if !selectedImages.isEmpty {
                imagePreview
            }
            
            // Main input row
            HStack(spacing: 8) {
                // Attachment button
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .photosPicker(
                    isPresented: $showPhotoPicker,
                    selection: $selectedPhotos,
                    maxSelectionCount: 4,
                    matching: .images
                )
                
                // Text field
                HStack(spacing: 8) {
                    TextField("Message", text: $textInput, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isTextFieldFocused)
                    
                    // Camera quick button (when text field empty)
                    if textInput.isEmpty && selectedImages.isEmpty {
                        Button {
                            showCamera = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                
                // Send or Mic button
                if textInput.isEmpty && selectedImages.isEmpty {
                    // Microphone - hold to record
                    micButton
                } else {
                    // Send button
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Mic Button (Hold to Record)
    
    private var micButton: some View {
        Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
            .font(.title2)
            .foregroundStyle(viewModel.isRecording ? .red : .secondary)
            .frame(width: 36, height: 36)
            .background(viewModel.isRecording ? Color.red.opacity(0.2) : Color.clear)
            .cornerRadius(18)
            .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !viewModel.isRecording {
                            viewModel.startRecording()
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        viewModel.stopRecording()
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
            )
    }
    
    // MARK: - Image Preview
    
    private var imagePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedImages.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: selectedImages[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                            .clipped()
                        
                        Button {
                            selectedImages.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6).opacity(0.5))
    }
    
    // MARK: - Send Message
    
    private func sendMessage() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = selectedImages
        
        textInput = ""
        selectedImages = []
        selectedPhotos = []
        isTextFieldFocused = false
        
        Task {
            if !images.isEmpty {
                await viewModel.sendMessageWithImages(text: text.isEmpty ? "What's in this image?" : text, images: images)
            } else if !text.isEmpty {
                await viewModel.sendMessage(text: text)
            }
        }
    }
}

// MARK: - WhatsApp Style Message Bubble

struct WhatsAppBubble: View {
    @Bindable var message: Message
    let isPlayingThis: Bool
    let onReplay: () -> Void
    @State private var showThinking = false
    @AppStorage("showThinkingInChat") private var showThinkingInChat = true
    
    private var isUser: Bool {
        message.role == .user
    }
    
    private var hasThinking: Bool {
        let thinking = message.thinkingContent ?? ""
        return !thinking.isEmpty
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser && showThinkingInChat && hasThinking {
                    DisclosureGroup(isExpanded: $showThinking) {
                        ScrollView {
                            Text(message.thinkingContent ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200) // Limit height for long thinking
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.purple.opacity(0.7))
                            Text("Thinking (\(message.thinkingContent?.count ?? 0) chars)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(12, corners: [.topLeft, .topRight, .bottomRight])
                }
                
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.green : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(16, corners: isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
                
                // Footer row with time and replay
                HStack(spacing: 8) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    // Replay button for assistant messages
                    if !isUser {
                        Button {
                            onReplay()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isPlayingThis ? "speaker.wave.2.fill" : "play.circle.fill")
                                    .font(.caption)
                                Text(isPlayingThis ? "Playing..." : "Play")
                                    .font(.caption2)
                            }
                            .foregroundStyle(isPlayingThis ? .green : .purple)
                        }
                        .disabled(isPlayingThis)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - Typing Bubble

struct TypingBubble: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animationOffset
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .cornerRadius(16)
        .onAppear {
            animationOffset = -5
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Camera Capture View

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction
        
        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
