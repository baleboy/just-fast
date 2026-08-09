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
    /// Read straight from the store rather than passed in: the appearance
    /// override has to sit above the TabView so every tab — and the window's own
    /// background — picks it up. `nil` (no settings row yet, first launch)
    /// means "follow the system", same as `.system`.
    @Query private var settingsList: [AppSettings]

    private var preferredScheme: ColorScheme? {
        settingsList.first?.appearance.colorScheme
    }

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
        .preferredColorScheme(preferredScheme)
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
