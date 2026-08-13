//
//  MetabolicZone.swift
//  Fastino
//
//  The three metabolic bands the Ember ring is built from. Pure value logic —
//  no SwiftData, no I/O — so the ring, the zone cards and the milestone
//  notifications all read the same boundaries.
//
//  Boundaries are **absolute hours into the fast, not fractions of the goal**:
//  fat burning starts around 12h whether you're on 16:8 or 20:4. A goal shorter
//  than a boundary simply means the ring never reaches that band (`span(for:)`
//  returns an empty range and it's shown as unreachable).
//

import Foundation

nonisolated enum MetabolicZone: Int, CaseIterable, Identifiable, Sendable {
    case burning    // 0–12h
    case fatBurn    // 12–14h
    case ketosis    // 14h+

    var id: Int { rawValue }

    /// Hours into the fast at which this zone opens.
    var startHours: Double {
        switch self {
        case .burning: 0
        case .fatBurn: 12
        case .ketosis: 14
        }
    }

    /// Hours at which the *next* zone opens; `nil` for the last, which is open-ended.
    var endHours: Double? {
        switch self {
        case .burning: 12
        case .fatBurn: 14
        case .ketosis: nil
        }
    }

    var name: String {
        switch self {
        case .burning: "Burning"
        case .fatBurn: "Fat burn"
        case .ketosis: "Ketosis"
        }
    }

    /// Label for the chip in the middle of the ring.
    var chipLabel: String {
        switch self {
        case .burning: "Burning zone"
        case .fatBurn: "Fat-burn zone"
        case .ketosis: "Ketosis zone"
        }
    }

    /// The range shown on the zone card — "0–12H", "12–14H", "14H+".
    var rangeLabel: String {
        if let endHours {
            return "\(Int(startHours))–\(Int(endHours))H"
        }
        return "\(Int(startHours))H+"
    }

    /// Body of the milestone notification fired when the zone opens.
    var milestoneBody: String {
        switch self {
        case .burning: "Your fast has started."
        case .fatBurn: "12 hours in — you're burning fat now."
        case .ketosis: "14 hours in — ketosis territory."
        }
    }

    /// The portion of a `goalHours` fast this zone occupies, in hours. Empty
    /// when the goal stops before the zone opens.
    func span(forGoalHours goalHours: Int) -> ClosedRange<Double>? {
        let goal = Double(goalHours)
        let lower = startHours
        let upper = min(endHours ?? goal, goal)
        guard upper > lower else { return nil }
        return lower...upper
    }

    /// Whether a fast with this goal can ever reach the zone.
    func isReachable(withGoalHours goalHours: Int) -> Bool {
        span(forGoalHours: goalHours) != nil
    }

    /// The zone a fast is in after `elapsed` seconds.
    static func current(elapsed: TimeInterval) -> MetabolicZone {
        let hours = elapsed / 3600
        if hours >= MetabolicZone.ketosis.startHours { return .ketosis }
        if hours >= MetabolicZone.fatBurn.startHours { return .fatBurn }
        return .burning
    }
}
