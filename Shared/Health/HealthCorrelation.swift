//
//  HealthCorrelation.swift
//  Fastino
//
//  The two pairings behind the Patterns section (§4.8), and the sentences that
//  describe them. Pure — it takes the value types the rest of the app already
//  produces (`EatingStop`, `SleepNight`, `DayBar`, `WeightPoint`) and returns
//  points and strings.
//
//  The wording lives here rather than in the view so it can be unit-tested.
//  A scatter that looks plausible under a headline that says the opposite of
//  what the dots show is the failure this file exists to make testable.
//
//  Neither pairing claims causation and the copy never says so: "on nights you
//  stopped before 20:00" is an association in the user's own data, and that is
//  all the app is entitled to say.
//

import Foundation

/// One observation on a scatter plot.
nonisolated struct Pairing: Equatable, Sendable, Identifiable {
    /// The day (or, for weekly pairings, the block's most recent day) this
    /// came from. Identity only — it isn't plotted.
    let date: Date
    let x: Double
    let y: Double

    var id: Date { date }
}

/// Everything a Patterns card needs: what to say, whether to draw a line, and
/// how much data it's based on.
nonisolated struct PatternSummary: Equatable, Sendable {
    let headline: String
    /// Non-nil only when there are enough points *and* the relationship is
    /// strong enough to describe. The card draws a fit line exactly when this
    /// is present, so a weak result can't come with a confident-looking line.
    let fit: Correlation.LinearFit?
    let n: Int
}

