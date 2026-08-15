//
//  NotificationOwnership.swift
//  Fastino
//
//  Which device schedules the local notifications (§4.4).
//
//  Only one may. iOS forwards the phone's notifications to a paired watch, and
//  there is no API to opt a local notification out of that forwarding —
//  identifiers are namespaced per device, so matching ids don't dedupe. If both
//  devices scheduled, the user would get every alert twice.
//
//  The phone owns them whenever it can, because it's the device that can ask
//  for permission in a familiar place and the one whose alerts reach the watch
//  anyway. The watch takes over only when there is no phone app to defer to —
//  a standalone install, where deferring would mean the user gets nothing at
//  all.
//
//  The decision is a pure function so it can be tested without WatchConnectivity,
//  which is untestable; `CompanionProbe` (watch target only) supplies the input.
//

import Foundation
import OSLog

nonisolated enum NotificationOwnership {

    /// Whether *this* device should schedule.
    ///
    /// - Parameters:
    ///   - cached: the last known answer, or the conservative default on a
    ///     device that has never resolved one.
    ///   - activated: whether the companion session has finished activating.
    ///   - companionInstalled: whether the paired phone has the iOS app.
    ///
    /// Before activation completes, `companionInstalled` reads `false` even on
    /// a paired watch with the app installed — so trusting it early would make
    /// every paired watch briefly claim ownership and double the user's alerts.
    /// Until we actually know, we keep the previous answer.
    static func decide(cached: Bool, activated: Bool, companionInstalled: Bool) -> Bool {
        activated ? !companionInstalled : cached
    }

    /// The answer for a device that has never resolved one.
    ///
    /// `false` — assume a phone is out there. On a standalone watch's very
    /// first launch this costs a sub-second window where scheduling no-ops,
    /// closed as soon as activation completes and re-runs
    /// `reconcileNotifications()`. The opposite default would trade that
    /// invisible gap for visible duplicate alerts on every paired watch, which
    /// is much the worse bargain.
    static let conservativeDefault = false

    #if os(watchOS)

    private static let defaultsKey = "notificationOwnership.schedulesLocally"
    private static let log = Logger(subsystem: "com.baleware.fastino", category: "NotificationOwnership")

    /// Stored in the app group so the answer survives launches, and so the
    /// complication process could read it if it ever needs to.
    private static var store: UserDefaults? {
        UserDefaults(suiteName: AppContainer.appGroupID)
    }

    /// DEBUG-only override, so both branches can be exercised on one watch.
    ///
    /// Whether this watch defers or schedules is decided by a fact about the
    /// *paired phone*, which can't be changed for a test run — the only honest
    /// way to reach the standalone branch on a paired watch is to say so at
    /// launch. `-forceWatchNotifications` claims ownership,
    /// `-deferWatchNotifications` gives it up; neither touches the stored
    /// answer, so a normal launch afterwards is unaffected.
    private static var override: Bool? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-forceWatchNotifications") { return true }
        if arguments.contains("-deferWatchNotifications") { return false }
        #endif
        return nil
    }

    /// Whether this device schedules notifications. Read on every `add()`.
    static var schedulesLocally: Bool {
        if let override { return override }
        guard let store, store.object(forKey: defaultsKey) != nil else {
            return conservativeDefault
        }
        return store.bool(forKey: defaultsKey)
    }

    /// Record what the companion probe found.
    /// - Returns: whether the answer changed, so the caller knows to re-arm.
    @discardableResult
    static func update(activated: Bool, companionInstalled: Bool) -> Bool {
        if let override {
            log.notice("Notification ownership: forced by launch argument — this watch \(override ? "schedules" : "defers to the phone").")
            return false
        }

        let previous = schedulesLocally
        let next = decide(cached: previous, activated: activated, companionInstalled: companionInstalled)
        guard next != previous || store?.object(forKey: defaultsKey) == nil else {
            // Same answer as last launch, so nothing to re-arm. Still logged in
            // DEBUG: otherwise the decision is only ever observable on a watch
            // that has never resolved one, which means uninstalling the app to
            // watch it happen.
            #if DEBUG
            log.notice("Notification ownership: unchanged — this watch \(next ? "schedules" : "defers to the phone").")
            #endif
            return false
        }
        store?.set(next, forKey: defaultsKey)
        log.notice("Notification ownership: this watch \(next ? "schedules" : "defers to the phone").")
        return next != previous
    }

    #else

    /// The phone always owns scheduling — there is nothing to defer to.
    static var schedulesLocally: Bool { true }

    #endif
}
