import Foundation
import AVFoundation

/// Manages AVAudioSession for recording and playback
@Observable
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private(set) var hasPermission = false
    private(set) var isConfigured = false
    
    enum AudioSessionError: LocalizedError {
        case permissionDenied
        case configurationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission denied"
            case .configurationFailed(let reason):
                return "Audio session configuration failed: \(reason)"
            }
        }
    }
    
    private init() {}
    
    /// Request microphone permission
    func requestPermission() async -> Bool {
        #if os(iOS)
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        hasPermission = granted
        return granted
        #else
        // macOS handles permissions differently
        hasPermission = true
        return true
        #endif
    }
    
    /// Configure audio session for recording and playback
    func configure() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP]
            )
            try session.setActive(true)
            isConfigured = true
        } catch {
            throw AudioSessionError.configurationFailed(error.localizedDescription)
        }
        #else
        // macOS doesn't need audio session configuration
        isConfigured = true
        #endif
    }
    
    /// Configure for recording only
    func configureForRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            throw AudioSessionError.configurationFailed(error.localizedDescription)
        }
        #else
        isConfigured = true
        #endif
    }
    
    /// Configure for playback only
    func configureForPlayback() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw AudioSessionError.configurationFailed(error.localizedDescription)
        }
        #else
        isConfigured = true
        #endif
    }
    
    /// Deactivate audio session
    func deactivate() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            isConfigured = false
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        #else
        isConfigured = false
        #endif
    }
    
    /// Setup interruption handling
    func setupInterruptionHandling(onInterruption: @escaping (Bool) -> Void) {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            
            switch type {
            case .began:
                onInterruption(true)
            case .ended:
                onInterruption(false)
                // Try to reactivate
                try? AVAudioSession.sharedInstance().setActive(true)
            @unknown default:
                break
            }
        }
        #else
        // macOS doesn't have audio session interruptions
        _ = onInterruption
        #endif
    }
}
