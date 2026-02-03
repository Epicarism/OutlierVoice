import Foundation
import AVFoundation

/// Manages voice input for both PTT and handsfree modes
@Observable
final class VoiceInputManager {
    private var audioRecorder: AVAudioRecorder?
    private let vadEngine: VADEngine
    private var currentRecordingURL: URL?
    
    private(set) var isRecording = false
    private(set) var currentMode: VoiceMode = .pushToTalk
    
    // Callbacks
    var onRecordingStarted: (() -> Void)?
    var onRecordingFinished: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    
    enum VoiceInputError: LocalizedError {
        case recordingFailed(String)
        case noRecordingURL
        case permissionDenied
        
        var errorDescription: String? {
            switch self {
            case .recordingFailed(let reason):
                return "Recording failed: \(reason)"
            case .noRecordingURL:
                return "No recording URL available"
            case .permissionDenied:
                return "Microphone permission denied"
            }
        }
    }
    
    init(vadEngine: VADEngine) {
        self.vadEngine = vadEngine
    }
    
    /// Start recording based on mode
    func startRecording(mode: VoiceMode) throws {
        currentMode = mode
        
        switch mode {
        case .pushToTalk, .facetime:
            try startPTTRecording()
        case .handsfree:
            try startHandsfreeRecording()
        }
    }
    
    /// Stop recording
    func stopRecording() {
        switch currentMode {
        case .pushToTalk, .facetime:
            stopPTTRecording()
        case .handsfree:
            stopHandsfreeRecording()
        }
    }
    
    // MARK: - Push to Talk
    
    private func startPTTRecording() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("ptt_\(UUID().uuidString).wav")
        currentRecordingURL = url
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            isRecording = true
            onRecordingStarted?()
        } catch {
            throw VoiceInputError.recordingFailed(error.localizedDescription)
        }
    }
    
    private func stopPTTRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        
        if let url = currentRecordingURL {
            onRecordingFinished?(url)
        }
        currentRecordingURL = nil
    }
    
    // MARK: - Handsfree (VAD)
    
    private func startHandsfreeRecording() throws {
        // VAD handles everything through callbacks
        try vadEngine.startListening()
        isRecording = true
        onRecordingStarted?()
    }
    
    private func stopHandsfreeRecording() {
        vadEngine.stopListening()
        isRecording = false
    }
}
