//
//  FastingProvider.swift
//  Fastino
//
//  The timeline both widget surfaces run on (§4.5, §4.7).
//
//  `policy: .never` on purpose. Refreshes come from `FastStore.reloadWidgets()`,
//  which already runs on every mutation, so a surface updates the moment a fast
//  starts or ends on this device — and after a CloudKit import, via
//  `RemoteChangeRefresher`. Between those, the entries below carry the changes
//  that *are* predictable; the fast ending is not one of them, so there is no
//  useful refresh date to ask for.
//

import Foundation
import WidgetKit

nonisolated struct FastingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry {
        FastingEntry(
            date: Date(),
            fast: FastRecord(
                id: UUID(),
                start: Date().addingTimeInterval(-10 * 3600),
                end: nil,
                goalHours: 16
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(currentEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let now = Date()
        // Fetched once and reused for every entry: they all describe the same
        // fast at different instants, so re-reading the store per entry would
        // be ~50 fetches for one timeline.
        let openFast = FastingSnapshot.openFast()
        let entry = FastingEntry(date: now, fast: openFast)

        guard let fast = openFast else {
            // Nothing running: nothing changes until the app tells us it has.
            completion(Timeline(entries: [entry], policy: .never))
            return
        }

        let entries = [entry] + FastingTimeline.refreshDates(for: fast, now: now)
            .map { FastingEntry(date: $0, fast: fast) }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func currentEntry(at date: Date) -> FastingEntry {
        FastingEntry(date: date, fast: FastingSnapshot.openFast())
    }
}
