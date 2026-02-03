import Foundation
import AVFoundation
import Speech

/// Speech-to-Text engine using Apple's built-in SFSpeechRecognizer
/// No downloads needed - works instantly!
@Observable
final class STTEngine: STTEngineProtocol {
    private let speechRecognizer: SFSpeechRecognizer?
    
    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var loadingProgress: Double = 0
    
    enum STTError: LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(String)
        case audioLoadFailed(String)
        case notAuthorized
        case recognizerUnavailable
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Speech recognition not ready"
            case .transcriptionFailed(let reason):
                return "Transcription failed: \(reason)"
            case .audioLoadFailed(let reason):
                return "Audio load failed: \(reason)"
            case .notAuthorized:
                return "Speech recognition not authorized"
            case .recognizerUnavailable:
                return "Speech recognizer unavailable for this locale"
            }
        }
    }
    
    init() {
        // Use device locale, fallback to English
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        print("[STT] Initialized with locale: \(speechRecognizer?.locale.identifier ?? "none")")
    }
    
    /// Request authorization and "load" the engine (instant - no download!)
    func loadModel(progressHandler: ((Double) -> Void)? = nil) async throws {
        guard !isModelLoaded else { return }
        
        print("[STT] Requesting speech recognition authorization...")
        loadingProgress = 0.5
        
        // Request authorization
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        switch status {
        case .authorized:
            print("[STT] ✅ Speech recognition authorized!")
            isModelLoaded = true
            loadingProgress = 1.0
            progressHandler?(1.0)
        case .denied:
            print("[STT] ❌ Speech recognition denied")
            throw STTError.notAuthorized
        case .restricted:
            print("[STT] ❌ Speech recognition restricted")
            throw STTError.notAuthorized
        case .notDetermined:
            print("[STT] ❌ Speech recognition not determined")
            throw STTError.notAuthorized
        @unknown default:
            throw STTError.notAuthorized
        }
        
        guard speechRecognizer?.isAvailable == true else {
            print("[STT] ❌ Speech recognizer not available")
            throw STTError.recognizerUnavailable
        }
    }
    
    /// Transcribe audio file to text using Apple's SFSpeechRecognizer
    func transcribe(audioURL: URL) async throws -> String {
        guard isModelLoaded else {
            throw STTError.modelNotLoaded
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw STTError.recognizerUnavailable
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        print("[STT] 🎤 Transcribing: \(audioURL.lastPathComponent)")
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false // Use server for better accuracy, falls back to on-device
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let result = result, result.isFinal {
                        continuation.resume(returning: result)
                    }
                }
            }
            
            let text = result.bestTranscription.formattedString
            print("[STT] ✅ Transcribed: \"\(text)\"")
            return text
            
        } catch {
            print("[STT] ❌ Transcription error: \(error)")
            throw STTError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    /// Unload (no-op for Apple STT, but keeps API compatible)
    func unloadModel() {
        isModelLoaded = false
        loadingProgress = 0
    }
}
