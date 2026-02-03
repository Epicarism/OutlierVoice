import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Register notification categories
        registerNotificationCategories()
        
        // Register for VoIP pushes (for background alarm calls!)
        VoIPPushManager.shared.register()
        
        return true
    }
    
    private func registerNotificationCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "😴 Snooze 5 min",
            options: []
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "✅ Dismiss",
            options: [.destructive]
        )
        
        let alarmCategory = UNNotificationCategory(
            identifier: "CLAUDE_ALARM",
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory])
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Called when notification arrives while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        if let alarmId = userInfo["alarmId"] as? String {
            // Trigger full-screen alarm UI
            DispatchQueue.main.async {
                AlarmManager.shared.handleNotification(alarmId: alarmId)
            }
            // Don't show banner - we're showing full screen
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }
    
    // Called when user taps on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        if let alarmId = userInfo["alarmId"] as? String {
            switch response.actionIdentifier {
            case "SNOOZE_ACTION":
                // Find alarm and snooze
                if let alarm = AlarmManager.shared.alarms.first(where: { $0.id.uuidString == alarmId }) {
                    AlarmManager.shared.triggerAlarm(alarm)
                    AlarmManager.shared.snoozeAlarm(minutes: 5)
                }
                
            case "DISMISS_ACTION", UNNotificationDismissActionIdentifier:
                AlarmManager.shared.dismissAlarm()
                
            default:
                // User tapped notification - show alarm UI
                DispatchQueue.main.async {
                    AlarmManager.shared.handleNotification(alarmId: alarmId)
                }
            }
        }
        
        completionHandler()
    }
}
