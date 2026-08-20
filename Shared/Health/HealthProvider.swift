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

    /// Sleep and weight, already aggregated to one entry per day and sorted
    /// oldest first.
    ///
    /// The two windows differ because the two questions do. Sleep is read
    /// against the 30-day timeline; weight also feeds the weekly
    /// fasting-vs-weight pairing (§4.8), which needs a couple of months before
    /// it can say anything, since body weight moves on a slower clock than a
    /// single fast.
    func series(days: Int, weightDays: Int, now: Date, timeZone: TimeZone) async -> HealthSeries
}

/// Deterministic stand-in for previews and tests. Generates a plausible month
/// of sleep and a slow downward weight drift without touching HealthKit.
nonisolated struct FixtureHealthProvider: HealthProvider {
    var isAvailable = true
    var asked = true
    var series: HealthSeries?

    func hasBeenAsked() async -> Bool { asked }

    @discardableResult
    func requestAccess() async -> Bool { true }

    func series(days: Int, weightDays: Int, now: Date, timeZone: TimeZone) async -> HealthSeries {
        if let series { return series }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var nights: [SleepNight] = []
        var weights: [WeightPoint] = []

        for offset in (0..<max(days, weightDays)).reversed() {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let date = cal.startOfDay(for: day)
            let wobble = sin(Double(offset) * 0.7)

            // A gap every eleventh day, so the empty-day handling is visible.
            if offset < days, offset % 11 != 3 {
                // Asleep around 23:15 the evening before, with the night's
                // length wobbling, and a little fragmentation on top.
                let onset = -0.75 + wobble * 0.45
                let slept = 7.1 + wobble * 0.8
                let start = date.addingTimeInterval(onset * 3600)
                nights.append(
                    SleepNight(
                        date: date,
                        asleep: slept * 3600,
                        mainSleepStart: start,
                        mainSleepEnd: start.addingTimeInterval((slept + 0.35) * 3600)
                    )
                )
            }
            if offset % 3 == 0 {
                // A slow drift down, so the weekly pairing has something to
                // find, plus enough wobble that it isn't a straight line.
                let drift = Double(max(days, weightDays) - offset) * 0.02
                weights.append(WeightPoint(date: date, kilograms: 79.6 - drift + wobble * 0.25))
            }
        }

        return HealthSeries(nights: nights, weights: weights, massUnit: .kilograms)
    }
}
