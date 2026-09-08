//
//  FastinoApp.swift
//  Fastino
//
//  Created by Francesco Balestrieri on 29.7.2026.
//

import SwiftUI
import SwiftData

@main
struct FastinoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Owned here, not by SettingsView: CloudKit mirroring reports success or
    /// failure within a second or so of the store opening, so an observer that
    /// waits for Settings to appear misses the event entirely.
    @State private var syncStatus = CloudSyncStatus()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncStatus)
                .task {
                    syncStatus.start()
                    // A change made on the watch arrives as an import, which is
                    // not a local write and so runs none of FastStore's side
                    // effects on its own (§4.7).
                    RemoteChangeRefresher.shared.start(container: AppContainer.shared)
                    DemoSeeder.seedIfNeeded(context: AppContainer.shared.mainContext)
                    reconcileNotifications()
                    await syncStatus.refreshAccountStatus()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        SyncLog.shared.markBackground()
                        return
                    }
                    SyncLog.shared.markForeground()
                    // Reconciles notifications and reloads widgets in one pass —
                    // this also catches an import that completed while the app
                    // was backgrounded, where the observer saw the event but the
                    // context had no reason to be consulted.
                    RemoteChangeRefresher.shared.refresh(container: AppContainer.shared)
                    // The user may have just signed in to iCloud and come back.
                    Task { await syncStatus.refreshAccountStatus() }
                }
        }
        .modelContainer(AppContainer.shared)
    }

    /// Re-arm on launch and on every foreground. Scheduling otherwise only
    /// happens at write time, so anything that failed then — most often because
    /// permission hadn't been granted yet — would stay missing until the next
    /// edit (§4.4). Runs on `.task` as well as the scene-phase change (which
    /// reaches it via `RemoteChangeRefresher.refresh`) because `onChange` isn't
    /// guaranteed to observe the initial transition to active.
    @MainActor
    private func reconcileNotifications() {
        FastStore(context: AppContainer.shared.mainContext).reconcileNotifications()
    }
}
