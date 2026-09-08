//
//  CompanionRelayTransport.swift
//  Fastino Watch App
//
//  The watch half of `CompanionRelay` (§4.4): the WatchConnectivity send that
//  wakes the phone so it can cancel a notification only it can cancel.
//
//  `transferUserInfo` rather than `updateApplicationContext` because waking a
//  suspended phone is the entire point — application context is delivered when
//  the opportunity arises, which is the same opportunism that let the reminder
//  fire in the first place.
//
//  Lives in the watch target, next to `CompanionProbe`, so WatchConnectivity
//  never links into the widget extensions that also compile `Shared/`. The
//  session is the probe's — one delegate per session — and this only sends on it.
//

import Foundation
import OSLog
import WatchConnectivity

@MainActor
enum CompanionRelayTransport {
    private static let log = Logger(subsystem: "com.baleware.fastino", category: "CompanionRelay")

    /// A payload raised before activation finished. Only the newest is kept —
    /// what the phone needs is the current state, not the sequence that reached it.
    private static var pending: CompanionRelayPayload?

    /// Wire `FastStore`'s announcements to this transport. Called once, at launch.
    static func install() {
        CompanionRelay.transport = { payload in send(payload) }
    }

    static func send(_ payload: CompanionRelayPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        guard session.activationState == .activated else {
            // Activation runs at launch and takes a moment; a fast started
            // inside that window would otherwise never be announced at all.
            pending = payload
            return
        }
        pending = nil

        // No phone app means this watch owns notifications itself
        // (`NotificationOwnership`), so there is nothing to tell.
        guard session.isCompanionAppInstalled else { return }

        // The newest state supersedes every earlier one, and a phone that has
        // been out of range for an afternoon should be woken once, not eleven
        // times to be walked through a day it can no longer act on.
        for transfer in session.outstandingUserInfoTransfers { transfer.cancel() }

        session.transferUserInfo(payload.userInfo)
        let state = payload.openFast == nil ? "no fast" : "fasting"
        log.info("Told the phone: \(state, privacy: .public)")
        SyncLog.shared.recordRelay("sent · \(state)")
    }

    /// Send what was raised before the session was ready. Called by
    /// `CompanionProbe` the moment activation completes.
    static func flush() {
        guard let pending else { return }
        send(pending)
    }
}
