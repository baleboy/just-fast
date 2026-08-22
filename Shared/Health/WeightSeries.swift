//
//  WeightSeries.swift
//  Fastino
//
//  Reduces raw body-mass samples to at most one point per calendar day (§4.8).
//  Pure, like `SleepAggregator`.
//
//  Health can hold several weigh-ins a day (a smart scale that reports twice, a
//  manual correction on top of a synced reading). The trends line wants one
//  point per day: we take the **last** reading of the day, which is the one the
//  user most recently stood by.
//

import Foundation

nonisolated enum WeightSeries {

    /// One point per day that has a reading, oldest first. Days without a
    /// weigh-in are absent — the line should bridge them, not drop to zero.
    static func daily(_ points: [WeightPoint], timeZone: TimeZone) -> [WeightPoint] {
        guard !points.isEmpty else { return [] }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var latest: [Int: (sample: Date, point: WeightPoint)] = [:]
        for point in points {
            let day = FastingEngine.dayNumber(of: point.date, timeZone: timeZone)
            if let existing = latest[day], existing.sample >= point.date { continue }
            let normalised = WeightPoint(
                date: cal.startOfDay(for: point.date),
                kilograms: point.kilograms
            )
            latest[day] = (point.date, normalised)
        }

        return latest.values.map(\.point).sorted { $0.date < $1.date }
    }

    /// Mean weight per calendar week, oldest first — one point per week that
    /// has at least one reading.
    ///
    /// The trends panel plots this rather than the daily points, in the same
    /// buckets as `FastingEngine.weeklyAverageHours`, so a week's fasting and
    /// that week's weight are one column of the chart. Weight swings a kilo on
    /// water and glycogen alone and only answers to fasting over weeks; drawn
    /// raw over the fasting bars, every wobble invites reading yesterday's dip
    /// as yesterday's fast.
    ///
    /// The mean of the week's readings, not its last one: a single weigh-in
    /// lands wherever that morning's water did, which is the noise this is here
    /// to take out.
    ///
    /// Weeks without a reading are absent — the line bridges them rather than
    /// inventing a value.
    ///
    /// - Parameter points: one point per day, as `daily` returns.
    static func weeklyMean(
        _ points: [WeightPoint],
        timeZone: TimeZone,
        firstWeekday: Int = Calendar.current.firstWeekday
    ) -> [WeightPoint] {
        var totals: [Date: (sum: Double, count: Int)] = [:]
        for point in points {
            let week = FastingEngine.weekStart(
                of: point.date, timeZone: timeZone, firstWeekday: firstWeekday
            )
            let running = totals[week] ?? (0, 0)
            totals[week] = (running.sum + point.kilograms, running.count + 1)
        }

        return totals
            .map { WeightPoint(date: $0.key, kilograms: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }
}
