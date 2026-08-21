//
//  Fastino_Watch_AppApp.swift
//  Fastino Watch App
//
//  Created by Francesco Balestrieri on 13.8.2026.
//
//  The watch app is standalone (§4.7): it opens the same CloudKit-backed
//  container as the phone rather than asking the phone for data, so starting
//  and ending a fast works with the phone out of range and reconciles when the
//  two next reach iCloud.
//

import SwiftData
import SwiftUI

@main
struct Fastino_Watch_App_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Observed here rather than in WatchSettingsView for the same reason as on
    /// the phone: mirroring reports success or failure within a second or so of
    /// the store opening, and an observer registered when a screen appears
    /// simply misses the event. It matters more here — a watch that silently
    /// fell back to a local store looks completely healthy while nothing it
    /// records ever reaches the phone.
    @State private var syncStatus = CloudSyncStatus()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(syncStatus)
                .task {
                    syncStatus.start()
                    // A change made on the phone arrives as an import, which is
                    // not a local write and so runs none of FastStore's side
                    // effects on its own — including the complication reload.
                    RemoteChangeRefresher.shared.start(container: AppContainer.shared)
                    // Resolves who owns notifications, and re-arms them if the
                    // answer changed since last launch (§4.4).
                    CompanionProbe.shared.activate()
                    reconcileNotifications()
                    await syncStatus.refreshAccountStatus()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Re-arms notifications, as FastinoApp does: scheduling
                    // otherwise only happens at write time, so anything that
                    // failed then — most often because permission hadn't been
                    // granted yet — would stay missing until the next edit. And
                    // it reloads the complication, which catches an import that
                    // completed while the app was backgrounded or not running,
                    // where the observer above was never alive to see it.
                    RemoteChangeRefresher.shared.refresh(container: AppContainer.shared)
                    Task { await syncStatus.refreshAccountStatus() }
                }
        }
        .modelContainer(AppContainer.shared)
    }

    @MainActor
    private func reconcileNotifications() {
        FastStore(context: AppContainer.shared.mainContext).reconcileNotifications()
    }
}
