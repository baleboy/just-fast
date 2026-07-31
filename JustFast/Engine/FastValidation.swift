//
//  FastValidation.swift
//  JustFast
//
//  Pure validation for creating/editing fasts (§4.2). Enforced identically by
//  the app UI, App Intents, widgets and the watch so every write goes through
//  the same rules.
//    • end must be strictly after start
//    • a fast may not overlap an existing fast (touching endpoints are allowed)
//    • duration is capped at 7 days (typo guard)
//

import Foundation

nonisolated enum FastValidationError: Error, Equatable, Sendable {
    case endNotAfterStart
    case tooLong(maxDays: Int)
    case overlap(conflictID: UUID)

    var message: String {
        switch self {
        case .endNotAfterStart:
            "End time must be after the start time."
        case .tooLong(let maxDays):
            "A fast can’t be longer than \(maxDays) days. Double-check the times."
        case .overlap:
            "This overlaps another fast. Adjust the times so they don’t collide."
        }
    }
}

nonisolated enum FastValidation {
    static let maxDurationDays = 7
    static var maxDuration: TimeInterval { Double(maxDurationDays) * 86_400 }

    /// The half-open interval a fast occupies. An open fast extends to
    /// `.distantFuture` so nothing may be scheduled after it.
    private static func interval(start: Date, end: Date?) -> (Date, Date) {
        (start, end ?? .distantFuture)
    }

    /// Two half-open intervals overlap iff each starts before the other ends.
    /// Touching endpoints (a.end == b.start) do NOT overlap.
    private static func overlaps(_ a: (Date, Date), _ b: (Date, Date)) -> Bool {
        a.0 < b.1 && b.0 < a.1
    }

    /// Validate a proposed start/end against the existing set.
    /// - Parameter excludingID: the id of the fast being edited (so it isn't
    ///   compared against itself); nil for a brand-new fast.
    static func validate(
        start: Date,
        end: Date?,
        excludingID: UUID?,
        against existing: [FastRecord]
    ) throws {
        if let end {
            guard end > start else { throw FastValidationError.endNotAfterStart }
            guard end.timeIntervalSince(start) <= maxDuration else {
                throw FastValidationError.tooLong(maxDays: maxDurationDays)
            }
        }

        let candidate = interval(start: start, end: end)
        for other in existing where other.id != excludingID {
            if overlaps(candidate, interval(start: other.start, end: other.end)) {
                throw FastValidationError.overlap(conflictID: other.id)
            }
        }
    }
}
