//
//  NotificationManager.swift
//  JustFast
//
//  Local notifications only (§4.4): a celebratory "goal reached" at
//  start + goalHours, and a daily "start reminder" suppressed while a fast is
//  running. No badges, no other notifications.
//
//  Deliberately no `UNUserNotificationCenterDelegate`: without one iOS suppresses
//  alerts that fire while the app is open, which is what we want — the app-open
//  goal celebration is the mint ring bloom + success haptic (§5), not a banner on
//  top of the screen already showing it. Don't "fix" this by adding a delegate
//  that returns `.banner` without revisiting §4.4/§5.
//

import Foundation
import OSLog
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "com.balenet.JustFast", category: "notifications")

    private static let startReminderID = "start-reminder"
    private static func goalID(_ fastID: UUID) -> String { "goal-\(fastID.uuidString)" }

    // MARK: Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// True when iOS will not present our alerts — permission was denied, or
    /// alerts have been switched off for the app in iOS Settings. `false` while
    /// the status is still undetermined: we simply haven't asked yet, which is
    /// not a problem to warn about (§4.4 asks lazily, never on launch).
    func alertsAreBlocked() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return true
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .disabled
        case .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    /// Schedule, logging failures instead of dropping them. `add` fails silently
    /// when permission is denied, which is exactly the case that used to leave
    /// the app permanently and invisibly mute.
    private func add(_ request: UNNotificationRequest) {
        let identifier = request.identifier
        center.add(request) { [log] error in
            if let error {
                log.error("Could not schedule \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Goal reached (§4.4)

    func scheduleGoalNotification(for fast: FastRecord, enabled: Bool) {
        cancelGoalNotification(for: fast.id)
        guard enabled, fast.isOpen else { return }

        let fireDate = fast.goalReachedAt
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return } // goal already passed; nothing to fire

        let content = UNMutableNotificationContent()
        content.title = "\(fast.goalHours) hours — goal reached 🎉"
        content.body = "Keep going or break your fast whenever you’re ready."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.goalID(fast.id), content: content, trigger: trigger)
        add(request)
    }

    func cancelGoalNotification(for fastID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.goalID(fastID)])
    }

    // MARK: Start reminder (§4.4)

    /// Arm the daily "time to start your fast?" nudge at the user's start-time
    /// anchor — the same time the eating window closes (§4.1, §4.4).
    ///
    /// One repeating trigger is enough because the anchor never moves. Wall-clock
    /// components rather than elapsed intervals, so it keeps landing at the chosen
    /// local time across a DST change.
    func scheduleStartReminder(hour: Int, minute: Int) {
        cancelStartReminder()

        let content = UNMutableNotificationContent()
        content.title = "Time to start your fast?"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute), repeats: true
        )
        add(UNNotificationRequest(identifier: Self.startReminderID, content: content, trigger: trigger))
    }

    func cancelStartReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.startReminderID])
    }
}
