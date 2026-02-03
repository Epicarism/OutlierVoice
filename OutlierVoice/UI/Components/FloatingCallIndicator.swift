import SwiftUI

/// Floating pill showing active call - tap to return to call
struct FloatingCallIndicator: View {
    let callManager = CallManager.shared
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Pulsing dot
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .modifier(PulseModifier())
                
                // Call type icon
                Image(systemName: callManager.callType == .facetime ? "video.fill" : "phone.fill")
                    .font(.subheadline)
                
                // Duration
                Text(callManager.formatDuration(callManager.callDuration))
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.medium)
                
                // Tap to return hint
                Text("Tap to return")
                    .font(.caption)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.green)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

#Preview {
    VStack {
        Spacer()
        FloatingCallIndicator(onTap: {})
            .padding()
    }
    .background(Color.gray.opacity(0.3))
}
