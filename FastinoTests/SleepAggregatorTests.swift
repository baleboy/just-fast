//
//  SleepAggregatorTests.swift
//  FastinoTests
//
//  The awkward half of the Health integration (§4.8): overlapping samples from
//  multiple sources, nights that span midnight, and DST. All pure — no
//  HealthKit, no entitlement, no HealthStore.
//

import Foundation
import Testing
@testable import Fastino

// MARK: - Helpers

private let utc = TimeZone(identifier: "UTC")!
private let ny = TimeZone(identifier: "America/New_York")!

private func date(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0,
    tz: TimeZone = utc
) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: comps)!
}

private func span(_ start: Date, _ end: Date, _ stage: SleepStage = .asleep) -> SleepSpan {
    SleepSpan(start: start, end: end, stage: stage)
}

private func hours(_ interval: TimeInterval) -> Double {
    (interval / 3600 * 1000).rounded() / 1000
}

@Suite("Sleep aggregation")
struct SleepAggregatorTests {

    @Test("Empty input yields no nights")
    func empty() {
        #expect(SleepAggregator.nights(from: [], timeZone: utc).isEmpty)
    }

    @Test("A single night is credited to the day the user woke")
    func creditsWakeDay() {
        let spans = [span(date(2026, 3, 10, 23), date(2026, 3, 11, 7))]
        let nights = SleepAggregator.nights(from: spans, timeZone: utc)

        #expect(nights.count == 1)
        #expect(nights[0].date == date(2026, 3, 11))
        #expect(hours(nights[0].asleep) == 8)
    }

