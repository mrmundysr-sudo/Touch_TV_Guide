import Foundation
import UserNotifications
import TVGuideCore

enum NotificationState: Equatable { case notDetermined, denied, allowed }

/// Permission side of reminders, behind a protocol so tests don't touch the system.
protocol NotificationPermission: Sendable {
    func state() async -> NotificationState
    func request() async -> Bool
}

struct SystemNotificationPermission: NotificationPermission {
    func state() async -> NotificationState {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }
    func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

/// Schedules local notifications. `sync` replaces every pending reminder notification (iOS allows 64).
struct NotificationScheduler: ReminderScheduling {
    static let prefix = "reminder."
    func sync(_ items: [(Reminder, Date)]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard await SystemNotificationPermission().state() == .allowed else { return }
        for (r, fire) in items {
            let c = UNMutableNotificationContent()
            c.title = r.title
            c.body = r.channelName.isEmpty ? "Starting soon" : "Starting soon on \(r.channelName)"
            c.sound = .default
            c.userInfo = ["programKey": r.programKey, "start": r.startMillis]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.prefix + r.programKey, content: c, trigger: trigger))
        }
    }
}

/// Delivers notification taps and shows banners while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (@MainActor (String, Int64) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let key = info["programKey"] as? String else { return }
        let start = (info["start"] as? NSNumber)?.int64Value ?? 0
        await MainActor.run { onOpen?(key, start) }
    }
}
