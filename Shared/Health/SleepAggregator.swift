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
//  3. **A night is not one unbroken block.** An Apple Watch scores brief
//     awakenings all night long, so the union above leaves a night as five or
//     ten stretches with short awake gaps between them. Grouping them back into
//     one night is what `nightGap` does — see below.
//

import Foundation

nonisolated enum SleepAggregator {

    /// How long the user can be awake before it counts as a new sleep, rather
    /// than a break in the one they were having.
    ///
    /// This is the number that makes `mainSleepStart`/`End` mean "the night"
    /// instead of "the longest unbroken doze". It used to be absent: the main
    /// sleep was the single longest contiguous stretch, chosen so an afternoon
    /// nap couldn't run the night from last evening to this teatime. That
    /// defence was right and the mechanism was wrong — a watch scores several
    /// brief awakenings a night, so the longest run is routinely an hour or two
    /// and an eight-hour night was drawn as a two-hour smear at a random offset
    /// inside it.
    ///
    /// Three hours separates the two cases comfortably. Waking at 05.00 and
    /// dropping off again at 06.00 is one night; a nap eight hours after
    /// getting up is its own sleep, counted in the day's total and never
    /// allowed to stretch the night's span.
    private static let nightGap: TimeInterval = 3 * 3600

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

        // Group the stretches back into sleeps: anything resumed within
        // `nightGap` is the same sleep, however many times it was interrupted.
        // `asleep` stays the sum of the stretches, so the awake gaps inside a
        // sleep are in its span but never in its total.
        var sleeps: [(start: Date, end: Date, asleep: TimeInterval)] = []
        for interval in merged {
            let duration = interval.end.timeIntervalSince(interval.start)
            if var last = sleeps.last, interval.start.timeIntervalSince(last.end) < nightGap {
                last.end = interval.end
                last.asleep += duration
                sleeps[sleeps.count - 1] = last
            } else {
                sleeps.append((interval.start, interval.end, duration))
            }
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        // Credit each sleep to the day it ended on — "ended on" is "woke on".
        //
        // Two things are tracked per day: the total (every sleep, naps
        // included) and the *main* one, which is the night itself. Main is the
        // sleep with the most actual sleep in it, not the widest span: a long
        // restless doze shouldn't outrank the night it sits beside.
        var totals: [Int: (date: Date, asleep: TimeInterval, main: (start: Date, end: Date, asleep: TimeInterval))] = [:]
        for sleep in sleeps {
            let day = FastingEngine.dayNumber(of: sleep.end, timeZone: timeZone)
            let startOfDay = cal.startOfDay(for: sleep.end)

            if var entry = totals[day] {
                entry.asleep += sleep.asleep
                if sleep.asleep > entry.main.asleep { entry.main = sleep }
                totals[day] = entry
            } else {
                totals[day] = (startOfDay, sleep.asleep, sleep)
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
