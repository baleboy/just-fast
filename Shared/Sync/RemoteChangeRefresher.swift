//
//  RemoteChangeRefresher.swift
//  Fastino
//
//  Acting on a change this process didn't make — from another *device* (§3,
//  §4.7) or another *process* on this one (§4.5).
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
//  The Control Center toggle (§4.5) is the same problem arriving down a
//  different pipe. It writes to the shared store from the widget extension —
//  a local write, in another process, so no CloudKit event is posted at all.
//  `.NSPersistentStoreRemoteChange` is what announces those, and unlike the
//  import path it is **not** gated on mirroring being configured: a local-only
//  fallback store still has an extension writing to it.
//
//  Both paths then need the same thing the import path always needed and got
//  for free — `mainContext.rollback()`. Objects the context already registered
//  keep the snapshot they were faulted with, so without it `TimerView` shows
//  the state from before the control was tapped, right up until relaunch.
//

import CoreData
import Foundation
import OSLog
import SwiftData

@MainActor
final class RemoteChangeRefresher {
    static let shared = RemoteChangeRefresher()

    private var isObservingImports = false
    private var crossProcessObserver: (any NSObjectProtocol)?
    private let log = Logger(subsystem: "com.baleware.fastino", category: "CloudSync")

    private init() {}

    /// Begin reacting to changes made elsewhere. Idempotent.
    func start(container: ModelContainer) {
        startCrossProcess(container: container)

        // The import half is a no-op when mirroring was never configured —
        // there is nothing to import from. The cross-process half above is not,
        // which is why it is started first and separately.
        guard !isObservingImports, AppContainer.isCloudKitConfigured else { return }
        isObservingImports = true

        // One observer of `eventChangedNotification` lives in `SyncLog`; this
        // subscribes to it. The filter is exactly the one this class used to
        // apply itself: only a completed, successful import carries data this
        // device hasn't already acted on.
        SyncLog.shared.start()
        SyncLog.shared.subscribe { [weak self] event in
            guard event.kind == .importing, event.isFinished, event.succeeded else { return }
            self?.refresh(container: container)
        }
    }

    /// A write made by another *process* against the same app-group store —
    /// today, the Control Center toggle (§4.5).
    ///
    /// Deliberately ungated on `isCloudKitConfigured`: the extension writes to
    /// whichever store the app opened, mirrored or not.
    private func startCrossProcess(container: ModelContainer) {
        guard crossProcessObserver == nil else { return }

        crossProcessObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(container: container)
            }
        }
    }

    /// Re-run the side effects a local write would have run, and let the
    /// context see what the other process wrote.
    ///
    /// Safe to call redundantly: every step is idempotent, and a change that
    /// touched nothing relevant simply re-arms what was already armed.
    func refresh(container: ModelContainer) {
        log.info("Change from elsewhere — refaulting, reconciling notifications and reloading widgets.")
        // Refault the registered objects. There is nothing of our own to lose:
        // `FastStore` saves synchronously on every mutation, so the main context
        // never holds an unsaved edit. Without this the reconcile below reads
        // the same stale snapshot the UI is showing.
        container.mainContext.rollback()
        let store = FastStore(context: container.mainContext)
        store.reconcileNotifications()
        store.reloadWidgets()
    }
}
