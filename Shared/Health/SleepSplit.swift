//
//  SleepSplit.swift
//  Fastino
//
//  The one summary the sleep scatter (§4.8) carries: the average night either
//  side of the time the user meant to stop eating.
//
//  It is a pair of means, not a fit. The panels' rule is that the app shows
//  what happened and the user interprets, and this stays on that side of it:
//  "before 20.00 you averaged 7h 20m, after it 6h 35m" is two facts about the
//  nights that happened, read against a line the user drew themselves. A
//  fitted line, a coefficient, or a sentence with "because" in it would be the
//  app's claim about why, and that is what was cut.
//
//  Two groups rather than clock-hour bins: thirty nights split six ways gives
//  groups of two or three, and an average of two nights is noise dressed as a
//  fact. And nothing at all unless both sides have enough nights to average.
//

import Foundation

nonisolated enum SleepSplit {
    /// One side of the split.
    struct Group: Equatable {
        /// Mean hours asleep.
        let meanHours: Double
        let nights: Int
    }

    struct Summary: Equatable {
        /// The dividing stop time, in signed hours from midnight.
        let threshold: Double
        /// Whether `threshold` is the user's anchor or, lacking one, their
        /// median stop — the caption says which.
        let isAnchor: Bool
        /// Nights that stopped at or before the threshold.
        let earlier: Group
        /// Nights that stopped after it.
        let later: Group
    }

    /// Fewer nights than this on either side and there is nothing honest to
    /// say — the scatter stands alone.
    static let minimumNights = 3

    /// The split, or `nil` when either side is too thin to average.
    static func summary(
        nights: [(stop: Double, asleep: Double)],
        anchor: Double?
    ) -> Summary? {
        guard nights.count >= minimumNights * 2 else { return nil }
        let threshold: Double
        let isAnchor: Bool
        if let anchor {
            threshold = anchor
            isAnchor = true
        } else {
            // The lower median, so an even count splits into equal halves
            // rather than the upper one leaving the later side a night short.
            threshold = nights.map(\.stop).sorted()[(nights.count - 1) / 2]
            isAnchor = false
        }
        let earlier = nights.filter { $0.stop <= threshold }
        let later = nights.filter { $0.stop > threshold }
        guard earlier.count >= minimumNights, later.count >= minimumNights else { return nil }
        return Summary(
            threshold: threshold,
            isAnchor: isAnchor,
            earlier: group(earlier),
            later: group(later)
        )
    }

    private static func group(_ nights: [(stop: Double, asleep: Double)]) -> Group {
        Group(
            meanHours: nights.map(\.asleep).reduce(0, +) / Double(nights.count),
            nights: nights.count
        )
    }
}
