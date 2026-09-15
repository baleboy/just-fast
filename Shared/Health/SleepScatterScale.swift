//
//  SleepScatterScale.swift
//  Fastino
//
//  The two axes behind the sleep scatter (§4.8) — the part of the panel that
//  isn't drawing.
//
//  The panel puts one dot on each night: across, the clock time eating stopped;
//  up, the hours asleep that followed. The x values are **signed hours from the
//  credited day's midnight**, so an ordinary 20:00 stop the evening before is
//  −4 and a stop just after midnight is +0.2 — continuous through midnight,
//  rather than 23:50 and 00:10 at opposite ends of a wrapped 0–24 axis. They
//  are drawn as they are, later to the right; nothing is negated or projected.
//
//  The y axis is hours asleep and is *not* zero-based: sleep lives between five
//  and nine hours, and a zero base would spend half the frame on a band nobody
//  ever falls into and squash the real nights into the top of it.
//

import Foundation

nonisolated enum SleepScatterScale {
    /// One scatter's scales, in the units they are drawn in.
    struct Scale: Equatable {
        /// Clock hours, signed from the credited day's midnight.
        let xDomain: ClosedRange<Double>
        /// Labelled positions along x, on whole clock hours.
        let xTicks: [Double]
        /// Hours asleep.
        let yDomain: ClosedRange<Double>
        /// Labelled positions along y, on whole hours.
        let yTicks: [Double]
        /// The start-time anchor in clock hours, or `nil` when including it
        /// would have flattened the real stops (below).
        let anchor: Double?
    }

    /// How far the extremes are held off the frame, so no dot is drawn on the
    /// boundary itself.
    private static let padding: Double = 0.5

    /// How far a stop may sit from the user's median stop and still set the
    /// x scale.
    ///
    /// `hoursFromMidnight` is measured against the *credited* day's midnight, so
    /// an ordinary evening stop is about −4 — but a 36-hour fast started on
    /// Monday morning and ended Tuesday evening lands at −16, and one morning
    /// like that would stretch the axis across a day and pile every real night
    /// into one column. Eight hours is wider than any evening varies (18.00 to
    /// 02.00), so the axis is set by the nights the panel is about; a stop
    /// outside it is still in the chart — and still read out by VoiceOver — it
    /// simply doesn't get to pull the frame apart.
    private static let stopSpread: Double = 8

    /// A clock axis wider than a day would label the same time twice.
    private static let maxSpan: Double = 24

    /// How far the anchor is allowed to widen the x scale before it's dropped.
    ///
    /// The anchor is context, not data: when it sits hours away from the times
    /// the user actually keeps, including it would squash the real ones into a
    /// band — and a schedule nobody is keeping is exactly when the actual times
    /// matter most.
    private static let anchorSlack: Double = 3

    /// The scales both axes are drawn against, from the nights that have both
    /// a stop and a sleep — pass them paired, one entry per night.
    ///
    /// `nil` when there is nothing to draw — the caller shows its empty state
    /// rather than two axes over a blank frame.
    static func scale(
        nights: [(stop: Double, asleep: Double)],
        anchor: Double? = nil
    ) -> Scale? {
        guard !nights.isEmpty else { return nil }

        let stops = core(of: nights.map(\.stop))
        var xLow = stops.min()! - padding
        var xHigh = stops.max()! + padding
        var kept: Double?
        if let anchor, max(xHigh, anchor) - min(xLow, anchor) <= (xHigh - xLow) + anchorSlack {
            xLow = min(xLow, anchor)
            xHigh = max(xHigh, anchor)
            kept = anchor
        }
        if xHigh - xLow > maxSpan {
            let middle = (xLow + xHigh) / 2
            xLow = middle - maxSpan / 2
            xHigh = middle + maxSpan / 2
        }

        // Sleep is never filtered — an odd night is still a night — and the
        // frame is snapped out to whole hours so the ticks are the edges.
        let sleeps = nights.map(\.asleep)
        let yLow = max(0, (sleeps.min()! - padding).rounded(.down))
        let yHigh = (sleeps.max()! + padding).rounded(.up)

        return Scale(
            xDomain: xLow...xHigh,
            xTicks: ticks(low: xLow, high: xHigh, step: xHigh - xLow > 6 ? 2 : 1),
            yDomain: yLow...yHigh,
            yTicks: ticks(low: yLow, high: yHigh, step: yHigh - yLow > 5 ? 2 : 1),
            anchor: kept
        )
    }

    /// The stops near enough the user's own median to set the scale. Always
    /// non-empty when `stops` is — the median is its own neighbour.
    private static func core(of stops: [Double]) -> [Double] {
        guard !stops.isEmpty else { return [] }
        let median = stops.sorted()[stops.count / 2]
        return stops.filter { abs($0 - median) <= stopSpread }
    }

    /// Ticks chosen on whole units rather than left to `.automatic`: an axis
    /// of times has to be labelled at times, and "7.5h" asleep is not a mark
    /// anyone reads a night against.
    private static func ticks(low: Double, high: Double, step: Double) -> [Double] {
        var ticks: [Double] = []
        var tick = (low / step).rounded(.up) * step
        while tick <= high {
            ticks.append(tick)
            tick += step
        }
        return ticks
    }
}
