//
//  HealthSample.swift
//  Fastino
//
//  Pure, Sendable value snapshots of the two Apple Health series the trends
//  screen overlays on fasting history (§4.8): nightly sleep and body mass.
//
//  Shaped deliberately like `FastRecord` — the aggregation and charting layers
//  operate exclusively on these, never on `HKSample`, so everything above the
//  HealthKit boundary is unit-testable without a HealthStore and without the
//  entitlement. Nothing here is ever persisted: HealthKit data may not be
//  synced to iCloud, and our SwiftData container mirrors to CloudKit, so these
//  live in memory for the lifetime of a screen and no longer.
//

import Foundation

/// The stages a sleep sample can carry. Deliberately coarser than HealthKit's
/// enum: the trends screen asks "how long were you asleep", not which stage,
/// and collapsing here keeps the aggregator free of HealthKit.
nonisolated enum SleepStage: Sendable, Equatable {
    /// In bed but not scored as asleep. Excluded from totals — it would inflate
    /// every night by the time spent reading.
    case inBed
    /// Scored awake mid-night. Excluded.
    case awake
    /// Any of HealthKit's asleep values (core, deep, REM, unspecified).
    case asleep
}

/// One raw sleep sample as it comes out of Health, before aggregation.
nonisolated struct SleepSpan: Equatable, Sendable {
    let start: Date
    let end: Date
    let stage: SleepStage

    init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One night's sleep credited to a calendar day — both *how much* and *when*.
nonisolated struct SleepNight: Equatable, Sendable, Identifiable {
    /// Start of the calendar day the sleep is credited to, in the time zone the
    /// series was built for.
    let date: Date
    /// Time actually asleep, with overlapping samples counted once. Includes
    /// naps, so it can exceed the main sleep's span.
    let asleep: TimeInterval
    /// When the night's *longest* stretch of sleep began and ended.
    ///
    /// The longest stretch rather than first-to-last, because an afternoon nap
    /// would otherwise stretch the night from last evening to this teatime and
    /// the "when did you sleep" chart (§4.8) would be nonsense.
    let mainSleepStart: Date
    let mainSleepEnd: Date

    var id: Date { date }

    var hours: Double { asleep / 3600 }

    /// The main stretch's length — shorter than `asleep` on a night with a nap,
    /// longer than nothing on a fragmented one.
    var mainSleepDuration: TimeInterval { mainSleepEnd.timeIntervalSince(mainSleepStart) }
}

/// One body-mass reading. Canonically kilograms — the display unit is a
/// presentation concern and comes from the user's Health preference.
nonisolated struct WeightPoint: Equatable, Sendable, Identifiable {
    let date: Date
    let kilograms: Double

    var id: Date { date }
}
