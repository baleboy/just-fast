//
//  AppContainer.swift
//  Fastino
//
//  The shared SwiftData ModelContainer, used by the app and by App Intents so
//  every surface writes through the same store (§4.6, §7).
//
//  CloudKit (§3): the store mirrors to the CloudKit *private* database so the
//  iPhone and the watch share one dataset (§4.7). The container is named
//  explicitly rather than using `.automatic` — `.automatic` picks the first
//  container in the entitlement, so an app signed with the wrong profile would
//  silently sync to a *different* database and never converge. Naming it means
//  a provisioning mistake fails here, loudly, where we can log it.
//
//  If mirroring can't be set up at all (empty/unprovisioned
//  `com.apple.developer.icloud-container-identifiers`, or a schema CloudKit
//  rejects) we fall back to a local-only store rather than trapping, so the app
//  still runs on a machine without the container. Note that a signed-out or
//  offline *user* is not this case: the container initialises fine and
//  mirroring simply retries later.
//
//  App group (§4.5, §4.7): the store lives in a shared group container rather
//  than each target's own sandbox, because the widget/complication extension
//  runs in a *different process* and cannot read the app's sandbox. App groups
//  work between an app and its extensions on one device — unlike iPhone⇄Watch,
//  which is what CloudKit is for. Extensions that only *display* open the same
//  file read-only via `readOnly()`; the one that *acts* — the Control Center
//  toggle (§4.5) — uses `writableShared()`. Neither mirrors, so the app process
//  remains the only one running CloudKit.
//

import Foundation
import OSLog
import SwiftData

enum AppContainer {
    static let schema = Schema([Fast.self, AppSettings.self])

    /// The private-database container backing sync. Must match the value in
    /// both Fastino.entitlements and the watch app's entitlements exactly.
    static let cloudKitContainerID = "iCloud.com.baleware.fastino"

    /// Shared between each app and its extensions. Must be listed in every
    /// target's entitlements — a target without it silently gets its own
    /// private store and shows stale or empty data forever.
    ///
    /// `nonisolated` because `NotificationOwnership` is nonisolated and reads
    /// it to open the group's `UserDefaults`; the targets default to
    /// `MainActor` isolation, so an ordinary `static let` here is main-actor
    /// bound. It is an immutable `String`, so lifting the isolation is safe.
    nonisolated static let appGroupID = "group.com.baleware.fastino"

    private static let log = Logger(subsystem: "com.baleware.fastino", category: "AppContainer")

    /// The store file inside the group container, or `nil` when the app group
    /// isn't available — which means the entitlement is missing, so we log it
    /// and fall back rather than trapping.
    private static var groupStoreURL: URL? {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            log.error("App group \(appGroupID) unavailable — extensions will not see this store.")
            return nil
        }
        return directory.appending(path: "Fastino.store")
    }

    /// True when the store opened with mirroring requested.
    ///
    /// Deliberately *not* named "sync is working": `ModelContainer.init` returns
    /// successfully even when the container is unprovisioned, because mirroring
    /// is set up asynchronously afterwards. Real sync health arrives later, via
    /// `CloudSyncStatus`. This flag only means "we didn't fall back to local".
    private(set) static var isCloudKitConfigured = false

    static let shared: ModelContainer = {
        let cloudKit = groupStoreURL.map {
            ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .private(cloudKitContainerID))
        } ?? ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [cloudKit])
            isCloudKitConfigured = true
            return container
        } catch {
            log.error("CloudKit mirroring unavailable, falling back to a local store: \(error)")
        }

        let local = groupStoreURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Read-only view of the same store, for widget and complication processes.
    ///
    /// Mirroring is deliberately off here: the app process owns syncing, and
    /// running a second CloudKit mirror inside a short-lived extension is both
    /// wasteful and a source of conflicting writes. The extension sees whatever
    /// the app last synced into the shared file, which is what `WidgetCenter`
    /// reloads are for.
    static func readOnly() -> ModelContainer? {
        guard let url = groupStoreURL else { return nil }
        let configuration = ModelConfiguration(schema: schema, url: url, allowsSave: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            log.error("Could not open the shared store read-only: \(error)")
            return nil
        }
    }

    /// Read-write view of the same store, for the one extension that *acts*
    /// rather than merely displays: the Control Center toggle (§4.5).
    ///
    /// Mirroring is off here for exactly the reason it's off in `readOnly()` —
    /// the app process owns syncing, and a second CloudKit mirror inside a
    /// short-lived extension is wasteful and a source of conflicting writes.
    /// The write is not stranded: Core Data records it in persistent history,
    /// and the app's mirrored container exports it the next time the app runs.
    ///
    /// What this *does* cost is that the running app doesn't notice on its own
    /// — a cross-process write is not a CloudKit import. `RemoteChangeRefresher`
    /// is what closes that gap; see the `.NSPersistentStoreRemoteChange`
    /// observer there.
    static func writableShared() -> ModelContainer? {
        guard let url = groupStoreURL else { return nil }
        let configuration = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            log.error("Could not open the shared store for writing: \(error)")
            return nil
        }
    }

    /// An in-memory container for previews and tests.
    @MainActor
    static func inMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