nonisolated enum HealthCorrelation {

    /// Effect-size floors. `Correlation.meaningfulR` asks whether the points
    /// line up; these ask whether the difference is big enough to be worth a
    /// sentence. A tidy relationship around a ten-minute or 200-gram difference
    /// is still noise — bed times and bathroom scales aren't that precise —
    /// and reporting it would train the user to act on nothing.
    static let minimumSleepDifference: TimeInterval = 10 * 60
    static let minimumWeightDifference = 0.2

    // MARK: Pairings

    /// One point per day that has both an eating stop and a night's sleep.
    ///
    /// No date arithmetic is needed: `FastingEngine.eatingStops` and
    /// `SleepAggregator.nights` both credit their value to the day the fast
    /// ended / the user woke (§2, §4.8), so equal `date`s are the same night.
    /// Days missing either series are dropped rather than zero-filled — a night
    /// the watch wasn't worn is absent data, not zero sleep.
    static func sleepVsEatingStop(stops: [EatingStop], nights: [SleepNight]) -> [Pairing] {
        let sleepByDate = Dictionary(nights.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        return stops.compactMap { stop in
            guard let night = sleepByDate[stop.date] else { return nil }
            return Pairing(date: stop.date, x: stop.hoursFromMidnight, y: night.hours)
        }
    }

    /// Average fast hours per week against that week's weight change.
    ///
    /// Weekly, and over a long window, because body weight swings on water and
    /// glycogen by more than a day of fasting could ever move it and responds
    /// over weeks. Pairing a single day's fast with a single day's weight would
    /// plot pure noise.
    ///
    /// Blocks are seven days counting back from today rather than calendar
    /// weeks, so the most recent block always ends today instead of being a
    /// part-week that reads as a dip.
    static func weightVsFasting(
        bars: [DayBar],
        weights: [WeightPoint],
        now: Date,
        timeZone: TimeZone
    ) -> [Pairing] {
        guard !bars.isEmpty else { return [] }

        let today = FastingEngine.dayNumber(of: now, timeZone: timeZone)
        let hoursByDay = Dictionary(
            bars.map { (FastingEngine.dayNumber(of: $0.date, timeZone: timeZone), $0.duration / 3600) },
            uniquingKeysWith: { first, _ in first }
        )
        let weightByDay = Dictionary(
            weights.map { (FastingEngine.dayNumber(of: $0.date, timeZone: timeZone), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        guard let oldestDay = hoursByDay.keys.min() else { return [] }
        let blockCount = (today - oldestDay) / 7 + 1

        // Oldest first, so each block can be compared with the one before it.
        var blocks: [(date: Date, meanHours: Double?, weight: WeightPoint?)] = []
        for index in (0..<blockCount).reversed() {
            let end = today - index * 7
            let days = Array((end - 6)...end)

            let fasted = days.compactMap { hoursByDay[$0] }.filter { $0 > 0 }
            let meanHours = fasted.isEmpty ? nil : fasted.reduce(0, +) / Double(fasted.count)
            // The block's weight is its most recent reading.
            let weight = days.reversed().compactMap { weightByDay[$0] }.first

            blocks.append((days.compactMap { weightByDay[$0]?.date }.last ?? now, meanHours, weight))
        }

        var pairings: [Pairing] = []
        for (index, block) in blocks.enumerated() {
            guard index > 0,
                  let meanHours = block.meanHours,
                  let weight = block.weight,
                  let previous = blocks[..<index].last(where: { $0.weight != nil })?.weight
            else { continue }

            pairings.append(
                Pairing(
                    date: block.date,
                    x: meanHours,
                    y: weight.kilograms - previous.kilograms
                )
            )
        }
        return pairings
    }

    // MARK: Wording

    /// The sleep card's sentence.
    ///
    /// `threshold` is the user's start-time anchor on the same signed-hours
    /// scale as the pairings — the time they meant to stop eating. Comparing
    /// against their own target is more useful than against the median, which
    /// would move every time they changed their habits.
    static func sleepSummary(_ pairs: [Pairing], threshold: Double?) -> PatternSummary {
        let points = pairs.map { (x: $0.x, y: $0.y) }
        guard let fit = Correlation.fit(points) else {
            return PatternSummary(headline: notEnoughNights, fit: nil, n: pairs.count)
        }
        guard fit.isMeaningful else {
            return PatternSummary(headline: noPattern, fit: nil, n: pairs.count)
        }
        guard let threshold, let split = Correlation.split(points, at: threshold) else {
            return PatternSummary(
                headline: "Not enough nights either side of your usual time to compare.",
                fit: fit,
                n: pairs.count
            )
        }

        let seconds = abs(split.difference) * 3600
        guard seconds >= minimumSleepDifference else {
            return PatternSummary(headline: noPattern, fit: nil, n: pairs.count)
        }
        let time = TimeFormat.timeOfDay(hoursFromMidnight: threshold)
        let direction = split.difference > 0 ? "more" : "less"
        return PatternSummary(
            headline: "You sleep about \(DurationFormat.hoursMinutes(seconds)) \(direction) "
                + "on nights you stop eating before \(time).",
            fit: fit,
            n: pairs.count
        )
    }

    /// The weight card's sentence. `threshold` is the user's goal in hours —
    /// weeks that averaged over it, against weeks that didn't.
    static func weightSummary(_ pairs: [Pairing], goalHours: Int, unit: MassUnit) -> PatternSummary {
        let points = pairs.map { (x: $0.x, y: $0.y) }
        guard let fit = Correlation.fit(points) else {
            return PatternSummary(headline: notEnoughWeeks, fit: nil, n: pairs.count)
        }
        guard fit.isMeaningful else {
            return PatternSummary(headline: noPattern, fit: nil, n: pairs.count)
        }
        guard let split = Correlation.split(points, at: Double(goalHours)) else {
            return PatternSummary(
                headline: "Not enough weeks either side of your \(goalHours)h goal to compare.",
                fit: fit,
                n: pairs.count
            )
        }

        guard abs(split.difference) >= minimumWeightDifference else {
            return PatternSummary(headline: noPattern, fit: nil, n: pairs.count)
        }
        // `difference` is below-minus-above, so a positive value means the
        // weeks that hit the goal changed *less* — i.e. ended lighter.
        let amount = unit.value(fromKilograms: abs(split.difference))
        let direction = split.difference > 0 ? "lighter" : "heavier"
        let formatted = amount.formatted(.number.precision(.fractionLength(1)))
        return PatternSummary(
            headline: "Weeks you averaged over \(goalHours)h ended about "
                + "\(formatted) \(unit.symbol) \(direction) than weeks you didn't.",
            fit: fit,
            n: pairs.count
        )
    }

    private static let notEnoughNights = "Not enough nights yet — keep logging and this will fill in."
    private static let notEnoughWeeks = "Not enough weeks yet — this needs a couple of months of weigh-ins."
    private static let noPattern = "No clear pattern yet."
}
