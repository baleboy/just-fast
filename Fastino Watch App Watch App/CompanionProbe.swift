//
//  CompanionProbe.swift
//  Fastino Watch App
//
//  Asks one question of WatchConnectivity: is the iPhone app installed?
//
//  That answer decides who schedules notifications (see `NotificationOwnership`).
//  It is the only thing this file does — no data crosses here. The two apps
//  share their fasts through CloudKit, and routing any of that through
//  WatchConnectivity instead would reintroduce the phone-must-be-reachable
//  dependency the standalone design exists to avoid.
//
//  `CompanionRelayTransport` sends on the same session, and is the one
//  deliberate exception: what it sends is scheduling state, not a fast. It
//  needs this file only for the moment activation completes, since a session
//  that hasn't activated can't transfer anything.
//
//  Lives in the watch target rather than `Shared/` so WatchConnectivity never
//  links into the iOS binary, which has no use for it.
//

import Foundation
import OSLog
import SwiftData
import WatchConnectivity

@MainActor
@Observable
final class CompanionProbe: NSObject {
    static let shared = CompanionProbe()

    /// Whether ownership has been resolved this launch. Until it is, callers
    /// that can afford to wait (the permission prompt) should, and callers that
    /// can't (scheduling) fall back to the cached answer.
    private(set) var hasResolved = false

    private let log = Logger(subsystem: "com.baleware.fastino", category: "CompanionProbe")
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    private override init() { super.init() }

    func activate() {
        #if DEBUG
        // The answer in force *before* the probe replies. Activation can take a
        // moment, and on an unpaired watch simulator it never completes at all —
        // so a log line that only fires on resolution can't be relied on to say
        // what the app is actually doing.
        log.notice("Notification ownership at launch: this watch \(NotificationOwnership.schedulesLocally ? "schedules" : "defers to the phone").")
        #endif

        guard WCSession.isSupported() else {
            // No session at all: nothing to defer to, so this watch owns
            // scheduling. Treat it as resolved rather than waiting forever.
            resolve(activated: true, companionInstalled: false)
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// The ownership answer, awaiting activation if it hasn't landed yet.
    ///
    /// Used only by the permission prompt, which must not ask on a watch whose
    /// phone owns notifications. Scheduling never waits on this — it reads the
    /// cached value and gets re-run when the answer arrives.
    func resolvedSchedulesLocally(timeout: Duration = .seconds(2)) async -> Bool {
        if hasResolved { return NotificationOwnership.schedulesLocally }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            // Activation is unusually slow; answer from the cache rather than
            // leaving the user staring at a button that did nothing.
            self.finishWaiters(with: NotificationOwnership.schedulesLocally)
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    fileprivate func resolve(activated: Bool, companionInstalled: Bool) {
        let changed = NotificationOwnership.update(
            activated: activated,
            companionInstalled: companionInstalled
        )
        hasResolved = hasResolved || activated

        if changed {
            // Ownership flipped. reconcileNotifications() re-runs every
            // schedule*, each of which cancels first — so this both clears what
            // we should no longer own and arms what we now do.
            FastStore(context: AppContainer.shared.mainContext).reconcileNotifications()
        }
        // Anything the store raised before the session was ready — a fast
        // started seconds after launch — goes out now (§4.4).
        if activated { CompanionRelayTransport.flush() }

        finishWaiters(with: NotificationOwnership.schedulesLocally)
    }

    private func finishWaiters(with value: Bool) {
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume(returning: value) }
    }
}

// WCSessionDelegate is required to be an NSObject conformance; only the two
// activation/state callbacks matter here. The rest of the protocol is about
// message passing we deliberately don't do.
extension CompanionProbe: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let activated = activationState == .activated
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in
            if let error {
                self.log.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
            }
            self.resolve(activated: activated, companionInstalled: installed)
        }
    }

    /// The user installed or deleted the iPhone app while the watch app was
    /// alive — ownership moves accordingly.
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in
            self.resolve(activated: true, companionInstalled: installed)
        }
    }
}
