import Foundation
import PushKit
import CallKit
import UIKit

/// Handles VoIP push notifications for alarm calls
/// VoIP pushes can wake the app and trigger CallKit even when backgrounded/locked
@MainActor
final class VoIPPushManager: NSObject, ObservableObject {
    static let shared = VoIPPushManager()
    
    private var pushRegistry: PKPushRegistry?
    @Published private(set) var voipToken: String?
    @Published private(set) var isRegistered = false
    
    // Server configuration
    private var serverURL: String {
        // Try to load from UserDefaults, default to local Mac
        UserDefaults.standard.string(forKey: "alarm_server_url") ?? "http://192.168.1.100:3000"
    }
    
    private var deviceId: String {
        // Use a stable device identifier
        if let existing = UserDefaults.standard.string(forKey: "alarm_device_id") {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "alarm_device_id")
        return newId
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    /// Call this on app launch to register for VoIP pushes
    func register() {
        print("[VoIP] Registering for VoIP push notifications...")
        
        pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry?.delegate = self
        pushRegistry?.desiredPushTypes = [.voIP]
    }
    
    /// Update server URL (e.g., from settings)
    func setServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "alarm_server_url")
        print("[VoIP] Server URL updated: \(url)")
        
        // Re-register with new server
        if let token = voipToken {
            registerWithServer(token: token)
        }
    }
    
    // MARK: - Server Communication
    
    private func registerWithServer(token: String) {
        guard let url = URL(string: "\(serverURL)/register") else {
            print("[VoIP] ❌ Invalid server URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "deviceId": deviceId,
            "deviceToken": token
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[VoIP] ❌ Server registration failed: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[VoIP] ✅ Registered with server successfully!")
                DispatchQueue.main.async {
                    self.isRegistered = true
                }
            }
        }.resume()
    }
    
    /// Sync an alarm to the server
    func syncAlarm(_ alarm: ClaudeAlarm) {
        guard let url = URL(string: "\(serverURL)/alarm") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "alarmId": alarm.id.uuidString,
            "deviceId": deviceId,
            "title": alarm.title,
            "message": alarm.message,
            "time": ISO8601DateFormatter().string(from: alarm.time),
            "repeatDays": alarm.repeatDays,
            "isEnabled": alarm.isEnabled
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[VoIP] ❌ Failed to sync alarm: \(error.localizedDescription)")
                return
            }
            print("[VoIP] ✅ Alarm synced: \(alarm.title)")
        }.resume()
    }
    
    /// Delete alarm from server
    func deleteAlarm(_ alarmId: UUID) {
        guard let url = URL(string: "\(serverURL)/alarm/\(alarmId.uuidString)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("[VoIP] 🗑️ Alarm deleted from server")
        }.resume()
    }
}

// MARK: - PKPushRegistryDelegate

extension VoIPPushManager: PKPushRegistryDelegate {
    
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("[VoIP] 📱 Got VoIP token: \(token.prefix(40))...")
        
        Task { @MainActor in
            self.voipToken = token
            self.registerWithServer(token: token)
        }
    }
    
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[VoIP] ⚠️ VoIP token invalidated")
        Task { @MainActor in
            self.voipToken = nil
            self.isRegistered = false
        }
    }
    
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }
        
        print("[VoIP] 📞 INCOMING VOIP PUSH!")
        print("[VoIP] Payload: \(payload.dictionaryPayload)")
        
        // Extract alarm data
        let alarmId = payload.dictionaryPayload["alarmId"] as? String ?? "unknown"
        let title = payload.dictionaryPayload["title"] as? String ?? "Claude Alarm"
        let message = payload.dictionaryPayload["message"] as? String ?? "Time to wake up!"
        
        // MUST report a call to CallKit when receiving VoIP push!
        // iOS requires this - if you don't, your app gets terminated.
        Task { @MainActor in
            // Find the alarm
            if let alarm = AlarmManager.shared.alarms.first(where: { $0.id.uuidString == alarmId }) {
                AlarmManager.shared.triggerAlarm(alarm)
            } else {
                // No matching alarm - create temp one for the call
                CallKitManager.shared.reportIncomingAlarmCall(title: title, message: message)
            }
            
            completion()
        }
    }
}
