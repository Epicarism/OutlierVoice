import SwiftUI
import AVFoundation
import CallKit

/// Voice call view - like a WhatsApp phone call with Claude
struct VoiceCallView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    let callManager = CallManager.shared
    let callKitManager = CallKitManager.shared
    @State private var isConnecting = true
    @State private var isMuted = false
    @State private var isSpeakerOn = true
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Claude avatar with waveform
                claudeAvatarSection
                
                Spacer()
                
                // Call status
                callStatusSection
                    .padding(.bottom, 40)
                
                // Control buttons
                controlButtons
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            startCall()
        }
        .onDisappear {
            // Only end call if not minimized
            if !callManager.isMinimized {
                endCall()
            }
        }
    }
    
    // MARK: - Claude Avatar Section
    
    private var claudeAvatarSection: some View {
        VStack(spacing: 24) {
            ZStack {
                // Animated rings when speaking
                if viewModel.isPlaying {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Color.white.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: 160 + CGFloat(i) * 40, height: 160 + CGFloat(i) * 40)
                            .scaleEffect(viewModel.isPlaying ? 1.1 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever()
                                    .delay(Double(i) * 0.2),
                                value: viewModel.isPlaying
                            )
                    }
                }
                
                // Main avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 140, height: 140)
                    
                    Text("🤖")
                        .font(.system(size: 60))
                }
                .shadow(color: Color(hex: "667eea").opacity(0.5), radius: 20)
            }
            
            // Name
            Text("Claude")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            
            // Waveform when speaking
            if viewModel.isPlaying {
                AudioWaveform(amplitude: viewModel.amplitude)
                    .frame(height: 40)
                    .padding(.horizontal, 60)
            }
        }
    }
    
    // MARK: - Call Status
    
    private var callStatusSection: some View {
        VStack(spacing: 8) {
            // Always show duration
            Text(callManager.formatDuration(callManager.callDuration))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            
            // Status indicator
            if isConnecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Connecting...")
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Text("Listening...")
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else if viewModel.isTranscribing {
                Text("Processing speech...")
                    .foregroundStyle(.white.opacity(0.8))
            } else if viewModel.isGenerating {
                Text("Claude is thinking...")
                    .foregroundStyle(.white.opacity(0.8))
            } else if viewModel.isPlaying {
                Text("Claude is speaking...")
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text("Tap to speak or just talk")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 30) {
            // Top row - Mute, End, Speaker
            HStack(spacing: 50) {
                // Mute button - uses CallKit
                CallControlButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    label: "Mute",
                    isActive: isMuted
                ) {
                    callKitManager.toggleMute()
                    isMuted = callKitManager.isMuted
                }
                
                // End call button
                Button {
                    endCall()
                    isPresented = false
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
                
                // Speaker button - uses CallKit audio routing
                CallControlButton(
                    icon: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.slash.fill",
                    label: "Speaker",
                    isActive: isSpeakerOn
                ) {
                    callKitManager.toggleSpeaker()
                    isSpeakerOn = callKitManager.isSpeakerOn
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
    
    // MARK: - Call Logic
    
    private func startCall() {
        print("[VoiceCall] startCall() called")
        
        // Don't restart if VAD is already listening (prevents proximity toggle issues)
        if viewModel.isHandsfreeMode {
            print("[VoiceCall] Already in handsfree mode, skipping restart")
            return
        }
        
        // Start CallKit (provides native call UI, lock screen, audio routing)
        if !callKitManager.isCallActive {
            callKitManager.startCall()
        }
        
        // Also start legacy call manager (handles timer)
        if !callManager.isInCall {
            callManager.startCall(type: .voice)
        }
        
        // Setup CallKit callbacks
        callKitManager.onMuteChanged = { muted in
            self.isMuted = muted
        }
        
        // Load models if needed
        Task {
            print("[VoiceCall] Task started, checking models...")
            if !viewModel.isSTTLoaded || !viewModel.isTTSLoaded {
                print("[VoiceCall] Loading models...")
                await viewModel.loadModels()
            }
            
            print("[VoiceCall] Waiting 1.5s...")
            // Simulate connecting delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            print("[VoiceCall] Setting isConnecting = false")
            withAnimation {
                isConnecting = false
            }
            
            print("[VoiceCall] About to start listening...")
            // Start VAD listening for handsfree conversation (use start, not toggle)
            viewModel.startHandsfreeListening()
            print("[VoiceCall] startHandsfreeListening() completed")
        }
    }
    
    private func startListening() {
        print("[VoiceCall] startListening() - isConnecting: \(isConnecting), isMuted: \(isMuted)")
        guard !isConnecting && !isMuted else { 
            print("[VoiceCall] Skipping - guard failed")
            return 
        }
        
        print("[VoiceCall] Calling toggleHandsfreeListening...")
        // Use handsfree mode for continuous VAD listening
        viewModel.toggleHandsfreeListening()
        print("[VoiceCall] toggleHandsfreeListening returned")
    }
    
    private func endCall() {
        print("[VoiceCall] endCall()")
        callKitManager.endCall()  // End CallKit call
        callManager.endCall()      // End legacy manager (timer)
        viewModel.stopAll()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Call Control Button

struct CallControlButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.white : Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isActive ? .black : .white)
                }
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Audio Waveform

struct AudioWaveform: View {
    let amplitude: Float
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 4)
                        .frame(height: barHeight(for: i, width: geo.size.width))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
    
    private func barHeight(for index: Int, width: CGFloat) -> CGFloat {
        let normalizedAmplitude = CGFloat(min(max(amplitude, 0), 1))
        let phase = animationPhase + CGFloat(index) * 0.3
        let wave = (sin(phase) + 1) / 2
        let height = 10 + (normalizedAmplitude * 30 * wave)
        return max(height, 4)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
