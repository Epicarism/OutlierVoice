import Foundation

/// Protocol for Speech-to-Text engines
/// Allows swapping between Apple SFSpeech and WhisperKit
protocol STTEngineProtocol {
    var isModelLoaded: Bool { get }
    var isTranscribing: Bool { get }
    var loadingProgress: Double { get }
    
    func loadModel(progressHandler: ((Double) -> Void)?) async throws
    func transcribe(audioURL: URL) async throws -> String
    func unloadModel()
}

/// STT Engine type selection
enum STTEngineType: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case whisper = "Whisper"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .apple:
            return "Apple Speech (Fast, OK accuracy)"
        case .whisper:
            return "Whisper (Slower, Best accuracy)"
        }
    }
}
