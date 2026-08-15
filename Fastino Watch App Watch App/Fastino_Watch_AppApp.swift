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

    var body: some Scene {
        WindowGroup {
            WatchTimerView()
                .task {
                    // Resolves who owns notifications, and re-arms them if the
                    // answer changed since last launch (§4.4).
                    CompanionProbe.shared.activate()
                    reconcileNotifications()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Mirrors FastinoApp: scheduling otherwise only happens at
                    // write time, so anything that failed then — most often
                    // because permission hadn't been granted yet — would stay
                    // missing until the next edit.
                    reconcileNotifications()
                }
        }
        .modelContainer(AppContainer.shared)
    }

    @MainActor
    private func reconcileNotifications() {
        FastStore(context: AppContainer.shared.mainContext).reconcileNotifications()
    }
}
