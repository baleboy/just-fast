//
//  FastingTimeline.swift
//  Fastino
//
//  When a widget surface needs to be redrawn during a running fast (§4.5,
//  §4.7).
//
//  Pure, so it can be unit-tested — which matters, because the one bug this
//  has already had was invisible: omit the hour marks and the display sits on
//  "9h" for hours while the fast runs on underneath it.
//

import Foundation

nonisolated enum FastingTimeline {
    /// Every instant strictly after `now` at which the display changes:
    ///
    ///  • each whole-hour mark, because the label is a whole-hour count;
    ///  • each `MetabolicZone` boundary, which changes the title and colour;
    ///  • the goal, where the ring fills.
    ///
    /// All are known in advance from the fast's start, so nothing polls.
    ///
    /// - Parameter capHours: how far ahead to schedule hour marks. A fast past
    ///   this is already past anything `FastValidation` accepts, and WidgetKit
    ///   won't thank us for an unbounded timeline.
    static func refreshDates(for fast: FastRecord, now: Date, capHours: Int = 48) -> [Date] {
        let hourMarks = capHours >= 1
            ? (1...capHours).map { fast.start.addingTimeInterval(Double($0) * 3600) }
            : []
        let zoneMarks = MetabolicZone.allCases.map {
            fast.start.addingTimeInterval($0.startHours * 3600)
        }
        return Set(hourMarks + zoneMarks + [fast.goalReachedAt])
            .filter { $0 > now }
            .sorted()
    }
}
