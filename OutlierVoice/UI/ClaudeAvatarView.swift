import SwiftUI

/// Animated Claude avatar - a beautiful orb that reacts to speech
struct ClaudeAvatarView: View {
    let isThinking: Bool
    let isSpeaking: Bool
    let amplitude: Float  // 0-1 for voice level
    
    @State private var rotation: Double = 0
    @State private var pulsePhase: Double = 0
    @State private var particlePhase: Double = 0
    
    private let baseSize: CGFloat = 120
    
    var body: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(0.3 - Double(i) * 0.1),
                                Color.blue.opacity(0.2 - Double(i) * 0.05),
                                Color.cyan.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(
                        width: baseSize + CGFloat(i * 30) + (isSpeaking ? CGFloat(amplitude) * 20 : 0),
                        height: baseSize + CGFloat(i * 30) + (isSpeaking ? CGFloat(amplitude) * 20 : 0)
                    )
                    .scaleEffect(1.0 + (isSpeaking ? sin(pulsePhase + Double(i) * 0.5) * 0.05 : 0))
                    .opacity(isSpeaking ? 0.8 : 0.4)
            }
            
            // Particle ring (when speaking)
            if isSpeaking {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .offset(y: -baseSize/2 - 25)
                        .rotationEffect(.degrees(Double(i) * 30 + particlePhase * 60))
                        .scaleEffect(0.5 + CGFloat(amplitude) * 0.5)
                }
            }
            
            // Main orb background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.4, green: 0.3, blue: 0.9),
                            Color(red: 0.2, green: 0.1, blue: 0.6),
                            Color(red: 0.1, green: 0.05, blue: 0.3)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: baseSize
                    )
                )
                .frame(width: baseSize, height: baseSize)
                .shadow(color: .purple.opacity(0.5), radius: isSpeaking ? 30 : 15)
            
            // Animated gradient overlay
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.1),
                            .clear,
                            .cyan.opacity(0.15),
                            .clear
                        ],
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    )
                )
                .frame(width: baseSize, height: baseSize)
            
            // Inner highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.4),
                            .clear
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: baseSize * 0.4
                    )
                )
                .frame(width: baseSize, height: baseSize)
            
            // Center icon/face
            ZStack {
                if isThinking {
                    // Thinking animation - rotating dots
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .offset(x: cos(pulsePhase * 2 + Double(i) * 2.1) * 15,
                                    y: sin(pulsePhase * 2 + Double(i) * 2.1) * 15)
                            .opacity(0.8)
                    }
                } else if isSpeaking {
                    // Speaking animation - audio bars
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: 4, 
                                       height: 10 + CGFloat(sin(pulsePhase * 3 + Double(i) * 0.8)) * 15 * CGFloat(amplitude + 0.3))
                        }
                    }
                } else {
                    // Idle - subtle sparkle
                    Image(systemName: "sparkle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .scaleEffect(1.0 + sin(pulsePhase) * 0.1)
                }
            }
            
            // Waveform ring (when speaking)
            if isSpeaking {
                WaveformRing(amplitude: amplitude, phase: pulsePhase)
                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    .frame(width: baseSize + 60, height: baseSize + 60)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .onChange(of: isSpeaking) { _, speaking in
            if speaking {
                startPulseAnimation()
            }
        }
        .onChange(of: isThinking) { _, thinking in
            if thinking {
                startPulseAnimation()
            }
        }
        .onAppear {
            startPulseAnimation()
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            pulsePhase = .pi * 2
        }
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            particlePhase = 1
        }
    }
}

/// Custom waveform shape that responds to amplitude
struct WaveformRing: Shape {
    let amplitude: Float
    let phase: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        let points = 60
        for i in 0..<points {
            let angle = Double(i) / Double(points) * 2 * .pi
            let waveOffset = sin(angle * 6 + phase * 4) * Double(amplitude) * 8
            let r = radius + waveOffset
            
            let x = center.x + cos(angle) * r
            let y = center.y + sin(angle) * r
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview

#Preview("Idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        ClaudeAvatarView(isThinking: false, isSpeaking: false, amplitude: 0)
    }
}

#Preview("Thinking") {
    ZStack {
        Color.black.ignoresSafeArea()
        ClaudeAvatarView(isThinking: true, isSpeaking: false, amplitude: 0)
    }
}

#Preview("Speaking") {
    ZStack {
        Color.black.ignoresSafeArea()
        ClaudeAvatarView(isThinking: false, isSpeaking: true, amplitude: 0.7)
    }
}
