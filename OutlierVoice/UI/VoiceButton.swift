import SwiftUI

/// Large voice input button with visual feedback
struct VoiceButton: View {
    let mode: VoiceMode
    let isRecording: Bool
    let isProcessing: Bool
    let amplitude: Float
    
    let onTapDown: () -> Void
    let onTapUp: () -> Void
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var buttonSize: CGFloat { 80 }
    private var pulseScale: CGFloat {
        isRecording ? 1.0 + CGFloat(amplitude) * 2 : 1.0
    }
    
    var body: some View {
        ZStack {
            // Pulse animation when recording
            if isRecording {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: buttonSize * pulseScale, height: buttonSize * pulseScale)
                    .animation(.easeInOut(duration: 0.1), value: amplitude)
            }
            
            // Main button
            Circle()
                .fill(buttonColor)
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    buttonIcon
                }
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .shadow(color: buttonColor.opacity(0.5), radius: isRecording ? 10 : 5)
        }
        .contentShape(Circle())
        .gesture(pushToTalkGesture, including: mode == .pushToTalk ? .all : .none)
        .gesture(tapGesture, including: mode == .handsfree ? .all : .none)
        .animation(.spring(response: 0.3), value: isRecording)
        .animation(.spring(response: 0.2), value: isPressed)
    }
    
    private var buttonColor: Color {
        if isProcessing {
            return .orange
        } else if isRecording {
            return .red
        } else {
            return .blue
        }
    }
    
    @ViewBuilder
    private var buttonIcon: some View {
        if isProcessing {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
        } else {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
        }
    }
    
    private var pushToTalkGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed {
                    isPressed = true
                    onTapDown()
                }
            }
            .onEnded { _ in
                isPressed = false
                onTapUp()
            }
    }
    
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                onTap()
            }
    }
}

/// Simpler mic button for text input row
struct MicButton: View {
    let isRecording: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(isRecording ? .red : .blue)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        VoiceButton(
            mode: .pushToTalk,
            isRecording: false,
            isProcessing: false,
            amplitude: 0,
            onTapDown: {},
            onTapUp: {},
            onTap: {}
        )
        
        VoiceButton(
            mode: .handsfree,
            isRecording: true,
            isProcessing: false,
            amplitude: 0.3,
            onTapDown: {},
            onTapUp: {},
            onTap: {}
        )
    }
    .padding()
}
