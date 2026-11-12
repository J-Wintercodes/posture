import Foundation
import UserNotifications

/// Local notifications: the silent feedback channel (mirrors to Apple Watch
/// as a wrist tap while the iPhone is locked), auto-start confirmations and
/// the scheduled check-ins of a reminders-only session.
enum Notifier {
    /// Key in `userInfo` that carries the id of the routine to open.
    static let routineKey = "routine"
    /// Id of the check-in notification posted by a running tracking session.
    /// One id, so a new check-in replaces the previous one.
    static let liveCheckInID = "checkin-live"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    static func post(title: String, body: String, id: String = UUID().uuidString, sound: Bool = true, routineID: String? = nil) {
        let request = UNNotificationRequest(
            identifier: id,
            content: content(title: title, body: body, sound: sound, routineID: routineID),
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Hands a notification to iOS for later. It is delivered even when the
    /// app is suspended or was closed, which is what makes the reminders-only
    /// mode free of battery cost.
    static func schedule(title: String, body: String, id: String, at date: Date, routineID: String?) {
        let delay = date.timeIntervalSinceNow
        guard delay > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: id,
            content: content(title: title, body: body, sound: true, routineID: routineID),
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func clearDelivered(ids: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func content(title: String, body: String, sound: Bool, routineID: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        if let routineID { content.userInfo = [routineKey: routineID] }
        return content
    }
}

/// Receives notification taps. A check-in carries the id of its routine, so
/// tapping it opens that routine directly.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Both are called on the main queue.
    var onOpenRoutine: ((String) -> Void)?
    var onCheckInShown: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // A check-in is shown as a banner even while the app is open.
        // Everything else stays quiet in the foreground, as before.
        let isCheckIn = notification.request.content.userInfo[Notifier.routineKey] != nil
        completionHandler(isCheckIn ? [.banner, .list, .sound] : [])
        if isCheckIn {
            DispatchQueue.main.async { [weak self] in
                self?.onCheckInShown?()
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let routineID = response.notification.request.content.userInfo[Notifier.routineKey] as? String
        completionHandler()
        guard let routineID else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onOpenRoutine?(routineID)
        }
    }
}
