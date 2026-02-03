import Foundation
import SwiftUI
import SwiftData
import AVFoundation

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Voice mode options
enum VoiceMode: String, CaseIterable, Identifiable {
    case pushToTalk = "Push to Talk"
    case handsfree = "Handsfree"
    case facetime = "FaceTime Claude"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pushToTalk: return "hand.tap"
        case .handsfree: return "waveform"
        case .facetime: return "video.fill"
        }
    }
}

/// Main view model for chat functionality
@Observable
@MainActor
final class ChatViewModel {
    // Services
    private let outlierClient: OutlierClient
    private let appleSTTEngine: STTEngine
    private let whisperSTTEngine: WhisperSTTEngine
    private let ttsEngine: TTSEngine
    private let vadEngine: VADEngine
    private let voiceInputManager: VoiceInputManager
    private let audioSessionManager = AudioSessionManager.shared
    
    // State
    var messages: [Message] = []
    var currentConversation: Conversation?
    var isLoading = false
    var isRecording = false
    var isTranscribing = false
    var isGenerating = false
    var isPlaying = false
    var currentModel: LLMModel = .opus45
    var voiceMode: VoiceMode = .pushToTalk
    var error: Error?
    var streamingResponse = ""
    var amplitude: Float = 0
    var refreshTrigger = 0  // Increment to force SwiftUI refresh
    var currentThinking = ""  // Direct observable for UI
    
    // FaceTime Claude - pending image to send with next message
    var pendingImageData: Data?
    
    // Model loading state
    var isSTTLoaded = false
    var isTTSLoaded = false
    var isLoadingModels = false
    
    // STT Engine selection (persisted)
    var sttEngineType: STTEngineType {
        get {
            let stored = UserDefaults.standard.string(forKey: "sttEngineType") ?? "whisper"
            return STTEngineType(rawValue: stored) ?? .apple
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sttEngineType")
            // Reset loaded state when changing engines
            isSTTLoaded = false
            print("[ChatViewModel] STT engine changed to: \(newValue.rawValue)")
        }
    }
    
    /// Get the current STT engine based on selection
    private var currentSTTEngine: any STTEngineProtocol {
        switch sttEngineType {
        case .apple:
            return appleSTTEngine
        case .whisper:
            return whisperSTTEngine
        }
    }
    
    /// Access to outlier client for fetching conversations
    func getOutlierClient() -> OutlierClient {
        return outlierClient
    }
    
    init(
        outlierClient: OutlierClient = OutlierClient(),
        appleSTTEngine: STTEngine = STTEngine(),
        whisperSTTEngine: WhisperSTTEngine = WhisperSTTEngine(),
        ttsEngine: TTSEngine? = nil,
        vadEngine: VADEngine = VADEngine()
    ) {
        self.outlierClient = outlierClient
        self.appleSTTEngine = appleSTTEngine
        self.whisperSTTEngine = whisperSTTEngine
        self.ttsEngine = ttsEngine ?? TTSEngine()
        self.vadEngine = vadEngine
        self.voiceInputManager = VoiceInputManager(vadEngine: vadEngine)
        
        setupCallbacks()
        cleanupOldTempFiles()
    }
    
    /// Clean up old temp audio files from PREVIOUS sessions (older than 1 hour)
    private func cleanupOldTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default
        let oneHourAgo = Date().addingTimeInterval(-3600)
        
