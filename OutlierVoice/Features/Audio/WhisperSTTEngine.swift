import Foundation
import AVFoundation
import WhisperKit

/// Speech-to-Text engine using WhisperKit (on-device Whisper)
/// Much better accuracy than Apple's SFSpeechRecognizer
@Observable
final class WhisperSTTEngine: STTEngineProtocol {
    private var whisperKit: WhisperKit?
    
    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var loadingProgress: Double = 0
    private(set) var modelName: String = "openai_whisper-tiny"
    
    enum STTError: LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(String)
        case audioLoadFailed(String)
        case whisperKitNotAvailable
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Whisper model not loaded"
            case .transcriptionFailed(let reason):
                return "Transcription failed: \(reason)"
            case .audioLoadFailed(let reason):
                return "Audio load failed: \(reason)"
            case .whisperKitNotAvailable:
                return "WhisperKit not available"
            }
        }
    }
    
    init() {
        print("[WhisperSTT] Initialized")
    }
    
    func loadModel(progressHandler: ((Double) -> Void)?) async throws {
        guard !isModelLoaded else { return }
        
        print("[WhisperSTT] Loading Whisper model: \(modelName)...")
        loadingProgress = 0.1
        progressHandler?(0.1)
        
        do {
            let config = WhisperKitConfig(
                model: modelName,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: true
            )
            
            loadingProgress = 0.3
            progressHandler?(0.3)
            
            whisperKit = try await WhisperKit(config)
            
            loadingProgress = 1.0
            progressHandler?(1.0)
            isModelLoaded = true
            
            print("[WhisperSTT] Whisper model loaded!")
            
        } catch {
            print("[WhisperSTT] Failed to load model: \(error)")
            throw STTError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        guard isModelLoaded, let whisper = whisperKit else {
            throw STTError.modelNotLoaded
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        print("[WhisperSTT] Transcribing: \(audioURL.lastPathComponent)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let results = try await whisper.transcribe(audioPath: audioURL.path)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("[WhisperSTT] Transcribed in \(String(format: "%.2f", elapsed))s: \(text.prefix(50))...")
            
            return text
            
        } catch {
            print("[WhisperSTT] Transcription error: \(error)")
            throw STTError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
        loadingProgress = 0
        print("[WhisperSTT] Model unloaded")
    }
    
    static let availableModels = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-small"
    ]
}
