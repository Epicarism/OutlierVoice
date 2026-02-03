import Foundation
import CallKit
import AVFoundation

/// CallKit integration for native iOS call UI
/// Provides lock screen call interface, system audio routing, and proximity sensor
@MainActor
final class CallKitManager: NSObject, ObservableObject {
    static let shared = CallKitManager()
    
    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    
    // Callbacks for call events
    var onCallStarted: (() -> Void)?
    var onCallEnded: (() -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onAudioRouteChanged: ((AVAudioSession.PortOverride) -> Void)?
    
    @Published var isCallActive = false
    @Published var isMuted = false
    @Published var isSpeakerOn = true
    
    private override init() {
        // Configure CallKit provider (localizedName set via init on iOS 14+)
        let config = CXProviderConfiguration(localizedName: "Claude")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false  // Don't add to phone history
        
        // Optional: Custom icon (36x36 points)
        // config.iconTemplateImageData = UIImage(named: "CallIcon")?.pngData()
        
        self.provider = CXProvider(configuration: config)
        
        super.init()
        
        provider.setDelegate(self, queue: nil)
        
        print("[CallKit] Initialized")
    }
    
    // MARK: - Start Call
    
    /// Start an outgoing call to Claude
    func startCall() {
        let uuid = UUID()
        currentCallUUID = uuid
        
        let handle = CXHandle(type: .generic, value: "Claude")
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = false
        
        let transaction = CXTransaction(action: startCallAction)
        
        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("[CallKit] ❌ Start call failed: \(error.localizedDescription)")
                return
            }
            
            print("[CallKit] ✅ Call started with UUID: \(uuid)")
            
            Task { @MainActor in
                self?.isCallActive = true
                
                // Report call connected after brief delay
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.provider.reportOutgoingCall(with: uuid, connectedAt: Date())
            }
        }
    }
    
    // MARK: - End Call
    
    /// End the current call
    func endCall() {
        guard let uuid = currentCallUUID else {
            print("[CallKit] No active call to end")
            return
        }
        
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKit] ❌ End call failed: \(error.localizedDescription)")
                return
            }
            print("[CallKit] ✅ Call ended")
        }
    }
    
    // MARK: - Mute
    
    /// Toggle mute state
    func toggleMute() {
        guard let uuid = currentCallUUID else { return }
        
        let muteAction = CXSetMutedCallAction(call: uuid, muted: !isMuted)
        let transaction = CXTransaction(action: muteAction)
        
        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("[CallKit] ❌ Mute failed: \(error.localizedDescription)")
                return
            }
            Task { @MainActor in
                self?.isMuted.toggle()
                print("[CallKit] Mute: \(self?.isMuted == true)")
            }
        }
    }
    
    // MARK: - Speaker
    
    /// Toggle speaker on/off
    func toggleSpeaker() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            if isSpeakerOn {
                // Switch to earpiece
                try session.overrideOutputAudioPort(.none)
                isSpeakerOn = false
                print("[CallKit] 🔈 Switched to earpiece")
            } else {
                // Switch to speaker
                try session.overrideOutputAudioPort(.speaker)
                isSpeakerOn = true
                print("[CallKit] 🔊 Switched to speaker")
            }
            onAudioRouteChanged?(isSpeakerOn ? .speaker : .none)
        } catch {
            print("[CallKit] ❌ Audio route change failed: \(error)")
        }
    }
    
    /// Set speaker state directly
    func setSpeaker(_ enabled: Bool) {
        guard enabled != isSpeakerOn else { return }
        toggleSpeaker()
    }
    
    // MARK: - Audio Session
    
    /// Configure audio session for call
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .defaultToSpeaker,
                .allowBluetoothHFP,
                .mixWithOthers
            ])
            try session.setActive(true)
            print("[CallKit] ✅ Audio session configured")
        } catch {
            print("[CallKit] ❌ Audio session config failed: \(error)")
        }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    
    nonisolated func providerDidReset(_ provider: CXProvider) {
        print("[CallKit] Provider reset")
        Task { @MainActor in
            currentCallUUID = nil
            isCallActive = false
        }
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("[CallKit] 📞 Starting call...")
        
        Task { @MainActor in
            configureAudioSession()
            onCallStarted?()
        }
        
        action.fulfill()
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("[CallKit] 📴 Ending call...")
        
        Task { @MainActor in
            currentCallUUID = nil
            isCallActive = false
            isMuted = false
            onCallEnded?()
        }
        
        action.fulfill()
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("[CallKit] 🔇 Mute action: \(action.isMuted)")
        
        Task { @MainActor in
            isMuted = action.isMuted
            onMuteChanged?(action.isMuted)
        }
        
        action.fulfill()
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        print("[CallKit] ⏸️ Hold action: \(action.isOnHold)")
        // We don't support hold, just fulfill
        action.fulfill()
    }
    
    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("[CallKit] 🎙️ Audio session activated")
    }
    
    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("[CallKit] 🔇 Audio session deactivated")
    }
    
    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // For future incoming calls
        print("[CallKit] 📲 Answer call action")
        action.fulfill()
    }
}
