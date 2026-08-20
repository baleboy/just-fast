//
//  CorrelationTests.swift
//  FastinoTests
//
//  The Patterns section (§4.8): the fit itself, the two pairings, and — most
//  importantly — the wording. A scatter that looks plausible under a headline
//  saying the opposite of what the dots show is the failure mode these cover.
//

import Foundation
import Testing
@testable import Fastino

// MARK: - Helpers

private let utc = TimeZone(identifier: "UTC")!

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = dayOfMonth
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = utc
    return cal.date(from: comps)!
}

/// `count` pairs on the line y = slope·x + intercept.
private func line(slope: Double, intercept: Double, count: Int) -> [(x: Double, y: Double)] {
    (0..<count).map { (x: Double($0), y: slope * Double($0) + intercept) }
}

@Suite("Linear fit")
struct LinearFitTests {

    @Test("A perfect ascending line is r = 1")
    func perfectPositive() throws {
        let fit = try #require(Correlation.fit(line(slope: 2, intercept: 3, count: 10)))

        #expect(abs(fit.r - 1) < 0.000001)
        #expect(abs(fit.slope - 2) < 0.000001)
        #expect(abs(fit.intercept - 3) < 0.000001)
        #expect(fit.n == 10)
        #expect(fit.isMeaningful)
    }

    @Test("A perfect descending line is r = -1")
    func perfectNegative() throws {
        let fit = try #require(Correlation.fit(line(slope: -1.5, intercept: 20, count: 12)))

        #expect(abs(fit.r + 1) < 0.000001)
        #expect(abs(fit.slope + 1.5) < 0.000001)
    }

    @Test("Fewer than eight pairs is refused")
    func belowMinimumSample() {
        #expect(Correlation.fit(line(slope: 1, intercept: 0, count: 7)) == nil)
        #expect(Correlation.fit(line(slope: 1, intercept: 0, count: 8)) != nil)
    }

    @Test("No spread in x is refused rather than divided by zero")
    func noVarianceInX() {
        let pairs = (0..<10).map { (x: 5.0, y: Double($0)) }

        #expect(Correlation.fit(pairs) == nil)
    }

    @Test("No spread in y is refused too")
    func noVarianceInY() {
        let pairs = (0..<10).map { (x: Double($0), y: 5.0) }

        #expect(Correlation.fit(pairs) == nil)
    }

    @Test("A hand-computed r matches")
    func knownCoefficient() throws {
        // x = 1...8, y = 2,4,5,4,5,7,8,9. Worked through by hand:
        // mean x 4.5, mean y 5.5; Sxy = 38, Sxx = 42, Syy = 38
        // → r = 38 / √(42·38) = 0.951190…, slope = 38/42.
        let xs: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        let ys: [Double] = [2, 4, 5, 4, 5, 7, 8, 9]
        let fit = try #require(Correlation.fit(Array(zip(xs, ys)).map { (x: $0.0, y: $0.1) }))

        #expect(abs(fit.r - 0.951190) < 0.00001)
        #expect(abs(fit.slope - 38.0 / 42) < 0.000001)
    }

    @Test("Weak correlations are not meaningful")
    func deadBand() throws {
        // Sxy = 2, Sxx = 60, Syy = 2 → r = 0.1826, inside the dead band.
        let noisy: [(x: Double, y: Double)] = [
            (-6, 7), (-5, 8), (-4, 7), (-3, 8), (-1, 7), (0, 8), (1, 7), (2, 8)
        ]
        let fit = try #require(Correlation.fit(noisy))

        #expect(abs(fit.r) < Correlation.meaningfulR)
        #expect(!fit.isMeaningful)
    }
}

@Suite("Split comparison")
struct SplitTests {

    private let pairs: [(x: Double, y: Double)] = [
        (1, 8), (2, 8), (3, 7), (4, 7),      // below 5
        (6, 6), (7, 6), (8, 5), (9, 5)       // at or above 5
    ]

    @Test("Group means are taken either side of the threshold")
    func groupMeans() throws {
        let split = try #require(Correlation.split(pairs, at: 5))

        #expect(split.belowMean == 7.5)
        #expect(split.aboveMean == 5.5)
        #expect(split.belowCount == 4)
        #expect(split.aboveCount == 4)
        #expect(split.difference == 2)
    }

