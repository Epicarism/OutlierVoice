import SwiftUI
import AVFoundation

/// Voice selection options
enum VoiceSelection: String, CaseIterable, Identifiable {
    case conversationalA = "conversational_a"
    case conversationalB = "conversational_b"
    case systemVoice = "system"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .conversationalA: return "Claude A (Neural)"
        case .conversationalB: return "Claude B (Neural)"
        case .systemVoice: return "System Voice (Fast)"
        }
    }
    
    var icon: String {
        switch self {
        case .conversationalA, .conversationalB: return "brain"
        case .systemVoice: return "speaker.wave.2"
        }
    }
}

/// TTS Quality levels
enum TTSQualitySelection: Int, CaseIterable, Identifiable {
    case fast = 8
    case balanced = 16
    case quality = 24
    case maximum = 32
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .fast: return "Fast (8)"
        case .balanced: return "Balanced (16)"
        case .quality: return "Quality (24)"
        case .maximum: return "Maximum (32)"
        }
    }
    
    var description: String {
        switch self {
        case .fast: return "Fastest generation, good quality"
        case .balanced: return "Good balance of speed & quality"
        case .quality: return "High quality, slower"
        case .maximum: return "Best quality, slowest"
        }
    }
}

/// App settings view
struct SettingsView: View {
    @AppStorage("vadSensitivity") private var vadSensitivity: Double = 0.02
    @AppStorage("silenceDuration") private var silenceDuration: Double = 1.5
    @AppStorage("autoSpeak") private var autoSpeak = true
    
