//
//  SleepAggregator.swift
//  Fastino
//
//  Turns raw Health sleep samples into one total per calendar day (§4.8). Pure —
//  no HealthKit import, no I/O — so the awkward parts are unit-tested directly
//  (`FastinoTests/SleepAggregatorTests.swift`).
//
//  Two things make this more than a sum:
//
//  1. **Samples overlap.** Health stores sleep as many short spans, and a user
//     with both an Apple Watch and a third-party tracker gets two full sets
//     covering the same night. Adding durations would report ~16 hours of sleep.
//     We take the *union* of the asleep spans instead, so every wall-clock
//     second counts exactly once no matter how many sources reported it.
//  2. **A night spans midnight.** It is credited to the day the user *woke*,
//     mirroring the rule that a goal day is the day a fast ended (§2). That
//     keeps one night on one day, in order, with no double counting — and it
//     lines the series up with the fasting bars without any further shifting.
//

import Foundation

nonisolated enum SleepAggregator {

    /// Nightly asleep totals, oldest first, one entry per day that has any
    /// sleep. Days with none are simply absent rather than zero — a gap in the
    /// chart is honest, a zero bar would claim the user didn't sleep.
    static func nights(from spans: [SleepSpan], timeZone: TimeZone) -> [SleepNight] {
        let asleep = spans
            .filter { $0.stage == .asleep && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !asleep.isEmpty else { return [] }

        // Union of the sorted spans. `<=` merges touching endpoints too, which
        // is the common case: consecutive core/deep/REM samples abut exactly.
        var merged: [(start: Date, end: Date)] = []
        for span in asleep {
            if let last = merged.last, span.start <= last.end {
                if span.end > last.end {
                    merged[merged.count - 1].end = span.end
                }
            } else {
                merged.append((span.start, span.end))
            }
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        // Credit each merged stretch to the day it ended on. A stretch is a
        // contiguous block of sleep, so "ended on" is "woke on".
        //
        // Two things are tracked per day: the total (all stretches, naps
        // included) and the longest single stretch, which is the night itself.
        var totals: [Int: (date: Date, asleep: TimeInterval, main: (start: Date, end: Date))] = [:]
        for interval in merged {
            let day = FastingEngine.dayNumber(of: interval.end, timeZone: timeZone)
            let startOfDay = cal.startOfDay(for: interval.end)
            let duration = interval.end.timeIntervalSince(interval.start)

            if var entry = totals[day] {
                entry.asleep += duration
                if duration > entry.main.end.timeIntervalSince(entry.main.start) {
                    entry.main = (interval.start, interval.end)
                }
                totals[day] = entry
            } else {
                totals[day] = (startOfDay, duration, (interval.start, interval.end))
            }
        }

        return totals.values
            .map {
                SleepNight(
                    date: $0.date,
                    asleep: $0.asleep,
                    mainSleepStart: $0.main.start,
                    mainSleepEnd: $0.main.end
                )
            }
            .sorted { $0.date < $1.date }
    }
}
