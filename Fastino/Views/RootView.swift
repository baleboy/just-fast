//
//  RootView.swift
//  Fastino
//
//  Navigation shell: three tabs — the timer (home), Stats and Settings (§4.1,
//  §4.3). Each tab owns its NavigationStack so pushes stay inside their tab
//  (Stats → History) and each keeps its own title.
//

import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Timer", systemImage: "timer") {
                NavigationStack {
                    TimerView()
                        .navigationTitle("Fastino")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab("Stats", systemImage: "chart.bar") {
                NavigationStack {
                    StatsView()
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(Theme.amber)
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
