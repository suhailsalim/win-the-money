import Foundation
import UserNotifications

/// Local notifications — a monthly budget reminder. No server, no push.
enum NotificationManager {
    static let reminderId = "wtm_monthly_budget"

    /// Toggle the monthly reminder. Requests authorization on enable.
    static func setEnabled(_ on: Bool) {
        let center = UNUserNotificationCenter.current()
        guard on else { center.removePendingNotificationRequests(withIdentifiers: [reminderId]); return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Win the Money"
            content.body = "A few days left this month — review your budget and stay on plan."
            content.sound = .default
            var when = DateComponents(); when.day = 25; when.hour = 10
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            center.add(UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger))
        }
    }
}
