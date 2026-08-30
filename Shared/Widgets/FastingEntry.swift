//
//  FastingEntry.swift
//  Fastino
//
//  What every widget surface displays: the open fast, as of an instant (§4.5,
//  §4.7).
//
//  Shared rather than per-extension because the iPhone Lock Screen widget and
//  the watch complication show the same fact from the same store, and a second
//  copy of "what counts as progress" is a second place for it to drift.
//
//  Marked `nonisolated` throughout: the app target defaults to `MainActor`
//  isolation and the widget extensions do not, so anything crossing that
//  boundary has to say what it is rather than inherit two different answers.
//

import Foundation
import SwiftData
import WidgetKit

nonisolated struct FastingEntry: TimelineEntry {
    let date: Date
    /// `nil` when no fast is running — the surface shows its ready state.
    let fast: FastRecord?

    var elapsed: TimeInterval? { fast?.duration(asOf: date) }
    var zone: MetabolicZone? { elapsed.map(MetabolicZone.current(elapsed:)) }
    /// Clamped: past the goal the ring stays full rather than wrapping around.
    var progress: Double {
        guard let fast, let elapsed else { return 0 }
        return min(elapsed / fast.goalInterval, 1)
    }
}

/// Reading the open fast from the shared store, for a process that only
/// displays it. The Control Center toggle, which *writes*, goes through
/// `FastStore` on `AppContainer.writableShared()` instead.
nonisolated enum FastingSnapshot {
    /// Fetched fresh each call: an extension is short-lived, and a container
    /// held across invocations would just serve stale data.
    static func openFast() -> FastRecord? {
        guard let container = AppContainer.readOnly() else { return nil }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Fast>(
            predicate: #Predicate { $0.end == nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.record
    }
}
