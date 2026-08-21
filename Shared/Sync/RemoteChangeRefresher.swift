//
//  RemoteChangeRefresher.swift
//  Fastino
//
//  Acting on a change that arrived from *another* device (§3, §4.7).
//
//  SwiftData republishes `@Query` when a mirrored change merges, so the on-screen
//  UI heals itself. Nothing else does. The two side effects `FastStore` performs
//  on every local write — reconciling notifications and reloading the widget
//  timeline — are wired to the write path, and a CloudKit import is not a write
//  on this device. So until this existed, ending a fast on the phone left the
//  watch with the goal notification still armed and, worse, the complication
//  still counting up.
//
//  The complication is the sharp edge: `WidgetCenter` reloads are process- and
//  device-local, so the phone calling `reloadAllTimelines()` never touches a
//  watch face, and `FastingProvider` hands back `policy: .never` because it
//  expects to be reloaded explicitly. Between the two, a watch complication had
//  no path back to the truth except the watch itself starting or ending a fast.
//
//  Only completed, successful `.import` events count: `.setup` and `.export`
//  carry no new local data, and an event still in flight has no verdict.
//

import CoreData
import Foundation
import OSLog
import SwiftData

@MainActor
final class RemoteChangeRefresher {
    static let shared = RemoteChangeRefresher()

    private var observer: (any NSObjectProtocol)?
    private let log = Logger(subsystem: "com.baleware.fastino", category: "CloudSync")

    private init() {}

    /// Begin reacting to imports. Idempotent, and a no-op when mirroring was
    /// never configured — there is nothing to import from.
    func start(container: ModelContainer) {
        guard observer == nil, AppContainer.isCloudKitConfigured else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import,
                  event.endDate != nil,
                  event.succeeded
            else { return }
            Task { @MainActor [weak self] in
                self?.refresh(container: container)
            }
        }
    }

    /// Re-run the side effects a local write would have run.
    ///
    /// Safe to call redundantly: both methods are idempotent, and an import that
    /// changed nothing relevant simply re-arms what was already armed.
    func refresh(container: ModelContainer) {
        log.info("Remote change imported — reconciling notifications and reloading widgets.")
        let store = FastStore(context: container.mainContext)
        store.reconcileNotifications()
        store.reloadWidgets()
    }
}
