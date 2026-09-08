//
//  CompanionListener.swift
//  Fastino
//
//  The phone half of `CompanionRelay` (§4.4): receives the watch's "a fast is /
//  isn't running" and re-arms this device's notifications from it.
//
//  Why it can't wait for the CloudKit import: the phone owns the start reminder
//  and only the phone can cancel it, but a suspended phone runs no code, and
//  mirroring's silent push is best-effort. `transferUserInfo` wakes the app in
//  the background, which is what makes this the reliable path — so the session
//  is activated from the app delegate, at launch, rather than from a `.task` on
//  a scene that a background launch may never bring up.
//
//  What arrives is a *hint about scheduling*, never data to keep: nothing here
//  is written to the store, and the fast itself still arrives as an import.
//  Should the two disagree, the import wins — every later `reconcileNotifications()`
//  reads the store and overwrites what this armed.
//

import Foundation
import OSLog
import SwiftData
import WatchConnectivity

@MainActor
final class CompanionListener: NSObject {
    static let shared = CompanionListener()

    private let log = Logger(subsystem: "com.baleware.fastino", category: "CompanionRelay")
    private var isStarted = false
    /// Timestamp of the newest payload acted on, so a transfer that arrives out
    /// of order — or after the store already knows better — is dropped.
    private var lastAppliedAt: Date?

    private override init() { super.init() }

    /// Idempotent. Safe on a phone with no watch paired: activation simply
    /// reports no counterpart and nothing ever arrives.
    func start() {
        guard !isStarted, WCSession.isSupported() else { return }
        isStarted = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Apply the watch's view of scheduling state.
    ///
    /// Cancel-then-arm in both branches: the watch may have deleted the fast
    /// this phone armed a goal alert for and started a different one, and a
    /// stale `goal-<uuid>` would otherwise sit there until the import landed.
    fileprivate func apply(_ payload: CompanionRelayPayload) async {
        guard CompanionRelayPayload.isFresh(payload, lastApplied: lastAppliedAt) else {
            log.info("Ignoring a relay payload older than the last one applied.")
            return
        }
        lastAppliedAt = payload.sentAt

        let settings = FastStore(context: AppContainer.shared.mainContext).settings()
        await NotificationManager.shared.cancelFastNotifications()

        if let openFast = payload.openFast {
            NotificationManager.shared.scheduleGoalNotification(
                for: openFast, enabled: settings.goalNotificationEnabled
            )
            NotificationManager.shared.scheduleMilestoneNotifications(
                for: openFast, enabled: settings.milestoneNotificationsEnabled
            )
            NotificationManager.shared.cancelStartReminder() // suppressed while a fast runs (§4.4)
        } else if settings.startReminderEnabled {
            NotificationManager.shared.scheduleStartReminder(
                hour: settings.startReminderHour,
                minute: settings.startReminderMinute
            )
        } else {
            NotificationManager.shared.cancelStartReminder()
        }

        let state = payload.openFast == nil ? "no fast" : "fasting"
        log.info("Watch says: \(state, privacy: .public) — notifications re-armed.")
        // In the log the diagnostics screen reads, because "did the phone wake
        // when the watch started a fast?" is the question this whole path exists
        // to answer, and it is otherwise invisible from the device.
        SyncLog.shared.recordRelay("received · \(state)")
    }
}

// Only `didReceiveUserInfo` matters. The two lifecycle callbacks below are
// required on iOS — the session tears down when the user switches watches — and
// reactivating is all there is to do about it.
extension CompanionListener: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            Task { @MainActor in
                self.log.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let payload = CompanionRelayPayload(userInfo: userInfo) else { return }
        Task { @MainActor in
            await self.apply(payload)
        }
    }
}
