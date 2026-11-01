import SwiftUI
import UserNotifications

/// Feed notifications (likes, comments, follows) through Apple's push service. Only builds for a
/// paid team carry the push entitlement, so the personal build leaves all of this out; the server
/// side is described in supabase/PUSH.md.
enum FeedPush {
    static let enabledKey = "nagisen.push.enabled"
    static let tokenKey = "nagisen.push.token"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks once for permission, then registers; the token arrives in `PushRelay`.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        return granted
    }

    static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }
}

#if !NAGISEN_NO_ICLOUD
final class PushRelay: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app once Feed is ready, so a new token is saved for the signed-in member.
    @MainActor static var onToken: ((String) -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if FeedPush.isEnabled { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = FeedPush.hex(deviceToken)
        UserDefaults.standard.set(token, forKey: FeedPush.tokenKey)
        Task { @MainActor in Self.onToken?(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No push entitlement or no network: Feed simply has no notifications on this iPhone.
    }

    /// Feed notifications show while the app is open; local reminders keep their usual behavior.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.trigger is UNPushNotificationTrigger ? [.banner, .sound] : [])
    }
}
#endif