    @Test("The threshold itself counts as above")
    func thresholdIsInclusiveAbove() throws {
        let onBoundary: [(x: Double, y: Double)] = [
            (1, 1), (2, 1), (5, 9), (5, 9), (6, 9), (7, 9)
        ]
        let split = try #require(Correlation.split(onBoundary, at: 5))

        #expect(split.belowCount == 2)
        #expect(split.aboveCount == 4)
    }

    @Test("A group of one is not a comparison")
    func lopsidedSplitIsRefused() {
        let lopsided: [(x: Double, y: Double)] = [
            (1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6), (7, 7), (99, 8)
        ]

        #expect(Correlation.split(lopsided, at: 50) == nil)
        #expect(Correlation.split(lopsided, at: 4) != nil)
    }
}

// MARK: - Pairings

@Suite("Sleep vs eating stop pairing")
struct SleepPairingTests {

    private func stop(_ date: Date, _ hours: Double) -> EatingStop {
        EatingStop(date: date, stoppedAt: date.addingTimeInterval(hours * 3600), hoursFromMidnight: hours)
    }

    private func night(_ date: Date, _ hours: Double) -> SleepNight {
        let start = date.addingTimeInterval(-3600)
        return SleepNight(
            date: date,
            asleep: hours * 3600,
            mainSleepStart: start,
            mainSleepEnd: start.addingTimeInterval(hours * 3600)
        )
    }

    @Test("Matching days pair up")
    func pairsOnDate() {
        let stops = [stop(day(2026, 7, 10), -4), stop(day(2026, 7, 11), -3)]
        let nights = [night(day(2026, 7, 10), 7), night(day(2026, 7, 11), 8)]
        let pairs = HealthCorrelation.sleepVsEatingStop(stops: stops, nights: nights)

        #expect(pairs.count == 2)
        #expect(pairs[0].x == -4)
        #expect(pairs[0].y == 7)
        #expect(pairs[1].y == 8)
    }

    @Test("A day missing either series is dropped, not zero-filled")
    func unmatchedDaysAreDropped() {
        // A night the watch wasn't worn is absent data, not zero sleep — and a
        // zero would drag any fit straight down.
        let stops = [stop(day(2026, 7, 10), -4), stop(day(2026, 7, 11), -3)]
        let nights = [night(day(2026, 7, 11), 8)]
        let pairs = HealthCorrelation.sleepVsEatingStop(stops: stops, nights: nights)

        #expect(pairs.count == 1)
        #expect(pairs[0].date == day(2026, 7, 11))
    }

    @Test("No overlap gives no pairs")
    func disjointSeries() {
        let stops = [stop(day(2026, 7, 10), -4)]
        let nights = [night(day(2026, 7, 11), 8)]

        #expect(HealthCorrelation.sleepVsEatingStop(stops: stops, nights: nights).isEmpty)
    }
}

@Suite("Weight vs fasting pairing")
struct WeightPairingTests {

    private let now = day(2026, 7, 29)

