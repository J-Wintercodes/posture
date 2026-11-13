import Foundation
import UserNotifications

/// Local notifications: the silent feedback channel (mirrors to Apple Watch
/// as a wrist tap while the iPhone is locked), auto-start confirmations, the
/// scheduled check-ins of study mode, the calm suggestions at home and the
/// pain question before bed.
enum Notifier {
    /// Key in `userInfo` that carries the id of the routine to open.
    static let routineKey = "routine"
    /// Key in `userInfo` that marks a check-in, with or without a routine.
    static let checkInKey = "checkin"
    /// Key in `userInfo` that carries the day a pain question is about.
    static let painDayKey = "painDay"
    /// Id of the check-in notification posted by a running tracking session.
    /// One id, so a new check-in replaces the previous one.
    static let liveCheckInID = "checkin-live"
    static let painCategory = "PAIN_CHECK"
    /// Action ids are this prefix plus the level: "pain.3".
    static let painActionPrefix = "pain."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// The quick answers under the pain question (press and hold the
    /// notification): none, mild, moderate, strong.
    static func registerCategories(language: CoachLanguage) {
        let actions = PainScale.quick.map { level in
            UNNotificationAction(
                identifier: "\(painActionPrefix)\(level)",
                title: "\(PainScale.label(level, language: language)) (\(level))",
                options: []
            )
        }
        let category = UNNotificationCategory(
            identifier: painCategory,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func post(title: String, body: String, id: String = UUID().uuidString, sound: Bool = true,
                     routineID: String? = nil, checkIn: Bool = false) {
        let request = UNNotificationRequest(
            identifier: id,
            content: content(title: title, body: body, sound: sound, routineID: routineID, painDay: nil, checkIn: checkIn),
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Hands a notification to iOS for later. It is delivered even when the
    /// app is suspended or was closed, which is what makes study mode free
    /// of battery cost.
    ///
    /// `wallClock` pins it to the clock time (for things planned days
    /// ahead, across a change of daylight saving time); otherwise it fires
    /// after the remaining interval.
    static func schedule(title: String, body: String, id: String, at date: Date, routineID: String?,
                         painDay: String? = nil, sound: Bool = true, wallClock: Bool = false, checkIn: Bool = false) {
        guard date.timeIntervalSinceNow > 1 else { return }
        let trigger: UNNotificationTrigger
        if wallClock {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: id,
            content: content(title: title, body: body, sound: sound, routineID: routineID, painDay: painDay, checkIn: checkIn),
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

    private static func content(title: String, body: String, sound: Bool, routineID: String?, painDay: String?,
                                checkIn: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        var info: [String: String] = [:]
        if let routineID { info[routineKey] = routineID }
        if checkIn { info[checkInKey] = "1" }
        if let painDay {
            info[painDayKey] = painDay
            content.categoryIdentifier = painCategory
        }
        if !info.isEmpty { content.userInfo = info }
        return content
    }
}

/// Receives notification taps. A check-in carries the id of its routine, so
/// tapping it opens that routine directly. The pain question can be answered
/// right on the notification.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// All of these are called on the main queue.
    var onOpenRoutine: ((String) -> Void)?
    var onCheckInShown: (() -> Void)?
    /// Level and day key: a quick answer was picked on the notification.
    var onPainAnswer: ((Int, String) -> Void)?
    /// Day key: the pain question was tapped, show the scale.
    var onOpenPainCheck: ((String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Check-ins, suggestions and the pain question are shown as a banner
        // even while the app is open. Everything else stays quiet in the
        // foreground, as before.
        let info = notification.request.content.userInfo
        let isCheckIn = info[Notifier.routineKey] != nil || info[Notifier.checkInKey] != nil
        let isPain = info[Notifier.painDayKey] != nil
        completionHandler(isCheckIn || isPain ? [.banner, .list, .sound] : [])
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
        let info = response.notification.request.content.userInfo
        let routineID = info[Notifier.routineKey] as? String
        let painDay = info[Notifier.painDayKey] as? String
        let action = response.actionIdentifier
        completionHandler()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let painDay {
                if action.hasPrefix(Notifier.painActionPrefix),
                   let level = Int(action.dropFirst(Notifier.painActionPrefix.count)) {
                    self.onPainAnswer?(level, painDay)
                } else if action == UNNotificationDefaultActionIdentifier {
                    self.onOpenPainCheck?(painDay)
                }
            } else if let routineID, action == UNNotificationDefaultActionIdentifier {
                self.onOpenRoutine?(routineID)
            }
        }
    }
}
