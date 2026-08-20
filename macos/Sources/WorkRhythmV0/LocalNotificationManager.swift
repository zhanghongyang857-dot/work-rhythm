import Foundation
@preconcurrency import UserNotifications

@MainActor
final class LocalNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let focusReminderID = "work-rhythm.focus-reminder"
    private let restReminderID = "work-rhythm.rest-reminder"

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization(afterGranted: @escaping @MainActor @Sendable () -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in afterGranted() }
        }
    }

    func scheduleFocusReminder(after interval: TimeInterval) {
        schedule(
            id: focusReminderID,
            title: "该休息了",
            body: "已完成一轮专注，可以开始休息。",
            after: interval
        )
    }

    func scheduleRestCompletion(after interval: TimeInterval) {
        schedule(
            id: restReminderID,
            title: "休息结束",
            body: "已准备好开始下一轮专注。",
            after: interval
        )
    }

    func cancelFocusReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [focusReminderID])
    }

    func cancelRestReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [restReminderID])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func schedule(id: String, title: String, body: String, after interval: TimeInterval) {
        let notificationCenter = center
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])
            notificationCenter.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
