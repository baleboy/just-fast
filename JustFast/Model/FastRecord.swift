//
//  FastRecord.swift
//  JustFast
//
//  A pure, Sendable value snapshot of a fast. The streak/stat engine and the
//  validation logic operate exclusively on these — never on SwiftData model
//  objects — so the engine stays a pure function of `[FastRecord]` + time zone
//  and is trivially unit-testable without a ModelContext (§7).
//

import Foundation

nonisolated struct FastRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date?
    /// Snapshot of the protocol goal (hours) at the time the fast started.
    let goalHours: Int

    init(id: UUID = UUID(), start: Date, end: Date?, goalHours: Int) {
        self.id = id
        self.start = start
        self.end = end
        self.goalHours = goalHours
    }

    var isOpen: Bool { end == nil }

    var goalInterval: TimeInterval { TimeInterval(goalHours) * 3600 }

    /// The instant at which the goal is reached.
    var goalReachedAt: Date { start.addingTimeInterval(goalInterval) }

    /// Elapsed duration. For an open fast this is measured against `now`.
    func duration(asOf now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }

    /// Final duration of a closed fast; `nil` while open.
    var finalDuration: TimeInterval? {
        guard let end else { return nil }
        return end.timeIntervalSince(start)
    }

    /// A completed fast is one whose duration ≥ its snapshotted goal (§2).
    /// Only closed fasts can be completed.
    var isGoalMet: Bool {
        guard let finalDuration else { return false }
        return finalDuration >= goalInterval
    }
}