        do {
            let files = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])
            var deletedCount = 0
            
            for file in files {
                let name = file.lastPathComponent
                // Only clean our audio temp files (vad_, ptt_, snapshot_)
                guard name.hasPrefix("vad_") || name.hasPrefix("ptt_") || name.hasPrefix("snapshot_") else {
                    continue
                }
                
                // Only delete files older than 1 hour (from previous sessions)
                if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                   let creationDate = attrs[.creationDate] as? Date,
                   creationDate < oneHourAgo {
                    try? fileManager.removeItem(at: file)
                    deletedCount += 1
                }
            }
            
            if deletedCount > 0 {
                print("[ChatViewModel] 🗑️ Cleaned up \(deletedCount) old temp files (>1hr old)")
            }
        } catch {
            print("[ChatViewModel] ⚠️ Failed to clean temp directory: \(error)")
        }
    }
    
    private func setupCallbacks() {
        // VAD callbacks for handsfree mode
        vadEngine.onSpeechStart = { [weak self] in
            print("[ChatViewModel] 🎙️ VAD onSpeechStart callback fired!")
            Task { @MainActor in
                self?.isRecording = true
            }
        }
        
        vadEngine.onSpeechEnd = { [weak self] url in
            print("[ChatViewModel] 🔇 VAD onSpeechEnd callback fired! URL: \(url.lastPathComponent)")
            Task { @MainActor in
                self?.isRecording = false
                print("[ChatViewModel] 🎯 Calling handleVoiceInput...")
                await self?.handleVoiceInput(audioURL: url)
                print("[ChatViewModel] ✅ handleVoiceInput completed")
            }
        }
        
        vadEngine.onAmplitudeChange = { [weak self] amp in
            Task { @MainActor in
                self?.amplitude = amp
            }
        }
        
        vadEngine.onError = { [weak self] error in
            Task { @MainActor in
                self?.error = error
            }
        }
        
        // Voice input manager callbacks
        voiceInputManager.onRecordingStarted = { [weak self] in
            Task { @MainActor in
                self?.isRecording = true
            }
        }
        
        voiceInputManager.onRecordingFinished = { [weak self] url in
            Task { @MainActor in
                self?.isRecording = false
                await self?.handleVoiceInput(audioURL: url)
            }
        }
        
        voiceInputManager.onError = { [weak self] error in
            Task { @MainActor in
                self?.error = error
            }
        }
    }
    
    // MARK: - Model Loading
    
    func loadModels() async {
        print("[ChatViewModel] loadModels() called")
        
        // Prevent double loading
        guard !isLoadingModels else {
            print("[ChatViewModel] Already loading models, skipping")
            return
        }
        
        guard !isSTTLoaded || !isTTSLoaded else {
            print("[ChatViewModel] Models already loaded, skipping")
            return
        }
        
        isLoadingModels = true
        
        do {
            // Request audio permission first
            print("[ChatViewModel] Requesting mic permission...")
            let hasPermission = await audioSessionManager.requestPermission()
            guard hasPermission else {
                print("[ChatViewModel] Mic permission DENIED")
                error = AudioSessionManager.AudioSessionError.permissionDenied
                isLoadingModels = false
                return
            }
            print("[ChatViewModel] Mic permission granted")
            
            try audioSessionManager.configure()
            print("[ChatViewModel] Audio session configured")
            
            // Load STT model only if not already loaded
            if !isSTTLoaded {
                print("[ChatViewModel] Loading STT model (\(sttEngineType.rawValue))...")
                try await currentSTTEngine.loadModel(progressHandler: nil)
                isSTTLoaded = true
                print("[ChatViewModel] STT model loaded!")
            }
            
            // Load TTS model only if not already loaded
            if !isTTSLoaded {
                print("[ChatViewModel] Loading TTS model...")
                try await ttsEngine.loadModel()
                isTTSLoaded = true
                print("[ChatViewModel] TTS model loaded!")
            }
            
        } catch {
            print("[ChatViewModel] ERROR loading models: \(error)")
            self.error = error
        }
        
        isLoadingModels = false
        print("[ChatViewModel] loadModels() finished - STT: \(isSTTLoaded), TTS: \(isTTSLoaded)")
    }
    
    /// Skip model loading and go to text-only mode
    func skipModelLoading() {
        isLoadingModels = false
        // Voice features will be disabled but text chat works
    }
    
    // MARK: - Voice Input
    
    func startRecording() {
        do {
            try voiceInputManager.startRecording(mode: voiceMode)
        } catch {
            self.error = error
        }
    }
    
    func stopRecording() {
        voiceInputManager.stopRecording()
    }
    
    /// Check if VAD is actively listening
    var isHandsfreeMode: Bool {
        vadEngine.state == .listening || vadEngine.state == .speaking
    }
    
    /// Start handsfree listening (idempotent - safe to call multiple times)
    func startHandsfreeListening() {
        print("[ChatViewModel] startHandsfreeListening() - vadEngine.state: \(vadEngine.state)")
        guard vadEngine.state == .idle else {
            print("[ChatViewModel] Already listening, skipping")
            return
        }
        
        // Set voice mode to handsfree so VAD restarts after TTS
        voiceMode = .handsfree
        print("[ChatViewModel] Set voiceMode = .handsfree")
        
        do {
            print("[ChatViewModel] Calling vadEngine.startListening()...")
            try vadEngine.startListening()
            print("[ChatViewModel] vadEngine.startListening() succeeded")
        } catch {
            print("[ChatViewModel] vadEngine.startListening() FAILED: \(error)")
            self.error = error
        }
    }
    
    /// Stop handsfree listening
    func stopHandsfreeListening() {
        print("[ChatViewModel] stopHandsfreeListening() - vadEngine.state: \(vadEngine.state)")
        guard vadEngine.state != .idle else {
            print("[ChatViewModel] Already idle, skipping")
            return
        }
        vadEngine.stopListening()
        
        // Reset voice mode when explicitly stopping (not when pausing for TTS)
        voiceMode = .pushToTalk
        print("[ChatViewModel] Reset voiceMode = .pushToTalk")
    }
    
    /// Toggle handsfree listening (legacy - prefer start/stop for clarity)
    func toggleHandsfreeListening() {
        print("[ChatViewModel] toggleHandsfreeListening() - vadEngine.state: \(vadEngine.state)")
        if vadEngine.state == .idle {
            startHandsfreeListening()
        } else {
            stopHandsfreeListening()
        }
    }
    
    private func handleVoiceInput(audioURL: URL) async {
        print("[ChatViewModel] 📥 handleVoiceInput called with: \(audioURL.lastPathComponent)")
        
        // Verify file exists and has content
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
              let size = attrs[.size] as? Int64 else {
            print("[ChatViewModel] ❌ Cannot read audio file attributes!")
            return
        }
        
        print("[ChatViewModel] 📁 Audio file size: \(size) bytes")
        
        // Minimum size check: WAV header (44 bytes) + some audio data
        // Lower threshold to allow short messages (even "yes" or "no")
        let minSize: Int64 = 1_000  // 1KB minimum - just needs header + minimal audio
        if size < minSize {
            print("[ChatViewModel] ❌ Audio file too small (\(size) bytes < \(minSize) min) - likely empty/corrupted")
            cleanupTempAudioFile(audioURL)
            return
        }
        
        // Auto-load STT if not loaded (fixes race condition)
        if !isSTTLoaded {
            print("[ChatViewModel] ⚠️ STT not loaded - loading now (\(sttEngineType.rawValue))...")
            do {
                try await currentSTTEngine.loadModel(progressHandler: nil)
                isSTTLoaded = true
                print("[ChatViewModel] ✅ STT model loaded on-demand!")
            } catch {
                print("[ChatViewModel] ❌ Failed to load STT: \(error)")
                self.error = error
                return
            }
        }
        
        isTranscribing = true
        
        do {
            // Always transcribe the audio first
            let text = try await currentSTTEngine.transcribe(audioURL: audioURL)
            isTranscribing = false
            
            // FaceTime mode: send transcribed text with image
            if voiceMode == .facetime, let imageData = pendingImageData {
                pendingImageData = nil
                // If user said something, use it. Otherwise use generic prompt
                let prompt = text.isEmpty ? "What do you see? Describe this." : text
                print("[FaceTime] Sending image with transcribed: \(prompt.prefix(50))...")
                await sendMessageWithImageData(text: prompt, imageData: imageData, audioURL: audioURL)
                return
            }
            
            guard !text.isEmpty else {
                // Empty transcription - clean up the file since it won't be used
                cleanupTempAudioFile(audioURL)
                return
            }
            
            // Regular mode: send as message WITH audio URL for replay
            await sendMessage(text: text, audioURL: audioURL)
            
        } catch {
            self.error = error
            isTranscribing = false
        }
    }
    
    /// Delete temporary audio files (only for orphaned/unused files)
    private func cleanupTempAudioFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("[ChatViewModel] 🗑️ Cleaned up unused audio: \(url.lastPathComponent)")
        } catch {
            print("[ChatViewModel] ⚠️ Failed to delete audio: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Chat
    
    func sendMessage(text: String, audioURL: URL? = nil) async {
        guard !text.isEmpty else { return }
        currentThinking = ""
        
        // Check if we have a pending image from FaceTime mode
        if let imageData = pendingImageData {
            pendingImageData = nil // Clear it
            await sendMessageWithImageData(text: text, imageData: imageData, audioURL: audioURL)
            return
        }
        
        let conversationID = currentConversation?.id ?? UUID()
        
        // Create user message
        let userMessage = Message(
            role: .user,
            content: text,
            audioURL: audioURL,
            conversationID: conversationID
        )
        messages.append(userMessage)
        
        // Create placeholder for assistant response
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            conversationID: conversationID
        )
        messages.append(assistantMessage)
        
        isGenerating = true
        streamingResponse = ""
        
        do {
            // Build chat messages for API
            let chatMessages = messages.dropLast().map { msg in
                ChatMessage(role: msg.role, content: msg.content)
            }
            
            // Stream response - collect full text first
            let stream = try await outlierClient.chat(messages: Array(chatMessages), model: currentModel)
            var thinkingResponse = ""
            
            for try await chunk in stream {
                // Check for thinking content (marked with special prefix)
                if chunk.hasPrefix("🧠THINKING🧠") {
                    let thinkingChunk = String(chunk.dropFirst("🧠THINKING🧠".count))
                    thinkingResponse += thinkingChunk
                    // Update thinking in message AND direct observable
                    if let index = messages.indices.last {
                        messages[index].thinkingContent = thinkingResponse
                        print("[ChatViewModel] 🧠 STORED thinking in message[\(index)]: \(thinkingResponse.count) chars")
                    }
                    currentThinking = thinkingResponse  // Direct observable for UI
                    refreshTrigger += 1
                    print("[ChatViewModel] 🧠 Thinking chunk received: '\(thinkingChunk.prefix(30))...'")
                } else {
                    streamingResponse += chunk
                    // Update last message in real-time
                    if let index = messages.indices.last {
                        messages[index].content = streamingResponse
                    }
                }
            }
            
            // Log final thinking state
            if !thinkingResponse.isEmpty {
                print("[ChatViewModel] 🧠 Final thinking: \(thinkingResponse.prefix(100))...")
                refreshTrigger += 1  // Final refresh
            }
            currentThinking = ""
            
            isGenerating = false
            
            // Speak the COMPLETE response once, after streaming is done (NOT the thinking!)
            if isTTSLoaded && !streamingResponse.isEmpty {
                await speakResponse(streamingResponse)
            }
            
        } catch {
            self.error = error
            isGenerating = false
            currentThinking = ""
            // Remove placeholder on error
            if messages.last?.content.isEmpty == true {
                messages.removeLast()
            }
        }
    }
    
    /// Send message with raw image data (from FaceTime mode camera capture)
    func sendMessageWithImageData(text: String, imageData: Data, audioURL: URL? = nil) async {
        currentThinking = ""
        let conversationID = currentConversation?.id ?? UUID()
        
        // Create user message with camera snapshot indicator
        let fullText = "📸 \(text)"
        
        let userMessage = Message(
            role: .user,
            content: fullText,
            audioURL: audioURL,
            conversationID: conversationID
        )
        messages.append(userMessage)
        
        // Create placeholder for assistant response
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            conversationID: conversationID
        )
        messages.append(assistantMessage)
        
        isGenerating = true
        streamingResponse = ""
        
        do {
            // Upload image to CDS
            let fileName = "snapshot_\(Int(Date().timeIntervalSince1970)).jpg"
            let imageUrl = try await outlierClient.uploadImage(data: imageData, fileName: fileName)
            print("[FaceTime] Uploaded snapshot: \(imageUrl)")
            
            // Send message with image
            let stream = try await outlierClient.chatWithImages(
                prompt: text,
                imageUrls: [(url: imageUrl, mimeType: "image/jpeg", name: fileName)],
                model: currentModel
            )
            
            var thinkingResponse = ""
            
            for try await chunk in stream {
                // Check for thinking content (marked with special prefix)
                if chunk.hasPrefix("🧠THINKING🧠") {
                    let thinkingChunk = String(chunk.dropFirst("🧠THINKING🧠".count))
                    thinkingResponse += thinkingChunk
                    // Update thinking in message - force SwiftUI update
                    if let index = messages.indices.last {
                        let msg = messages[index]
                        msg.thinkingContent = thinkingResponse
                        messages[index] = msg
                        print("[ChatViewModel] 🧠 Image thinking updated: \(thinkingResponse.count) chars")
                    }
                } else {
                    streamingResponse += chunk
                    if let index = messages.indices.last {
                        messages[index].content = streamingResponse
                    }
                }
            }
            
            // Final update with thinking - FORCE array mutation for SwiftUI
            if !thinkingResponse.isEmpty {
                print("[ChatViewModel] 🧠 Image final thinking: \(thinkingResponse.prefix(100))...")
                if let index = messages.indices.last {
                    let msg = messages[index]
                    msg.thinkingContent = thinkingResponse
                    messages[index] = msg
                }
            }
            currentThinking = ""
            
            isGenerating = false
            
            // Speak the response
            if isTTSLoaded && !streamingResponse.isEmpty {
                await speakResponse(streamingResponse)
            }
            
        } catch {
            self.error = error
            isGenerating = false
            currentThinking = ""
            print("[FaceTime] Error sending with image: \(error)")
            if messages.last?.content.isEmpty == true {
                messages.removeLast()
            }
        }
    }
    
    /// Pause VAD before speaking (call once at start of speech queue)
    private func pauseVADForSpeaking() async {
        if vadEngine.state != .idle {
            print("[ChatViewModel] ⏸️ Pausing VAD for TTS playback")
            vadEngine.stopListening()
        }
    }
    
    /// Speak text without VAD management (used by speech queue)
    private func speakText(_ text: String) async {
        isPlaying = true
        
        do {
            try await ttsEngine.speakAndPlay(text: text)
        } catch {
            self.error = error
            print("[ChatViewModel] TTS error: \(error)")
        }
        
        isPlaying = false
    }
    
    /// Restart VAD after all speech is done (call once at end of speech queue)
    private func restartVADAfterSpeaking() async {
        guard voiceMode == .handsfree || voiceMode == .facetime else { return }
        
        // Reconfigure audio session for recording
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[ChatViewModel] ⚠️ Audio session reconfiguration failed: \(error)")
        }
        
        // Small delay before listening again
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        print("[ChatViewModel] 🎙️ Restarting VAD after TTS")
        do {
            try vadEngine.startListening()
            print("[ChatViewModel] ✅ VAD restarted, state: \(vadEngine.state)")
        } catch {
            print("[ChatViewModel] ❌ VAD restart failed: \(error)")
            self.error = error
        }
    }
    
    /// Legacy method for single-response speaking (used by image messages)
    private func speakResponse(_ text: String) async {
        await pauseVADForSpeaking()
        await speakText(text)
        await restartVADAfterSpeaking()
    }
    
    // MARK: - Send with Images
    
    func sendMessageWithImages(text: String, images: [PlatformImage]) async {
        print("[ChatViewModel] sendMessageWithImages called with \(images.count) images, text: \(text.prefix(50))")
        currentThinking = ""
        
        let conversationID = currentConversation?.id ?? UUID()
        
        // Create user message with image indicator
        let imageText = images.count == 1 ? "[1 image]" : "[\(images.count) images]"
        let fullText = text.isEmpty ? imageText : "\(imageText) \(text)"
        
        let userMessage = Message(
            role: .user,
            content: fullText,
            conversationID: conversationID
        )
        messages.append(userMessage)
        
        // Create placeholder for assistant response
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            conversationID: conversationID
        )
        messages.append(assistantMessage)
        
        isGenerating = true
        streamingResponse = ""
        
        do {
            // Upload images to CDS and get URLs
            var imageUrls: [(url: String, mimeType: String, name: String)] = []
            
            for (index, image) in images.enumerated() {
                #if canImport(UIKit)
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let fileName = "image_\(index + 1).jpg"
                    let url = try await outlierClient.uploadImage(data: data, fileName: fileName)
                    imageUrls.append((url: url, mimeType: "image/jpeg", name: fileName))
                }
                #elseif canImport(AppKit)
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                    let fileName = "image_\(index + 1).jpg"
                    let url = try await outlierClient.uploadImage(data: data, fileName: fileName)
                    imageUrls.append((url: url, mimeType: "image/jpeg", name: fileName))
                }
                #endif
            }
            
            // Send message with images
            let prompt = text.isEmpty ? "Describe this image" : text
            let stream = try await outlierClient.chatWithImages(
                prompt: prompt,
                imageUrls: imageUrls,
                model: currentModel
            )
            
            var thinkingResponse = ""
            
            for try await chunk in stream {
                // Check for thinking content (marked with special prefix)
                if chunk.hasPrefix("🧠THINKING🧠") {
                    let thinkingChunk = String(chunk.dropFirst("🧠THINKING🧠".count))
                    thinkingResponse += thinkingChunk
                    // Update thinking in message - force SwiftUI update
                    if let index = messages.indices.last {
                        let msg = messages[index]
                        msg.thinkingContent = thinkingResponse
                        messages[index] = msg
                        print("[ChatViewModel] 🧠 Gallery thinking updated: \(thinkingResponse.count) chars")
                    }
                } else {
                    streamingResponse += chunk
                    if let index = messages.indices.last {
                        messages[index].content = streamingResponse
                    }
                }
            }
            
            // Final update with thinking - FORCE array mutation for SwiftUI
            if !thinkingResponse.isEmpty {
                print("[ChatViewModel] 🧠 Gallery final thinking: \(thinkingResponse.prefix(100))...")
                if let index = messages.indices.last {
                    let msg = messages[index]
                    msg.thinkingContent = thinkingResponse
                    messages[index] = msg
                }
            }
            currentThinking = ""
            
            isGenerating = false
            
            // Speak the response
            if isTTSLoaded && !streamingResponse.isEmpty {
                await speakResponse(streamingResponse)
            }
            
        } catch {
            self.error = error
            isGenerating = false
            currentThinking = ""
            if messages.last?.content.isEmpty == true {
                messages.removeLast()
            }
        }
    }
    
    // MARK: - Audio Replay
    
    func replayAudio(for message: Message) async {
        guard message.role == .assistant && !message.content.isEmpty else { return }
        
        isPlaying = true
        
        do {
            try await ttsEngine.speakAndPlay(text: message.content)
        } catch {
            self.error = error
        }
        
        isPlaying = false
    }
    
    // MARK: - Conversation Management
    
    func newConversation() {
        currentConversation = nil
        messages = []
        streamingResponse = ""
    }
    
    func loadConversation(_ conversation: Conversation) {
        currentConversation = conversation
        messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
        currentModel = LLMModel(rawValue: conversation.modelUsed) ?? .opus45
    }
    
    /// Load a conversation from Outlier API
    func loadRemoteConversation(_ remoteConv: OutlierConversation) {
        // Set the conversation ID in the client
        Task {
            await outlierClient.setCurrentConversationId(remoteConv.id)
            
            // Clear current messages
            messages = []
            currentConversation = nil
            streamingResponse = ""
            
            // Load turns from API
            do {
                let turns = try await outlierClient.fetchConversationMessages(convId: remoteConv.id)
                
                // Use a consistent UUID for this remote conversation (based on conversation ID)
                let remoteConvUUID = UUID(uuidString: String(remoteConv.id.prefix(36))) ?? UUID()
                
                // Convert turns to Message objects
                // Each turn has: prompt.text (user) and responses[0].text OR response.text (assistant)
                for turn in turns {
                    // User message from prompt.text
                    if let prompt = turn["prompt"] as? [String: Any],
                       let text = prompt["text"] as? String,
                       !text.isEmpty {
                        let userMessage = Message(
                            role: .user,
                            content: text,
                            timestamp: Date(),
                            conversationID: remoteConvUUID
                        )
                        messages.append(userMessage)
                    }
                    
                    // Assistant response - try responses[0].text first, then response.text
                    // Also extract thinking content if present
                    var responseText: String?
                    var thinkingText: String?
                    
                    if let responses = turn["responses"] as? [[String: Any]],
                       let firstResponse = responses.first {
                        responseText = firstResponse["text"] as? String
                        // Extract thinking - it's nested: thinkingContent.thinking
                        if let thinkingObj = firstResponse["thinkingContent"] as? [String: Any] {
                            thinkingText = thinkingObj["thinking"] as? String
                        }
                    } else if let response = turn["response"] as? [String: Any] {
                        responseText = response["text"] as? String
                        if let thinkingObj = response["thinkingContent"] as? [String: Any] {
                            thinkingText = thinkingObj["thinking"] as? String
                        }
                    }
                    
                    if let text = responseText, !text.isEmpty {
                        let assistantMessage = Message(
                            role: .assistant,
                            content: text,
                            thinkingContent: thinkingText,
                            timestamp: Date(),
                            conversationID: remoteConvUUID
                        )
                        messages.append(assistantMessage)
                        
                        if let thinking = thinkingText, !thinking.isEmpty {
                            print("[ChatViewModel] 🧠 Loaded thinking for message: \(thinking.prefix(50))...")
                        }
                    }
                }
                
                print("[ChatViewModel] Loaded \(messages.count) messages from \(turns.count) turns")
            } catch {
                self.error = error
                print("[ChatViewModel] Error loading remote conversation: \(error)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    func stopAll() {
        vadEngine.stopListening()
        voiceInputManager.stopRecording()
        ttsEngine.stopPlayback()
    }
}
