//
//  WeightSeriesTests.swift
//  FastinoTests
//
//  The weight half of the Health integration (§4.8): one point per day, and
//  the seven-day trailing mean the trends panel actually plots. All pure — no
//  HealthKit, no entitlement, no HealthStore.
//

import Foundation
import Testing
@testable import Fastino

private let utc = TimeZone(identifier: "UTC")!
/// A zone with a spring-forward inside the window, to prove the window is
/// counted in days rather than in 86 400-second blocks.
private let helsinki = TimeZone(identifier: "Europe/Helsinki")!

private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 8, tz: TimeZone = utc) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: comps)!
}

private func point(_ date: Date, _ kilograms: Double) -> WeightPoint {
    WeightPoint(date: date, kilograms: kilograms)
}

private func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

@Suite("Weekly weight mean")
struct WeeklyWeightMeanTests {

    /// Pinned rather than inherited from whoever runs the tests.
    private let monday = 2

    private func weekly(_ points: [WeightPoint], tz: TimeZone = utc) -> [WeightPoint] {
        WeightSeries.weeklyMean(points, timeZone: tz, firstWeekday: monday)
    }

    @Test("An empty series stays empty")
    func empty() {
        #expect(weekly([]).isEmpty)
    }

    @Test("A week of weigh-ins collapses to one point, at that week's mean")
    func oneAWeek() {
        // Mon 2 – Fri 6 March 2026.
        let points = (0..<5).map { point(day(2026, 3, 2 + $0), 80 + Double($0)) }
        let mean = weekly(points)

        #expect(mean.count == 1)
        #expect(mean[0].date == day(2026, 3, 2, 0))
        #expect(rounded(mean[0].kilograms) == 82)
    }

    @Test("The mean, not the last reading — one morning's water shouldn't set the week")
    func meanNotLast() {
        let mean = weekly([
            point(day(2026, 3, 2), 80),
            point(day(2026, 3, 3), 80),
            point(day(2026, 3, 4), 83)
        ])

        #expect(rounded(mean[0].kilograms) == rounded(243.0 / 3))
    }

    @Test("The bucket boundary is the week's first day")
    func weeksAreCalendarWeeks() {
        let mean = weekly([
            point(day(2026, 3, 8), 80),   // Sunday
            point(day(2026, 3, 9), 84)    // Monday
        ])

        #expect(mean.count == 2)
        #expect(mean.map(\.date) == [day(2026, 3, 2, 0), day(2026, 3, 9, 0)])
        #expect(mean.map { rounded($0.kilograms) } == [80, 84])
    }

    @Test("A week with no reading is absent, not interpolated")
    func gapsAreNotFilled() {
        let mean = weekly([
            point(day(2026, 3, 2), 80),
            point(day(2026, 3, 16), 84)
        ])

        #expect(mean.map(\.date) == [day(2026, 3, 2, 0), day(2026, 3, 16, 0)])
    }

    @Test("Weeks come back oldest first, whatever order they arrive in")
    func sorted() {
        let mean = weekly([
            point(day(2026, 3, 16), 82),
            point(day(2026, 3, 2), 80),
            point(day(2026, 3, 9), 81)
        ])

        #expect(mean.map(\.date) == [day(2026, 3, 2, 0), day(2026, 3, 9, 0), day(2026, 3, 16, 0)])
        #expect(mean.map { rounded($0.kilograms) } == [80, 81, 82])
    }

    @Test("A week with a DST change is still one week")
    func dstWeek() {
        // Europe/Helsinki springs forward on Sunday 29 March 2026.
        let points = (0..<7).map { point(day(2026, 3, 23 + $0, tz: helsinki), 80) }
        let mean = WeightSeries.weeklyMean(points, timeZone: helsinki, firstWeekday: monday)

        #expect(mean.count == 1)
        #expect(rounded(mean[0].kilograms) == 80)
    }
}
