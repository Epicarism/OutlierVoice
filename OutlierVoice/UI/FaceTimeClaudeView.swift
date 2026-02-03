import SwiftUI
import AVFoundation

// MARK: - FaceTime Claude View

struct FaceTimeClaudeView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var cameraManager = CameraManager()
    @State private var callDuration: TimeInterval = 0
    @State private var showControls = true
    @State private var lastSnapshotTime: Date?
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full screen camera preview (Claude's "view")
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea()
                
                // Dark overlay when Claude is speaking
                if viewModel.isPlaying {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                // Main UI overlay
                VStack {
                    // Top bar
                    topBar
                        .padding(.top, 60)
                    
                    Spacer()
                    
                    // Claude avatar (shows when speaking)
                    if viewModel.isPlaying || viewModel.isGenerating {
                        claudeOverlay
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    statusIndicator
                        .padding(.bottom, 20)
                    
                    // Bottom controls
                    bottomControls
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            cameraManager.startSession()
            startAutoCapture()
            // Auto-load STT/TTS models if not loaded
            if !viewModel.isSTTLoaded {
                Task {
                    await viewModel.loadModels()
                }
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onReceive(timer) { _ in
            callDuration += 1
            checkAutoSnapshot()
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isPlaying)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isGenerating)
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Duration
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("FaceTime with Claude")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Text(formatDuration(callDuration))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            }
            
            Spacer()
            
            // Camera flip button
            Button {
                withAnimation {
                    cameraManager.switchCamera()
                }
            } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Claude Overlay
    
    private var claudeOverlay: some View {
        VStack(spacing: 16) {
            // Beautiful animated Claude avatar
            ClaudeAvatarView(
                isThinking: viewModel.isGenerating,
                isSpeaking: viewModel.isPlaying,
                amplitude: viewModel.amplitude
            )
            
            // Status text
            if viewModel.isGenerating {
                Text("Thinking...")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            } else if viewModel.isPlaying {
                Text("Speaking...")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(30)
        .background(.ultraThinMaterial.opacity(0.6))
        .cornerRadius(24)
    }
    
    // MARK: - Status Indicator
    
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            if viewModel.isLoadingModels {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading voice models...")
            } else if !viewModel.isSTTLoaded {
                Image(systemName: "exclamationmark.triangle")
                Text("Voice not ready")
            } else if viewModel.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                Text("Listening...")
            } else if viewModel.isTranscribing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Processing...")
            } else if viewModel.isGenerating {
                Image(systemName: "brain")
                Text("Thinking...")
            } else if viewModel.isPlaying {
                Image(systemName: "waveform")
                Text("Speaking...")
            } else {
                Image(systemName: "hand.tap")
                Text("Tap to speak")
            }
        }
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Mute (placeholder)
            Button {
                // Toggle mute
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                    Text("Mute")
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
            
            // Main action button - Push to talk
            Button {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    captureAndStartRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.white)
                        .frame(width: 80, height: 80)
                    
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.black)
                    }
                }
            }
            .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
            
            // End call
            Button {
                viewModel.stopAll()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Color.red)
                        .clipShape(Circle())
                    Text("End")
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
        }
    }
    
    // MARK: - Auto Capture
    
    private func startAutoCapture() {
        // Start camera session
        cameraManager.startSession()
    }
    
    private func checkAutoSnapshot() {
        // Auto-capture every 5 seconds while recording
        if viewModel.isRecording {
            if let last = lastSnapshotTime {
                if Date().timeIntervalSince(last) > 5 {
                    captureSnapshot()
                }
            }
        }
    }
    
    private func captureAndStartRecording() {
        // Capture snapshot first
        captureSnapshot()
        
        // Then start recording
        viewModel.startRecording()
    }
    
    private func captureSnapshot() {
        lastSnapshotTime = Date()
        
        if let image = cameraManager.captureSnapshot() {
            print("[FaceTime] Captured snapshot")
            
            // Compress and prepare for upload
            if let data = image.jpegData(compressionQuality: 0.7) {
                // Store for sending with next message
                viewModel.pendingImageData = data
                print("[FaceTime] Snapshot ready: \(data.count / 1024)KB")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    FaceTimeClaudeView(viewModel: ChatViewModel())
}
