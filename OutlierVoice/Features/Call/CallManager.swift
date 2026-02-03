import Foundation
import UIKit
import AVFoundation

/// Manages active call state across the app
@Observable
@MainActor
final class CallManager {
    static let shared = CallManager()
    
    enum CallType {
        case voice
        case facetime
    }
    
    enum CallState {
        case idle
        case active(CallType)
        case minimized(CallType)
    }
    
    private(set) var state: CallState = .idle
    private(set) var callDuration: TimeInterval = 0
    private var callTimer: Timer?
    private var proximityObserver: NSObjectProtocol?
    
    var isInCall: Bool {
        switch state {
        case .idle: return false
        case .active, .minimized: return true
        }
    }
    
    var isMinimized: Bool {
        if case .minimized = state { return true }
        return false
    }
    
    var callType: CallType? {
        switch state {
        case .idle: return nil
        case .active(let type), .minimized(let type): return type
        }
    }
    
    private init() {}
    
    // MARK: - Call Control
    
    func startCall(type: CallType) {
        print("[CallManager] Starting \(type) call")
        state = .active(type)
        callDuration = 0
        startTimer()
        enableProximitySensor()
    }
    
    func minimizeCall() {
        guard case .active(let type) = state else { return }
        print("[CallManager] Minimizing call")
        state = .minimized(type)
    }
    
    func maximizeCall() {
        guard case .minimized(let type) = state else { return }
        print("[CallManager] Maximizing call")
        state = .active(type)
    }
    
    func endCall() {
        print("[CallManager] Ending call after \(formatDuration(callDuration))")
        state = .idle
        callDuration = 0
        stopTimer()
        disableProximitySensor()
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        callTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.callDuration += 1
            }
        }
    }
    
    private func stopTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Proximity Sensor
    
    private func enableProximitySensor() {
        print("[CallManager] Enabling proximity sensor")
        UIDevice.current.isProximityMonitoringEnabled = true
        
        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let isNear = UIDevice.current.proximityState
            print("[CallManager] Proximity state: \(isNear ? "near" : "far")")
            // Screen automatically blacks out when proximity sensor triggers
        }
    }
    
    private func disableProximitySensor() {
        print("[CallManager] Disabling proximity sensor")
        UIDevice.current.isProximityMonitoringEnabled = false
        
        if let observer = proximityObserver {
            NotificationCenter.default.removeObserver(observer)
            proximityObserver = nil
        }
    }
}
