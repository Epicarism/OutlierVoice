import SwiftUI

/// Toggle between Push-to-Talk and Handsfree modes
struct VoiceModeToggle: View {
    @Binding var mode: VoiceMode
    
    var body: some View {
        Picker("Voice Mode", selection: $mode) {
            ForEach(VoiceMode.allCases) { voiceMode in
                Label(voiceMode.rawValue, systemImage: voiceMode.icon)
                    .tag(voiceMode)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Compact toggle for toolbar
struct VoiceModeButton: View {
    @Binding var mode: VoiceMode
    
    var body: some View {
        Button {
            withAnimation {
                mode = mode == .pushToTalk ? .handsfree : .pushToTalk
            }
        } label: {
            Label(mode.rawValue, systemImage: mode.icon)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VoiceModeToggle(mode: .constant(.pushToTalk))
            .padding()
        
        VoiceModeButton(mode: .constant(.handsfree))
    }
}
