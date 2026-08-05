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

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    DemoSeeder.seedIfNeeded(context: AppContainer.shared.mainContext)
                    reconcileNotifications()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    reconcileNotifications()
                }
        }
        .modelContainer(AppContainer.shared)
    }

    /// Re-arm on launch and on every foreground. Scheduling otherwise only
    /// happens at write time, so anything that failed then — most often because
    /// permission hadn't been granted yet — would stay missing until the next
    /// edit (§4.4). Runs on both `.task` and the scene-phase change because
    /// `onChange` isn't guaranteed to observe the initial transition to active.
    @MainActor
    private func reconcileNotifications() {
        FastStore(context: AppContainer.shared.mainContext).reconcileNotifications()
    }
}