    @Test("Contiguous stage samples merge into one stretch")
    func contiguousStages() {
        let spans = [
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 1)),
            span(date(2026, 3, 11, 1), date(2026, 3, 11, 3)),
            span(date(2026, 3, 11, 3), date(2026, 3, 11, 6, 30))
        ]
        let nights = SleepAggregator.nights(from: spans, timeZone: utc)

        #expect(nights.count == 1)
        #expect(hours(nights[0].asleep) == 7.5)
    }

    @Test("Overlapping samples from two sources count once")
    func twoSourcesDoNotDoubleCount() {
        // A Watch and a third-party tracker both cover the same eight hours,
        // the second offset by an hour. The union is nine, not sixteen.
        let watch = [span(date(2026, 3, 10, 23), date(2026, 3, 11, 7))]
        let other = [span(date(2026, 3, 11, 0), date(2026, 3, 11, 8))]
        let nights = SleepAggregator.nights(from: watch + other, timeZone: utc)

        #expect(nights.count == 1)
        #expect(hours(nights[0].asleep) == 9)
    }

    @Test("A sample fully contained in another adds nothing")
    func containedSample() {
        let spans = [
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 7)),
            span(date(2026, 3, 11, 2), date(2026, 3, 11, 3))
        ]
        let nights = SleepAggregator.nights(from: spans, timeZone: utc)

        #expect(hours(nights[0].asleep) == 8)
    }

    @Test("In-bed and awake samples are excluded")
    func excludesNonAsleepStages() {
        let spans = [
            span(date(2026, 3, 10, 22), date(2026, 3, 11, 8), .inBed),
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 7)),
            span(date(2026, 3, 11, 3), date(2026, 3, 11, 3, 20), .awake)
        ]
        let nights = SleepAggregator.nights(from: spans, timeZone: utc)

        // Ten hours in bed, twenty minutes awake — still eight hours asleep.
        // (The awake span sits inside the asleep one; Health reports both.)
        #expect(hours(nights[0].asleep) == 8)
    }

    @Test("A nap and the night before sum into the same day")
    func napAndNightSum() {
        let spans = [
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 7)),
            span(date(2026, 3, 11, 14), date(2026, 3, 11, 14, 45))
        ]
        let nights = SleepAggregator.nights(from: spans, timeZone: utc)

        #expect(nights.count == 1)
        #expect(hours(nights[0].asleep) == 8.75)
    }

    @Test("The main sleep is the night, not the whole day's first-to-last")
    func napDoesNotStretchTheNight() {
        // An afternoon nap would otherwise run the "when did you sleep" bar
        // from last evening to this teatime.
        let spans = [
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 7)),
            span(date(2026, 3, 11, 14), date(2026, 3, 11, 14, 45))
        ]
        let night = SleepAggregator.nights(from: spans, timeZone: utc)[0]

        #expect(night.mainSleepStart == date(2026, 3, 10, 23))
        #expect(night.mainSleepEnd == date(2026, 3, 11, 7))
        #expect(hours(night.mainSleepDuration) == 8)
    }

    @Test("A fragmented night reports a span longer than the time asleep")
    func fragmentedNight() {
        // Awake for an hour in the middle. It is still one night: the span
        // covers the hour, the total does not.
        let spans = [
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 3)),
            span(date(2026, 3, 11, 4), date(2026, 3, 11, 7))
        ]
        let night = SleepAggregator.nights(from: spans, timeZone: utc)[0]

        #expect(hours(night.asleep) == 7)
        #expect(night.mainSleepStart == date(2026, 3, 10, 23))
        #expect(night.mainSleepEnd == date(2026, 3, 11, 7))
        #expect(hours(night.mainSleepDuration) == 8)
    }

    /// The regression that sent this back to the drawing board. A watch scores
    /// brief awakenings all night, so an eight-hour night arrives as a dozen
    /// short stretches — and taking the longest of them drew it as a two-hour
    /// smear at a random offset inside the night.
    @Test("A watch-scored night is one band, not its longest doze")
    func watchScoredNightIsOneNight() {
        var spans: [SleepSpan] = []
        var cursor = date(2026, 3, 10, 23)
        // 90 minutes asleep, 6 minutes awake, over and over.
        while cursor < date(2026, 3, 11, 7) {
            let wake = min(cursor.addingTimeInterval(90 * 60), date(2026, 3, 11, 7))
            spans.append(span(cursor, wake))
            cursor = wake.addingTimeInterval(6 * 60)
        }
        #expect(spans.count > 4)

        let night = SleepAggregator.nights(from: spans, timeZone: utc)[0]

        // One band, spanning the whole night — not the ninety minutes of its
        // longest doze.
        #expect(night.mainSleepStart == spans.first!.start)
        #expect(night.mainSleepEnd == spans.last!.end)
        #expect(hours(night.mainSleepDuration) > 7.5)
        // The awake minutes are in the span but not in the total.
        #expect(night.asleep < night.mainSleepDuration)
        #expect(hours(night.asleep) > 7.4)
    }

    /// Getting up at 05.00 and going back to bed at 06.00 is still one night;
    /// the gap rule has to be wider than a restless hour.
    @Test("An hour up in the small hours is still one night")
    func anHourUpIsStillOneNight() {
        let spans = [
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 5)),
            span(date(2026, 3, 11, 6), date(2026, 3, 11, 8))
        ]
        let night = SleepAggregator.nights(from: spans, timeZone: utc)[0]

        #expect(night.mainSleepEnd == date(2026, 3, 11, 8))
        #expect(hours(night.mainSleepDuration) == 9)
    }

    /// The main sleep is the one with the most sleep in it, not the widest
    /// span — a long restless doze must not outrank the night beside it.
    @Test("Main sleep is the most sleep, not the widest span")
    func mainSleepIsTheMostSleep() {
        let spans = [
            // A solid seven-hour night.
            span(date(2026, 3, 10, 23), date(2026, 3, 11, 6)),
            // An eight-hour afternoon of dozing that adds up to three.
            span(date(2026, 3, 11, 12), date(2026, 3, 11, 13, 30)),
            span(date(2026, 3, 11, 17), date(2026, 3, 11, 18, 30)),
            span(date(2026, 3, 11, 19, 30), date(2026, 3, 11, 20))
        ]
        let night = SleepAggregator.nights(from: spans, timeZone: utc)[0]

        #expect(night.mainSleepStart == date(2026, 3, 10, 23))
        #expect(night.mainSleepEnd == date(2026, 3, 11, 6))
    }

    @Test("Overlapping sources give one span, not two")
    func mainSleepUsesTheUnion() {
        let watch = [span(date(2026, 3, 10, 23), date(2026, 3, 11, 7))]
        let other = [span(date(2026, 3, 11, 0), date(2026, 3, 11, 8))]
        let night = SleepAggregator.nights(from: watch + other, timeZone: utc)[0]

        #expect(night.mainSleepStart == date(2026, 3, 10, 23))
        #expect(night.mainSleepEnd == date(2026, 3, 11, 8))
    }

    @Test("Separate nights land on separate days, oldest first")
    func separateNights() {
        let spans = [
            span(date(2026, 3, 11, 23), date(2026, 3, 12, 7)),
            span(date(2026, 3, 9, 23), date(2026, 3, 10, 6))
        ]
        let nights = SleepAggregator.nights(from: spans, timeZone: utc)

        #expect(nights.map(\.date) == [date(2026, 3, 10), date(2026, 3, 12)])
        #expect(nights.map { hours($0.asleep) } == [7, 8])
    }

    @Test("Duration stays absolute across a DST spring-forward")
    func springForward() {
        // 2026-03-08, America/New_York: 02:00 jumps to 03:00. Going to bed at
        // 23:00 and waking at 07:00 wall-clock is seven real hours, and the
        // night belongs to the 8th.
        let spans = [span(date(2026, 3, 7, 23, tz: ny), date(2026, 3, 8, 7, tz: ny))]
        let nights = SleepAggregator.nights(from: spans, timeZone: ny)

        #expect(nights.count == 1)
        #expect(nights[0].date == date(2026, 3, 8, tz: ny))
        #expect(hours(nights[0].asleep) == 7)
    }

    @Test("Zero-length and inverted samples are dropped")
    func degenerateSamples() {
        let spans = [
            span(date(2026, 3, 11, 2), date(2026, 3, 11, 2)),
            span(date(2026, 3, 11, 5), date(2026, 3, 11, 4))
        ]
        #expect(SleepAggregator.nights(from: spans, timeZone: utc).isEmpty)
    }

    @Test("The same night in a different time zone can land on a different day")
    func timeZoneShiftsTheDay() {
        // Waking at 03:00 UTC is the 11th in UTC but still the 10th in New York.
        let spans = [span(date(2026, 3, 10, 20), date(2026, 3, 11, 3))]

        #expect(SleepAggregator.nights(from: spans, timeZone: utc)[0].date == date(2026, 3, 11))
        #expect(SleepAggregator.nights(from: spans, timeZone: ny)[0].date == date(2026, 3, 10, tz: ny))
    }
}