    /// `hours` oldest-first, one per day ending today. Zero means no fast.
    private func bars(_ hours: [Double]) -> [DayBar] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let count = hours.count
        return hours.enumerated().map { index, value in
            let offset = count - 1 - index
            let date = cal.date(byAdding: .day, value: -offset, to: now)!
            return DayBar(date: date, duration: value * 3600, goalMet: value >= 16, isInProgress: false)
        }
    }

    private func weight(_ daysAgo: Int, _ kilograms: Double) -> WeightPoint {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return WeightPoint(date: cal.date(byAdding: .day, value: -daysAgo, to: now)!, kilograms: kilograms)
    }

    @Test("Each week pairs its mean fast hours with its weight change")
    func weeklyPairs() {
        // Three weeks: the oldest establishes a baseline weight, the two after
        // it each produce a point.
        let pairs = HealthCorrelation.weightVsFasting(
            bars: bars(Array(repeating: 16, count: 14) + Array(repeating: 18, count: 7)),
            weights: [weight(14, 80), weight(7, 79.5), weight(0, 79)],
            now: now,
            timeZone: utc
        )

        #expect(pairs.count == 2)
        #expect(pairs[0].x == 16)
        #expect(abs(pairs[0].y + 0.5) < 0.0001)
        #expect(pairs[1].x == 18)
        #expect(abs(pairs[1].y + 0.5) < 0.0001)
    }

    @Test("The oldest week has nothing to compare against")
    func firstWeekIsBaselineOnly() {
        let pairs = HealthCorrelation.weightVsFasting(
            bars: bars(Array(repeating: 16, count: 7)),
            weights: [weight(6, 80), weight(0, 79.5)],
            now: now,
            timeZone: utc
        )

        #expect(pairs.isEmpty)
    }

    @Test("A week without a weigh-in is skipped, and the next compares past it")
    func missingWeighInIsSkipped() {
        // Weeks: baseline 80, then nothing, then 79. The 79 week compares
        // against the baseline rather than inventing a middle reading.
        let pairs = HealthCorrelation.weightVsFasting(
            bars: bars(Array(repeating: 16, count: 21)),
            weights: [weight(14, 80), weight(0, 79)],
            now: now,
            timeZone: utc
        )

        #expect(pairs.count == 1)
        #expect(abs(pairs[0].y + 1) < 0.0001)
    }

    @Test("Days without a fast don't drag the week's mean to zero")
    func daysWithoutAFastAreExcludedFromTheMean() {
        // Four 16h fasts and three rest days. The mean is 16, not 16·4/7.
        let week = [16.0, 16, 0, 16, 0, 16, 0]
        let pairs = HealthCorrelation.weightVsFasting(
            bars: bars(Array(repeating: 16, count: 7) + week),
            weights: [weight(7, 80), weight(0, 79)],
            now: now,
            timeZone: utc
        )

        #expect(pairs.count == 1)
        #expect(pairs[0].x == 16)
    }

    @Test("A week with no fasts at all produces no point")
    func weekWithoutFastsIsSkipped() {
        let pairs = HealthCorrelation.weightVsFasting(
            bars: bars(Array(repeating: 16, count: 7) + Array(repeating: 0, count: 7)),
            weights: [weight(7, 80), weight(0, 79)],
            now: now,
            timeZone: utc
        )

        #expect(pairs.isEmpty)
    }

    @Test("No weigh-ins at all gives no points")
    func noWeights() {
        #expect(
            HealthCorrelation.weightVsFasting(
                bars: bars(Array(repeating: 16, count: 21)),
                weights: [],
                now: now,
                timeZone: utc
            ).isEmpty
        )
    }
}

// MARK: - Wording

@Suite("Pattern wording")
struct PatternWordingTests {

