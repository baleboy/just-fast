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
    var body: some Scene {
        WindowGroup {
            WatchTimerView()
        }
        .modelContainer(AppContainer.shared)
    }
}
