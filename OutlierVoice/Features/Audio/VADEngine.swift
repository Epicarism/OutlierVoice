import Foundation
import AVFoundation
import Accelerate

/// Voice Activity Detection engine
@Observable
final class VADEngine {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var inputSampleRate: Double = 16000
    
    // Configuration - read from UserDefaults with sensible defaults
    var amplitudeThreshold: Float {
        let saved = UserDefaults.standard.double(forKey: "vadSensitivity")
        return saved > 0 ? Float(saved) : 0.02  // Default 0.02
    }
    
    var silenceDuration: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "silenceDuration")
        return saved > 0 ? saved : 1.5  // Default 1.5s
    }
    
    var minSpeechDuration: TimeInterval = 0.3
    
    // State
    enum State: Equatable {
        case idle
        case listening
        case speaking
    }
    
    private(set) var state: State = .idle
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var silenceTimer: Timer?
    
    // Callbacks
    var onSpeechStart: (() -> Void)?
    var onSpeechEnd: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    var onAmplitudeChange: ((Float) -> Void)?
    
    enum VADError: LocalizedError {
        case engineNotInitialized
        case recordingFailed(String)
        case saveFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .engineNotInitialized:
                return "Audio engine not initialized"
            case .recordingFailed(let reason):
                return "Recording failed: \(reason)"
            case .saveFailed(let reason):
                return "Save failed: \(reason)"
            }
        }
    }
    
    /// Start listening for voice activity
    func startListening() throws {
        print("[VAD] startListening() called, state: \(state)")
        guard state == .idle else { 
            print("[VAD] Already running, skipping")
            return 
        }
        
        // Reuse existing engine if available, otherwise create new
        if audioEngine == nil {
            print("[VAD] Creating NEW AVAudioEngine...")
            audioEngine = AVAudioEngine()
        } else {
            print("[VAD] Reusing existing AVAudioEngine")
        }
        
        guard let audioEngine = audioEngine else {
            print("[VAD] ERROR: audioEngine is nil")
            throw VADError.engineNotInitialized
        }
        
        print("[VAD] Getting inputNode...")
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("[VAD] ERROR: inputNode is nil")
            throw VADError.engineNotInitialized
        }
        
        print("[VAD] Getting format...")
        let format = inputNode.outputFormat(forBus: 0)
        inputSampleRate = format.sampleRate
        print("[VAD] Format: \(format), sampleRate: \(inputSampleRate)")
        
        // Check for valid format
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            print("[VAD] ERROR: Invalid audio format!")
            throw VADError.recordingFailed("Invalid audio format: sampleRate=\(format.sampleRate), channels=\(format.channelCount)")
        }
        
        bufferLock.lock()
        audioBuffer = []
        bufferLock.unlock()
        
        // Only install tap if not already installed
        print("[VAD] Installing tap...")
        // Remove any existing tap first to avoid "tap already exists" error
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBufferNonisolated(buffer)
        }
        
        print("[VAD] Starting engine...")
        try audioEngine.start()
        state = .listening
        print("[VAD] Engine started, state: \(state)")
    }
    
    /// Stop listening (pauses but keeps engine for quick restart)
    func stopListening() {
        print("[VAD] stopListening() called, state: \(state)")
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Remove tap but keep engine for reuse
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        // DON'T nil these - keep for quick restart
        // audioEngine = nil
        // inputNode = nil
        
        // If we were speaking, finalize the audio
        if state == .speaking {
            finalizeAudio()
        }
        
        state = .idle
        bufferLock.lock()
        audioBuffer = []
        bufferLock.unlock()
        print("[VAD] Stopped, engine preserved for reuse")
    }
    
    /// Fully destroy the audio engine (call on deinit or when done with VAD)
    func destroyEngine() {
        print("[VAD] destroyEngine() - fully releasing resources")
        stopListening()
        audioEngine = nil
        inputNode = nil
    }
    
    /// Process audio buffer from audio thread
    private func processAudioBufferNonisolated(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Calculate RMS amplitude
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        
        // Check if this looks like speech
        let isSpeech = rms > amplitudeThreshold
        
        // Only store audio when speaking (not when idle listening)
        // Also capture if speech detected to not miss the start
        if state == .speaking || isSpeech {
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            bufferLock.lock()
            // Safety limit: max 60 seconds at 48kHz = 2.88M samples
            // At 24kHz (common) = 1.44M samples for 60 seconds
            let maxBufferSize = 1_500_000  // ~60 seconds at 24kHz, ~30 seconds at 48kHz
            if audioBuffer.count < maxBufferSize {
                audioBuffer.append(contentsOf: samples)
                
                // Auto-finalize when buffer is 90% full to avoid dropping audio
                if audioBuffer.count > Int(Double(maxBufferSize) * 0.9) && state == .speaking {
                    print("[VAD] ⚠️ Buffer 90% full, auto-finalizing...")
                    bufferLock.unlock()
                    DispatchQueue.main.async { [weak self] in
                        self?.finalizeAudio()
                    }
                    return
                }
            } else {
                print("[VAD] ⚠️ Buffer full, dropping audio")
            }
            bufferLock.unlock()
        }
        
        // Dispatch to main queue for callbacks and state updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.onAmplitudeChange?(rms)
            
            // Debug: Log amplitude periodically
            if Int.random(in: 0...50) == 0 {
                print("[VAD] 🎤 Amplitude: \(String(format: "%.4f", rms)) threshold: \(self.amplitudeThreshold) isSpeech: \(isSpeech)")
            }
            
            // Detect speech
            if isSpeech {
                self.handleSpeechDetected()
            } else {
                self.handleSilenceDetected()
            }
        }
    }
    
    private func handleSpeechDetected() {
        lastSpeechTime = Date()
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if state == .listening {
            // Speech started
            state = .speaking
            speechStartTime = Date()
            print("[VAD] 🎙️ SPEECH STARTED - state now: \(state)")
            onSpeechStart?()
        }
    }
    
    private func handleSilenceDetected() {
        guard state == .speaking else { 
            // Clear buffer when idle to prevent memory buildup
            if state == .listening {
                bufferLock.lock()
                if audioBuffer.count > 10000 {
                    audioBuffer.removeAll(keepingCapacity: true)
                }
                bufferLock.unlock()
            }
            return 
        }
        
        // Start silence timer if not already running (must be on main thread for RunLoop)
        if silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleSilenceTimeout()
                }
            }
        }
    }
    
    private func handleSilenceTimeout() {
        guard state == .speaking else { return }
        
        // Check if speech duration was long enough
        if let startTime = speechStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("[VAD] ⏱️ Silence timeout - speech duration: \(String(format: "%.2f", duration))s, min: \(minSpeechDuration)s")
            
            if duration >= minSpeechDuration {
                print("[VAD] ✅ Speech long enough, finalizing audio...")
                finalizeAudio()
            } else {
                // Too short, reset
                print("[VAD] ❌ Speech too short (\(String(format: "%.2f", duration))s < \(minSpeechDuration)s), discarding")
                state = .listening
                bufferLock.lock()
                audioBuffer = []
                bufferLock.unlock()
            }
        } else {
            print("[VAD] ⚠️ No speech start time recorded!")
            state = .listening
        }
        
        silenceTimer = nil
    }
    
    private func finalizeAudio() {
        state = .listening
        
        bufferLock.lock()
        let bufferCopy = audioBuffer
        audioBuffer = []
        bufferLock.unlock()
        
        print("[VAD] 🔇 SPEECH ENDED - buffer size: \(bufferCopy.count) samples")
        
        guard !bufferCopy.isEmpty else {
            print("[VAD] ⚠️ Buffer is empty, nothing to save!")
            return
        }
        
        // Save audio to file
        do {
            let url = try saveAudioBuffer(bufferCopy)
            let duration = Double(bufferCopy.count) / inputSampleRate
            print("[VAD] 💾 Saved audio: \(url.lastPathComponent) (\(String(format: "%.2f", duration))s)")
            print("[VAD] 📤 Calling onSpeechEnd callback...")
            self.onSpeechEnd?(url)
            print("[VAD] ✅ onSpeechEnd callback completed")
        } catch {
            print("[VAD] ❌ Failed to save audio: \(error)")
            self.onError?(error)
        }
        
        speechStartTime = nil
    }
    
    private func saveAudioBuffer(_ buffer: [Float]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("vad_\(UUID().uuidString).wav")
        
        // Use the actual input sample rate from the device
        let format = AVAudioFormat(standardFormatWithSampleRate: inputSampleRate, channels: 1)!
        let audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        // Create buffer
        let frameCount = AVAudioFrameCount(buffer.count)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw VADError.saveFailed("Failed to create buffer")
        }
        
        pcmBuffer.frameLength = frameCount
        let channelData = pcmBuffer.floatChannelData![0]
        for (index, sample) in buffer.enumerated() {
            channelData[index] = sample
        }
        
        try audioFile.write(from: pcmBuffer)
        
        return outputURL
    }
}
