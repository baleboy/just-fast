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
}