    // TTS Settings
    @AppStorage("selectedVoice") private var selectedVoice: String = VoiceSelection.conversationalA.rawValue
    @AppStorage("selectedLanguage") private var selectedLanguage: String = VoiceLanguage.default.rawValue
    @AppStorage("selectedKokoroVoice") private var selectedKokoroVoice: String = KokoroVoice.default.rawValue
    @AppStorage("ttsQuality") private var ttsQuality: Int = TTSQualitySelection.fast.rawValue
    @AppStorage("playbackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("useSystemVoiceFallback") private var useSystemVoiceFallback = true
    
    // AI Settings
    @AppStorage("enableThinking") private var enableThinking = false
    
    @State private var showLogin = false
    @State private var isLoggedIn = false
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var showVoiceCloneSheet = false
    
    private let outlierClient = OutlierClient()
    
    enum ConnectionStatus: Equatable {
        case unknown, checking, success, failed(String)
    }
    
    /// Voices filtered by selected language
    private var voicesForSelectedLanguage: [KokoroVoice] {
        guard let language = VoiceLanguage(rawValue: selectedLanguage) else {
            return KokoroVoice.voices(for: .americanEnglish)
        }
        return KokoroVoice.voices(for: language)
    }
    
    var body: some View {
        Form {
            // Authentication Section
            Section {
                if isLoggedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Connected to Outlier")
                                .font(.headline)
                            Text("Ready to chat and view history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button(role: .destructive) {
                        logout()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Not Connected")
                                .font(.headline)
                            Text("Login to access chat and history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button {
                        showLogin = true
                    } label: {
                        Label("Login to Outlier", systemImage: "person.circle")
                    }
                }
            } header: {
                Text("Account")
            }
            
            // Voice Input Settings Section
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("VAD Sensitivity")
                        Spacer()
                        Text(String(format: "%.3f", vadSensitivity))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $vadSensitivity, in: 0.005...0.1, step: 0.005)
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Silence Duration")
                        Spacer()
                        Text(String(format: "%.1fs", silenceDuration))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $silenceDuration, in: 0.5...3.0, step: 0.5)
                }
            } header: {
                Text("Voice Input (STT)")
            } footer: {
                Text("VAD = Voice Activity Detection. Higher sensitivity means quieter sounds trigger recording.")
            }
            
            // TTS Settings Section
            Section {
                Toggle("Auto-speak responses", isOn: $autoSpeak)
                
                Toggle("Use Kokoro Neural Voice", isOn: Binding(
                    get: { !useSystemVoiceFallback },
                    set: { useSystemVoiceFallback = !$0 }
                ))
                
                if !useSystemVoiceFallback {
                    // Language Picker
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(VoiceLanguage.allCases) { language in
                            Text(language.displayName)
                                .tag(language.rawValue)
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newLanguage in
                        // Auto-select first voice for new language
                        if let lang = VoiceLanguage(rawValue: newLanguage) {
                            let voices = KokoroVoice.voices(for: lang)
                            if let firstVoice = voices.first {
                                selectedKokoroVoice = firstVoice.rawValue
                            }
                        }
                    }
                    
                    // Voice Picker (filtered by language)
                    Picker("Voice", selection: $selectedKokoroVoice) {
                        ForEach(voicesForSelectedLanguage) { voice in
                            Text(voice.displayName)
                                .tag(voice.rawValue)
                        }
                    }
                    
                    // Quality Level
                    Picker("Quality", selection: $ttsQuality) {
                        ForEach(TTSQualitySelection.allCases) { quality in
                            Text(quality.displayName)
                                .tag(quality.rawValue)
                        }
                    }
                    
                    // Playback Speed
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Playback Speed")
                            Spacer()
                            Text(String(format: "%.1fx", playbackSpeed))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $playbackSpeed, in: 0.5...2.0, step: 0.1)
                    }
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Kokoro uses ~1.5GB RAM. May crash on older devices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // System voice fallback - simple picker
                    Picker("Voice", selection: $selectedVoice) {
                        ForEach(VoiceSelection.allCases) { voice in
                            HStack {
                                Image(systemName: voice.icon)
                                Text(voice.displayName)
                            }
                            .tag(voice.rawValue)
                        }
                    }
                }
                
                // Voice Clone Button
                Button {
                    showVoiceCloneSheet = true
                } label: {
                    HStack {
                        Image(systemName: "waveform.badge.plus")
                        Text("Clone a Voice")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Voice Output (TTS)")
            } footer: {
                Text("Neural voices sound more natural but are slower. System voice is instant. Lower quality = faster generation.")
            }
            
            // AI Settings Section
            Section {
                Toggle("Enable Extended Thinking", isOn: $enableThinking)
                
                if enableThinking {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.purple)
                        Text("Claude will think deeply before responding. Adds 5-15s latency.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Toggle("Show Thinking in Chat", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "showThinkingInChat") },
                        set: { UserDefaults.standard.set($0, forKey: "showThinkingInChat") }
                    ))
                    
                    HStack {
                        Image(systemName: "eye")
                            .foregroundStyle(.blue)
                        Text("Display Claude's thinking process in message bubbles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.green)
                        Text("Fast mode - instant responses, best for voice chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("AI Settings")
            } footer: {
                Text("Extended thinking improves reasoning but adds latency. Disable for faster voice conversations.")
            }
            
            // Models Section
            Section {
                ModelInfoRow(
                    name: "Whisper",
                    description: "Speech-to-Text (On-Device)",
                    icon: "waveform",
                    color: .blue
                )
                ModelInfoRow(
                    name: "Kokoro TTS",
                    description: "Text-to-Speech (On-Device)",
                    icon: "speaker.wave.2",
                    color: .purple
                )
            } header: {
                Text("ML Models")
            } footer: {
                Text("Models run locally on your device using Apple MLX.")
            }
            
            // About Section
            Section {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "2026.02")
                
                Link(destination: URL(string: "https://github.com/Blaizzy/mlx-audio-swift")!) {
                    HStack {
                        Label("MLX Audio Swift", systemImage: "link")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showLogin) {
            OutlierLoginView { cookie, csrf in
                Task {
                    await outlierClient.setCredentials(cookie: cookie, csrf: csrf)
                    await checkLoginStatus()
                }
            }
        }
        .sheet(isPresented: $showVoiceCloneSheet) {
            VoiceCloneSheet()
        }
        .task {
            await checkLoginStatus()
        }
    }
    
    private func checkLoginStatus() async {
        isLoggedIn = await outlierClient.isAuthenticated()
    }
    
    private func logout() {
        Task {
            await outlierClient.clearCredentials()
            await checkLoginStatus()
        }
    }
}

/// Model info row
struct ModelInfoRow: View {
    let name: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Voice Clone Sheet

struct VoiceCloneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var referenceText = ""
    @State private var isRecording = false
    @State private var recordedURL: URL?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var voiceName = ""
    @State private var showingFilePicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Voice cloning lets Claude speak in any voice! You need:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("A 24kHz mono WAV audio file", systemImage: "waveform")
                        Label("The exact text spoken in the audio", systemImage: "text.quote")
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                } header: {
                    Text("How it works")
                }
                
                Section {
                    TextField("Voice Name", text: $voiceName)
                        .textContentType(.name)
                    
                    // Record or Upload
                    if recordedURL == nil {
                        Button {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        } label: {
                            HStack {
                                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .foregroundStyle(isRecording ? .red : .blue)
                                    .font(.title2)
                                Text(isRecording ? "Stop Recording" : "Record Sample")
                            }
                        }
                        
                        Button {
                            showingFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .font(.title2)
                                Text("Import WAV File")
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Audio recorded")
                            Spacer()
                            Button("Clear") {
                                recordedURL = nil
                            }
                            .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Voice Sample")
                }
                
                Section {
                    TextField("Enter the exact words spoken...", text: $referenceText, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Reference Text")
                } footer: {
                    Text("This MUST match exactly what was said in the audio sample.")
                }
                
                Section {
                    Button {
                        saveVoiceClone()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save Voice")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(voiceName.isEmpty || recordedURL == nil || referenceText.isEmpty)
                }
            }
            .navigationTitle("Clone Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("voice_clone_\(Date().timeIntervalSince1970).wav")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 24000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        recordedURL = audioRecorder?.url
        isRecording = false
        audioRecorder = nil
    }
    
    private func saveVoiceClone() {
        guard let url = recordedURL else { return }
        
        // Save voice clone info to UserDefaults
        var clonedVoices = UserDefaults.standard.dictionary(forKey: "clonedVoices") as? [String: [String: String]] ?? [:]
        
        clonedVoices[voiceName] = [
            "audioPath": url.path,
            "referenceText": referenceText
        ]
        
        UserDefaults.standard.set(clonedVoices, forKey: "clonedVoices")
        
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

#Preview("Voice Clone") {
    VoiceCloneSheet()
}
