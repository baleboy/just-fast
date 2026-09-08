//
//  FastinoApp.swift
//  Fastino
//
//  Created by Francesco Balestrieri on 29.7.2026.
//

import SwiftUI
import SwiftData

/// Exists for one reason: WatchConnectivity has to be listening on a *background*
/// launch (§4.4). The watch wakes this app by transferring the fact that a fast
/// started, and a scene's `.task` is no place to activate the session — the
/// system may launch the process without ever bringing the scene up.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CompanionListener.shared.start()
        return true
    }
}

@main
struct FastinoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                    // Idempotent; the app delegate has normally done this
                    // already. Here too so a launch path that somehow skipped
                    // the delegate still ends up listening.
                    CompanionListener.shared.start()
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