@Suite("Weight series")
struct WeightSeriesTests {

    @Test("Empty input yields no points")
    func empty() {
        #expect(WeightSeries.daily([], timeZone: utc).isEmpty)
    }

    @Test("The last reading of a day wins")
    func lastReadingWins() {
        let points = [
            WeightPoint(date: date(2026, 3, 11, 7), kilograms: 78.9),
            WeightPoint(date: date(2026, 3, 11, 21), kilograms: 79.4),
            WeightPoint(date: date(2026, 3, 11, 12), kilograms: 79.1)
        ]
        let daily = WeightSeries.daily(points, timeZone: utc)

        #expect(daily.count == 1)
        #expect(daily[0].kilograms == 79.4)
    }

    @Test("Points are normalised to the start of their day and sorted")
    func normalisedAndSorted() {
        let points = [
            WeightPoint(date: date(2026, 3, 12, 8), kilograms: 79),
            WeightPoint(date: date(2026, 3, 10, 8), kilograms: 80)
        ]
        let daily = WeightSeries.daily(points, timeZone: utc)

        #expect(daily.map(\.date) == [date(2026, 3, 10), date(2026, 3, 12)])
    }

    @Test("Days are bucketed in the given time zone")
    func timeZoneBuckets() {
        // 02:00 UTC on the 11th is 21:00 on the 10th in New York.
        let points = [
            WeightPoint(date: date(2026, 3, 11, 2), kilograms: 79),
            WeightPoint(date: date(2026, 3, 10, 15), kilograms: 80)
        ]

        #expect(WeightSeries.daily(points, timeZone: utc).count == 2)
        #expect(WeightSeries.daily(points, timeZone: ny).count == 1)
        #expect(WeightSeries.daily(points, timeZone: ny)[0].kilograms == 79)
    }
}

@Suite("Mass units")
struct MassUnitTests {

    @Test("Kilograms pass through unchanged")
    func kilograms() {
        #expect(MassUnit.kilograms.value(fromKilograms: 80) == 80)
    }

    @Test("Pounds convert")
    func pounds() {
        let converted = MassUnit.pounds.value(fromKilograms: 80)
        #expect(abs(converted - 176.37) < 0.01)
    }
}
