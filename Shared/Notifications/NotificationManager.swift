//
//  NotificationManager.swift
//  Fastino
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
    private let log = Logger(subsystem: "com.baleware.fastino", category: "notifications")

    private static let startReminderID = "start-reminder"
    private static func goalID(_ fastID: UUID) -> String { "goal-\(fastID.uuidString)" }
    private static func milestoneID(_ fastID: UUID, _ zone: MetabolicZone) -> String {
        "milestone-\(zone.rawValue)-\(fastID.uuidString)"
    }

    // MARK: Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        #if os(watchOS)
        // The watch never schedules anything (see `add`), so asking would be a
        // permission prompt in exchange for nothing.
        return false
        #else
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #endif
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
    ///
    /// On watchOS this is a deliberate no-op: iOS forwards the phone's
    /// notifications to the watch, and there is no API to opt a local
    /// notification out of forwarding — identifiers are namespaced per device,
    /// so matching ids don't dedupe. If both devices scheduled the same goal
    /// alert the user would simply get it twice. The phone owns scheduling;
    /// cancelling stays live on both so a watch-side end still clears whatever
    /// that device had. FastinoApp re-arms on launch and on every foreground,
    /// so a fast started on the watch gets its notifications the moment the
    /// phone is next opened.
    private func add(_ request: UNNotificationRequest) {
        #if os(watchOS)
        return
        #else
        let identifier = request.identifier
        center.add(request) { [log] error in
            if let error {
                log.error("Could not schedule \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
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

    // MARK: Metabolic milestones (§4.4)

    /// Nudges as the fast crosses into fat burn and ketosis — the same boundaries
    /// the ring changes colour at, so the notification and the screen agree.
    ///
    /// A milestone that lands at or after the goal is skipped: on a 14:10 plan the
    /// ketosis boundary *is* the goal, and two alerts for one moment is noise.
    func scheduleMilestoneNotifications(for fast: FastRecord, enabled: Bool) {
        cancelMilestoneNotifications(for: fast.id)
        guard enabled, fast.isOpen else { return }

        for zone in MetabolicZone.allCases where zone.startHours > 0 {
            let fireDate = fast.start.addingTimeInterval(zone.startHours * 3600)
            guard fireDate < fast.goalReachedAt else { continue }
            let interval = fireDate.timeIntervalSinceNow
            guard interval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(zone.name) zone"
            content.body = zone.milestoneBody
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            add(UNNotificationRequest(
                identifier: Self.milestoneID(fast.id, zone),
                content: content,
                trigger: trigger
            ))
        }
    }

    func cancelMilestoneNotifications(for fastID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: MetabolicZone.allCases.map { Self.milestoneID(fastID, $0) }
        )
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
