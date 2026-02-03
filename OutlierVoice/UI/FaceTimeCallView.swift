import SwiftUI
import AVFoundation
import CallKit

/// FaceTime-style video call with Claude - sends camera snapshot with each message
struct FaceTimeCallView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    let callManager = CallManager.shared
    let callKitManager = CallKitManager.shared
    @State private var cameraManager = CameraManager()
    @State private var isConnecting = true
    @State private var isMuted = false
    @State private var isUsingFrontCamera = true
    @State private var lastCapturedImage: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background gradient (fallback when camera not ready)
                LinearGradient(
                    colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Full screen camera preview (what Claude "sees")
                if cameraManager.isAuthorized && cameraManager.captureSession?.isRunning == true {
                    CameraPreviewLayer(cameraManager: cameraManager)
                        .ignoresSafeArea()
                }
                
                // Gradient overlay at top and bottom
                VStack {
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                    
                    Spacer()
                    
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                }
                .ignoresSafeArea()
                
                // Main UI
                VStack {
                    // Top bar
                    topBar
                        .padding(.top, 60)
                    
                    Spacer()
                    
                    // Claude visualization (always visible in center)
                    claudeVisualization
                        .transition(.scale.combined(with: .opacity))
                    
                    Spacer()
                    
                    // Status
                    statusBadge
                        .padding(.bottom, 20)
                    
                    // Bottom controls
                    bottomControls
                        .padding(.bottom, 40)
                }
                
                // Small self-view (picture-in-picture style)
                selfView
                    .position(x: geo.size.width - 70, y: 140)
            }
        }
        .onAppear {
            viewModel.voiceMode = .facetime
            startCall()
        }
        .onDisappear {
            viewModel.voiceMode = .pushToTalk
            // Only end call if not minimized
            if !callManager.isMinimized {
                endCall()
            }
        }
        .onChange(of: viewModel.isRecording) { wasRecording, isRecording in
            // Capture when recording STARTS so image is ready when speech ends
            if !wasRecording && isRecording {
                captureAndSend()
                print("[FaceTime] Captured on recording START")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isPlaying)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isGenerating)
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("FaceTime")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                Text(isConnecting ? "Connecting..." : callManager.formatDuration(callManager.callDuration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Flip camera button
            Button {
                isUsingFrontCamera.toggle()
                cameraManager.switchCamera()
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
    
    // MARK: - Claude Visualization
    
    private var claudeVisualization: some View {
        VStack(spacing: 20) {
            // Animated waveform circle
            ZStack {
                // Outer rings
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 120 + CGFloat(i) * 30, height: 120 + CGFloat(i) * 30)
                        .scaleEffect(viewModel.isPlaying ? 1.0 + CGFloat(viewModel.amplitude) * 0.3 : 1.0)
                        .opacity(viewModel.isPlaying ? 0.8 - Double(i) * 0.2 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.1),
                            value: viewModel.amplitude
                        )
                }
                
                // Center circle with Claude avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    if viewModel.isGenerating {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    } else if viewModel.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    } else {
                        // Claude icon/avatar
                        Text("C")
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            
            // Status text
            Text(claudeStatusText)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(30)
        .background(.ultraThinMaterial.opacity(0.5))
        .cornerRadius(24)
    }
    
    private var claudeStatusText: String {
        if viewModel.isGenerating {
            return "Thinking..."
        } else if viewModel.isPlaying {
            return "Speaking..."
        } else if viewModel.isRecording {
            return "Listening..."
        } else if viewModel.isTranscribing {
            return "Processing..."
        } else {
            return "Claude"
        }
    }
    
    // MARK: - Self View (PiP)
    
    private var selfView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .frame(width: 120, height: 160)
            
            // Show captured image as self-view (more reliable than duplicate preview layer)
            if let image = cameraManager.lastCapturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 116, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .scaleEffect(x: isUsingFrontCamera ? -1 : 1, y: 1)
            } else {
                // Placeholder while camera starts
                VStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("You")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .frame(width: 116, height: 156)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 10)
        .gesture(
            TapGesture().onEnded {
                isUsingFrontCamera.toggle()
                cameraManager.switchCamera()
            }
        )
        .overlay(alignment: .topTrailing) {
            // Camera flip indicator
            Image(systemName: "camera.rotate")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .padding(4)
        }
    }
    
    // MARK: - Status Badge
    
    private var statusBadge: some View {
        HStack(spacing: 8) {
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                Text("Connecting...")
            } else if viewModel.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                Text("Listening...")
            } else if viewModel.isTranscribing {
                Image(systemName: "waveform")
                Text("Processing...")
            } else if viewModel.isGenerating {
                Image(systemName: "brain")
                Text("Thinking...")
            } else if viewModel.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                Text("Speaking...")
            } else {
                Image(systemName: "hand.tap")
                Text("Tap mic to speak")
            }
        }
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5))
        .cornerRadius(25)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Main controls row
            HStack(spacing: 40) {
                // Mute - uses CallKit
                FaceTimeControlButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    isActive: !isMuted
                ) {
                    callKitManager.toggleMute()
                    isMuted = callKitManager.isMuted
                }
                
                // Main mic button - tap to record
                Button {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.white)
                            .frame(width: 80, height: 80)
                        
                        if viewModel.isRecording {
                            // Stop icon
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.title)
                                .foregroundStyle(.black)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10)
                }
                .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
                
                // End call
                FaceTimeControlButton(
                    icon: "phone.down.fill",
                    color: .red,
                    isActive: true
                ) {
                    endCall()
                    isPresented = false
                }
            }
            
            // Minimize button
            Button {
                callManager.minimizeCall()
                isPresented = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Back to Chat")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .cornerRadius(20)
            }
        }
    }
    
    // MARK: - Logic
    
    private func startCall() {
        print("[FaceTime] startCall()")
        
        // Start CallKit (provides native call UI, lock screen, audio routing)
        if !callKitManager.isCallActive {
            callKitManager.startCall()
        }
        
        // Also start legacy call manager (handles timer)
        if !callManager.isInCall {
            callManager.startCall(type: .facetime)
        }
        
        Task {
            print("[FaceTime] Task started")
            
            // Check camera authorization first
            print("[FaceTime] Checking camera authorization...")
            if !cameraManager.isAuthorized {
                cameraManager.checkAuthorization()
                // Wait a moment for authorization
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            // Start camera if authorized
            if cameraManager.isAuthorized {
                print("[FaceTime] Camera authorized, starting session...")
                cameraManager.startSession()
            } else {
                print("[FaceTime] Camera NOT authorized!")
            }
            
            // Load AI models
            if !viewModel.isSTTLoaded || !viewModel.isTTSLoaded {
                print("[FaceTime] Loading models...")
                await viewModel.loadModels()
                print("[FaceTime] Models loaded")
            }
            
            print("[FaceTime] Waiting 1s...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            print("[FaceTime] Setting isConnecting = false")
            withAnimation {
                isConnecting = false
            }
            print("[FaceTime] startCall complete - camera running: \(cameraManager.captureSession?.isRunning ?? false)")
        }
    }
    
    private func captureAndSend() {
        guard !isConnecting else { return }
        
        // Capture current frame from video buffer
        if let image = cameraManager.captureSnapshot(),
           let imageData = image.jpegData(compressionQuality: 0.7) {
            viewModel.pendingImageData = imageData
            print("[FaceTime] Captured snapshot (\(imageData.count) bytes)")
        }
    }
    
    private func endCall() {
        print("[FaceTime] endCall()")
        callKitManager.endCall()  // End CallKit call
        callManager.endCall()      // End legacy manager (timer)
        cameraManager.stopSession()
        viewModel.stopAll()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - FaceTime Control Button

struct FaceTimeControlButton: View {
    let icon: String
    var color: Color = .white
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color == .red ? Color.red : (isActive ? Color.white.opacity(0.3) : Color.white.opacity(0.15)))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Camera Preview Layer

struct CameraPreviewLayer: UIViewRepresentable {
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove old preview layer if exists
        uiView.layer.sublayers?.removeAll(where: { $0 is AVCaptureVideoPreviewLayer })
        
        // Add new preview layer if session is available
        if let session = cameraManager.captureSession {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = uiView.bounds
            uiView.layer.addSublayer(previewLayer)
        }
    }
}
