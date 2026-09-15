//
//  HealthProvider.swift
//  Fastino
//
//  The boundary between the trends screen and Apple Health (§4.8). Everything
//  above this protocol is pure and testable; the one implementation that
//  imports HealthKit lives in `Fastino/Health/` because the feature is iOS-only
//  (this file sits in `Shared/` only so previews and tests can reach the
//  fixture without dragging HealthKit into the watch target).
//
//  Read authorization in HealthKit is deliberately opaque: once the user has
//  been asked, the system will not tell an app whether reads were granted —
//  denial is indistinguishable from "no samples". So there is no `.denied`
//  case here to switch on, and the UI must never claim permission is missing.
//  All we can honestly distinguish is "we have not asked yet" from "we have
//  asked, and this is what came back".
//

import Foundation

/// The unit the user reads weight in. HealthKit knows the user's preference;
/// we carry it as our own enum so the pure layer stays Foundation-only.
nonisolated enum MassUnit: Sendable, Equatable {
    case kilograms
    case pounds

    var unit: UnitMass { self == .kilograms ? .kilograms : .pounds }

    var symbol: String { self == .kilograms ? "kg" : "lb" }

    func value(fromKilograms kilograms: Double) -> Double {
        Measurement(value: kilograms, unit: UnitMass.kilograms)
            .converted(to: unit).value
    }
}

/// One load of everything the trends screen needs from Health.
nonisolated struct HealthSeries: Equatable, Sendable {
    var nights: [SleepNight] = []
    var weights: [WeightPoint] = []
    var massUnit: MassUnit = .kilograms

    static let empty = HealthSeries()

    var isEmpty: Bool { nights.isEmpty && weights.isEmpty }
}

nonisolated protocol HealthProvider: Sendable {
    /// Whether Health exists on this device at all.
    var isAvailable: Bool { get }

    /// False until the user has been shown the permission sheet. The only
    /// authorization fact HealthKit will tell us about reads.
    func hasBeenAsked() async -> Bool

    /// Prompts for read access if it hasn't been requested yet. Returns whether
    /// the request completed — *not* whether the user granted anything, which
    /// HealthKit will not disclose.
    @discardableResult
    func requestAccess() async -> Bool

    /// Sleep and weight over the same window, already aggregated to one entry
    /// per day and sorted oldest first.
    func series(days: Int, now: Date, timeZone: TimeZone) async -> HealthSeries
}

/// Deterministic stand-in for previews and tests. Generates a plausible month
/// of sleep and a slow downward weight drift without touching HealthKit.
///
/// The sleep goes through `SleepAggregator` as raw spans rather than being
/// handed over as finished nights, and the spans are **fragmented the way a
/// watch fragments them** — ninety minutes at a time with a few minutes awake
/// between. Handing over clean nights is what hid a real bug: the night chart
/// was drawing the longest unbroken doze instead of the night, which no
/// fixture-driven preview could ever have shown.
nonisolated struct FixtureHealthProvider: HealthProvider {
    var isAvailable = true
    var asked = true
    var series: HealthSeries?

    func hasBeenAsked() async -> Bool { asked }

    @discardableResult
    func requestAccess() async -> Bool { true }

    func series(days: Int, now: Date, timeZone: TimeZone) async -> HealthSeries {
        if let series { return series }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var spans: [SleepSpan] = []
        var weights: [WeightPoint] = []

        for offset in (0..<days).reversed() {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let date = cal.startOfDay(for: day)
            let wobble = sin(Double(offset) * 0.7)

            // A gap every eleventh day, so the empty-day handling is visible.
            if offset % 11 != 3 {
                // Asleep around 23:15 the evening before, with both the bedtime
                // and the night's length wobbling.
                let onset = -0.75 + wobble * 0.9
                let slept = 7.1 + wobble * 0.8
                var cursor = date.addingTimeInterval(onset * 3600)
                let wake = cursor.addingTimeInterval(slept * 3600)
                while cursor < wake {
                    let until = min(cursor.addingTimeInterval(90 * 60), wake)
                    spans.append(SleepSpan(start: cursor, end: until, stage: .asleep))
                    // Briefly awake, the way a watch scores it — short enough
                    // to stay one night.
                    cursor = until.addingTimeInterval(7 * 60)
                }
                // An afternoon nap now and then, which must land in the day's
                // total without stretching the night's band.
                if offset % 7 == 2 {
                    let nap = date.addingTimeInterval(14.5 * 3600)
                    spans.append(SleepSpan(start: nap, end: nap.addingTimeInterval(40 * 60), stage: .asleep))
                }
            }
            if offset % 3 == 0 {
                // A slow drift down, so the weekly means have something to
                // show, plus enough wobble that it isn't a straight line.
                let drift = Double(days - offset) * 0.02
                weights.append(WeightPoint(date: date, kilograms: 79.6 - drift + wobble * 0.25))
            }
        }

        return HealthSeries(
            nights: SleepAggregator.nights(from: spans, timeZone: timeZone),
            weights: weights,
            massUnit: .kilograms
        )
    }
}
