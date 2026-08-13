//
//  CloudSyncStatus.swift
//  Fastino
//
//  Whether CloudKit mirroring is actually working (§3).
//
//  This exists because the obvious check doesn't work: `ModelContainer.init`
//  succeeds even when the iCloud container is missing or unprovisioned, since
//  mirroring is configured asynchronously *after* the store opens. So
//  `AppContainer.isCloudKitConfigured` only tells us we asked for sync — not
//  that any data moved.
//
//  `NSPersistentCloudKitContainer.eventChangedNotification` is the supported
//  way to find out. It's a global notification, so we can observe it without a
//  handle on the container itself, which SwiftData doesn't vend.
//
//  The state starts `.unknown` and only becomes `.unavailable` once a setup or
//  sync event has actually failed — a warning that flashes up during normal
//  startup would be worse than no warning at all.
//
//  Observation starts at app launch rather than when Settings appears: mirroring
//  fails within a second or so of the store opening, and an observer registered
//  later simply misses the notification. The account-status check covers the
//  same gap from the other side, and catches the overwhelmingly common cause
//  (not signed in to iCloud) without depending on a race at all.
//

import CloudKit
import CoreData
import Foundation
import OSLog

@MainActor
@Observable
final class CloudSyncStatus {
    enum Health: Equatable {
        /// No verdict yet — show nothing.
        case unknown
        case healthy
        case unavailable(reason: String)
    }

    private(set) var health: Health = .unknown

    /// `nonisolated(unsafe)` so `deinit` can unregister: deinit is nonisolated,
    /// and this is only ever written once from the main actor in `start()`.
    @ObservationIgnored
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?
    private let log = Logger(subsystem: "com.baleware.fastino", category: "CloudSync")

    /// Re-check the iCloud account. Cheap, and worth repeating on foreground —
    /// the user may have just signed in (or out) in iOS Settings.
    func refreshAccountStatus() async {
        guard AppContainer.isCloudKitConfigured else { return }
        do {
            let status = try await CKContainer(identifier: AppContainer.cloudKitContainerID).accountStatus()
            switch status {
            case .available:
                // Don't overwrite a failure the mirroring events already found —
                // a valid account doesn't by itself prove sync is working.
                if health == .unknown { health = .healthy }
            case .noAccount:
                health = .unavailable(
                    reason: "You’re not signed in to iCloud, so this device isn’t syncing."
                )
            case .restricted, .couldNotDetermine, .temporarilyUnavailable:
                health = .unavailable(
                    reason: "Fastino can’t reach iCloud right now, so this device isn’t syncing."
                )
            @unknown default:
                break
            }
        } catch {
            log.error("Could not read iCloud account status: \(error.localizedDescription)")
        }
    }

    func start() {
        guard observer == nil else { return }

        guard AppContainer.isCloudKitConfigured else {
            // We never even got as far as requesting mirroring.
            health = .unavailable(reason: "Your fasts are saved on this device only.")
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event else { return }
            // Ignore events still in flight — only completed ones carry a verdict.
            guard event.endDate != nil else { return }
            let succeeded = event.succeeded
            let description = event.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.apply(succeeded: succeeded, error: description)
            }
        }
    }

    private func apply(succeeded: Bool, error: String?) {
        if succeeded {
            health = .healthy
            return
        }
        log.error("CloudKit sync event failed: \(error ?? "unknown error")")
        health = .unavailable(
            reason: "Fastino can’t reach iCloud, so this device isn’t syncing. Check that you’re signed in to iCloud."
        )
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