    private func pairs(_ values: [(Double, Double)]) -> [Pairing] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return values.enumerated().map { index, value in
            Pairing(
                date: cal.date(byAdding: .day, value: index, to: day(2026, 7, 1))!,
                x: value.0,
                y: value.1
            )
        }
    }

    @Test("Too little data says so and draws no line")
    func notEnoughData() {
        let summary = HealthCorrelation.sleepSummary(pairs([(-5, 8), (-4, 7), (-3, 7)]), threshold: -4)

        #expect(summary.fit == nil)
        #expect(summary.n == 3)
        #expect(summary.headline.contains("Not enough nights"))
    }

    @Test("A weak relationship reports no pattern and draws no line")
    func weakRelationship() {
        // Same set as `deadBand` above: r = 0.1826, and a valid split either
        // side of the threshold, so only the dead band can suppress it.
        let summary = HealthCorrelation.sleepSummary(
            pairs([(-6, 7), (-5, 8), (-4, 7), (-3, 8), (-1, 7), (0, 8), (1, 7), (2, 8)]),
            threshold: -2
        )

        #expect(summary.fit == nil)
        #expect(summary.headline == "No clear pattern yet.")
    }

    @Test("Stopping earlier going with more sleep reads as 'more'")
    func earlierMeansMoreSleep() {
        // Below the -4 threshold: 8h. At or above it: 7h. One hour more.
        let summary = HealthCorrelation.sleepSummary(
            pairs([(-6, 8), (-6, 8), (-5, 8), (-5, 8), (-3, 7), (-3, 7), (-2, 7), (-2, 7)]),
            threshold: -4
        )

        #expect(summary.fit != nil)
        #expect(summary.headline.contains("1h 0m more"))
        #expect(summary.headline.contains("before"))
        #expect(!summary.headline.lowercased().contains("cause"))
    }

    @Test("A tidy but tiny sleep difference is still noise")
    func sleepEffectFloor() {
        // Perfectly ordered, r near 1 — but the two groups differ by five
        // minutes, which no one should change their evening over.
        let summary = HealthCorrelation.sleepSummary(
            pairs([(-6, 7.0), (-6, 7.0), (-5, 7.0), (-5, 7.0),
                   (-3, 6.917), (-3, 6.917), (-2, 6.917), (-2, 6.917)]),
            threshold: -4
        )

        #expect(summary.fit == nil)
        #expect(summary.headline == "No clear pattern yet.")
    }

    @Test("A tidy but tiny weight difference is still noise")
    func weightEffectFloor() {
        // 100 g between the groups — inside what a bathroom scale and a glass
        // of water disagree about.
        let summary = HealthCorrelation.weightSummary(
            pairs([(14, 0.05), (14.5, 0.05), (15, 0.05), (15.5, 0.05),
                   (16.5, -0.05), (17, -0.05), (17.5, -0.05), (18, -0.05)]),
            goalHours: 16,
            unit: .kilograms
        )

        #expect(summary.fit == nil)
        #expect(summary.headline == "No clear pattern yet.")
    }

    @Test("The reverse direction reads as 'less'")
    func earlierMeansLessSleep() {
        let summary = HealthCorrelation.sleepSummary(
            pairs([(-6, 6), (-6, 6), (-5, 6), (-5, 6), (-3, 8), (-3, 8), (-2, 8), (-2, 8)]),
            threshold: -4
        )

        #expect(summary.headline.contains("less"))
    }

    @Test("Everything on one side of the target can't be compared")
    func lopsidedSleepSplit() {
        let summary = HealthCorrelation.sleepSummary(
            pairs([(-6, 6), (-5.5, 6.2), (-5, 6.5), (-4.5, 6.8), (-4.2, 7), (-4.1, 7.2), (-4.05, 7.4), (-4.01, 7.6)]),
            threshold: -4
        )

        // Strong enough to draw, but there is no "after" group to quote.
        #expect(summary.fit != nil)
        #expect(summary.headline.contains("Not enough nights either side"))
    }

    @Test("Longer weeks going with loss reads as 'lighter'")
    func longerWeeksAreLighter() {
        // Below the 16h goal: +0.4 kg. At or above: -0.4 kg. Difference 0.8.
        let summary = HealthCorrelation.weightSummary(
            pairs([(14, 0.4), (14.5, 0.4), (15, 0.4), (15.5, 0.4),
                   (16.5, -0.4), (17, -0.4), (17.5, -0.4), (18, -0.4)]),
            goalHours: 16,
            unit: .kilograms
        )

        // Formatted through the same style, because the decimal separator is
        // the user's — this reads "0,8 kg" in a comma locale.
        let expected = (0.8).formatted(.number.precision(.fractionLength(1)))
        #expect(summary.fit != nil)
        #expect(summary.headline.contains("\(expected) kg lighter"))
        #expect(summary.headline.contains("over 16h"))
    }

    @Test("The reverse direction reads as 'heavier'")
    func longerWeeksAreHeavier() {
        let summary = HealthCorrelation.weightSummary(
            pairs([(14, -0.4), (14.5, -0.4), (15, -0.4), (15.5, -0.4),
                   (16.5, 0.4), (17, 0.4), (17.5, 0.4), (18, 0.4)]),
            goalHours: 16,
            unit: .kilograms
        )

        #expect(summary.headline.contains("heavier"))
    }

    @Test("Weight is quoted in the user's unit")
    func poundsAreConverted() {
        let summary = HealthCorrelation.weightSummary(
            pairs([(14, 0.4), (14.5, 0.4), (15, 0.4), (15.5, 0.4),
                   (16.5, -0.4), (17, -0.4), (17.5, -0.4), (18, -0.4)]),
            goalHours: 16,
            unit: .pounds
        )

        // 0.8 kg ≈ 1.8 lb, in whatever decimal separator the locale uses.
        let expected = MassUnit.pounds.value(fromKilograms: 0.8)
            .formatted(.number.precision(.fractionLength(1)))
        #expect(expected.hasPrefix("1"))
        #expect(summary.headline.contains("\(expected) lb"))
    }
}
