//
//  FastingEngineTests.swift
//  JustFastTests
//
//  Exhaustive tests for the pure streak/stat engine (§7): midnight spans, TZ
//  shifts, edits, overlaps, and the rolling-window stats.
//

import Foundation
import Testing
@testable import JustFast

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

private func fast(_ start: Date, _ end: Date?, goal: Int = 16) -> FastRecord {
    FastRecord(start: start, end: end, goalHours: goal)
}

// A completed fast comfortably over `goal` hours ending at the given day/time.
// (One second of slack keeps the goal unambiguously met despite Date's
// sub-nanosecond floating-point rounding at large magnitudes.)
private func completedFast(endingAt end: Date, goal: Int = 16) -> FastRecord {
    fast(end.addingTimeInterval(-Double(goal) * 3600 - 1), end, goal: goal)
}

/// Tolerant comparison for TimeInterval math. `Date` arithmetic at real-world
/// magnitudes (~10⁹ s since the reference date) carries ~10⁻⁷ s of rounding, so
/// exact `==` on reconstructed durations is not meaningful — but sub-second
/// agreement is exactly what the app cares about.
private func approxEqual(_ a: TimeInterval?, _ b: TimeInterval, tol: TimeInterval = 0.001) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tol
}

// MARK: - Goal-met determination

@Suite struct GoalMetTests {
    @Test func durationAtLeastGoalIsMet() {
        let f = fast(date(2026, 7, 1, 20, 0), date(2026, 7, 2, 12, 0)) // 16h, goal 16
        #expect(f.isGoalMet)
    }

    @Test func durationBelowGoalIsNotMet() {
        let f = fast(date(2026, 7, 1, 20, 0), date(2026, 7, 2, 10, 0)) // 14h, goal 16
        #expect(!f.isGoalMet)
    }

    @Test func openFastIsNeverGoalMet() {
        let f = fast(date(2026, 7, 1, 20, 0), nil)
        #expect(!f.isGoalMet)
    }

    @Test func exactlyGoalCountsAsMet() {
        let f = fast(date(2026, 7, 1, 0, 0), date(2026, 7, 1, 16, 0), goal: 16)
        #expect(f.isGoalMet)
    }
}

// MARK: - Current streak

@Suite struct CurrentStreakTests {
    @Test func threeConsecutiveDaysEndingToday() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 27, 12)),
            completedFast(endingAt: date(2026, 7, 28, 12)),
            completedFast(endingAt: date(2026, 7, 29, 12)),
        ]
        let now = date(2026, 7, 29, 18)
        #expect(FastingEngine.currentStreak(fasts, now: now, timeZone: utc) == 3)
    }

    @Test func streakAliveWhenTodayNotYetAGoalDayButYesterdayWas() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 26, 12)),
            completedFast(endingAt: date(2026, 7, 27, 12)),
            completedFast(endingAt: date(2026, 7, 28, 12)),
        ]
        let now = date(2026, 7, 29, 9) // today has no completed fast yet
        #expect(FastingEngine.currentStreak(fasts, now: now, timeZone: utc) == 3)
    }

    @Test func streakBrokenWhenAFullDayPassedWithNoGoal() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 25, 12)),
            completedFast(endingAt: date(2026, 7, 26, 12)),
            completedFast(endingAt: date(2026, 7, 27, 12)),
        ]
        let now = date(2026, 7, 29, 9) // 7/28 was empty → broken
        #expect(FastingEngine.currentStreak(fasts, now: now, timeZone: utc) == 0)
    }

    @Test func gapInTheMiddleCountsOnlyTheRecentRun() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 20, 12)),
            completedFast(endingAt: date(2026, 7, 21, 12)),
            // gap
            completedFast(endingAt: date(2026, 7, 28, 12)),
            completedFast(endingAt: date(2026, 7, 29, 12)),
        ]
        let now = date(2026, 7, 29, 18)
        #expect(FastingEngine.currentStreak(fasts, now: now, timeZone: utc) == 2)
    }

    @Test func multipleCompletedFastsSameDayCountOnce() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 29, 8)),
            completedFast(endingAt: date(2026, 7, 29, 20)),
        ]
        let now = date(2026, 7, 29, 22)
        #expect(FastingEngine.currentStreak(fasts, now: now, timeZone: utc) == 1)
    }

    @Test func underGoalFastDoesNotContribute() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 28, 12)),
            fast(date(2026, 7, 29, 0), date(2026, 7, 29, 10)), // 10h < 16
        ]
        let now = date(2026, 7, 29, 18)
        // today isn't a goal day; yesterday is → streak 1
        #expect(FastingEngine.currentStreak(fasts, now: now, timeZone: utc) == 1)
    }

    @Test func noFastsMeansZero() {
        #expect(FastingEngine.currentStreak([], now: date(2026, 7, 29), timeZone: utc) == 0)
    }
}

// MARK: - Longest streak

@Suite struct LongestStreakTests {
    @Test func longestRunAcrossGaps() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 1, 12)),
            completedFast(endingAt: date(2026, 7, 2, 12)),
            completedFast(endingAt: date(2026, 7, 3, 12)),
            completedFast(endingAt: date(2026, 7, 4, 12)),
            // gap
            completedFast(endingAt: date(2026, 7, 10, 12)),
            completedFast(endingAt: date(2026, 7, 11, 12)),
        ]
        #expect(FastingEngine.longestStreak(fasts, timeZone: utc) == 4)
    }

    @Test func singleGoalDayIsStreakOfOne() {
        let fasts = [completedFast(endingAt: date(2026, 7, 10, 12))]
        #expect(FastingEngine.longestStreak(fasts, timeZone: utc) == 1)
    }

    @Test func noGoalDaysIsZero() {
        let fasts = [fast(date(2026, 7, 1, 0), date(2026, 7, 1, 5))] // under goal
        #expect(FastingEngine.longestStreak(fasts, timeZone: utc) == 0)
    }
}

// MARK: - Midnight spans & time zones

@Suite struct MidnightAndTimeZoneTests {
    @Test func midnightSpanningFastCreditsTheEndDay() {
        // 20:00 → 12:00 next day, 16h, goal 16.
        let f = completedFast(endingAt: date(2026, 7, 29, 12))
        let goalDays = FastingEngine.goalDayNumbers([f], timeZone: utc)
        #expect(goalDays == [FastingEngine.dayNumber(of: date(2026, 7, 29, 12), timeZone: utc)])
    }

    @Test func timeZoneShiftMovesGoalDayAcrossMidnight() {
        // The fast ends 2026-07-29 00:30 UTC, which is 2026-07-28 20:30 in New
        // York — a different calendar date. With "now" at 2026-07-29 12:00 UTC
        // (= 08:00 in NY, so both zones agree today is the 29th), the goal day
        // lands on *today* in UTC but on *yesterday* in New York.
        let end = date(2026, 7, 29, 0, 30, tz: utc)
        let f = completedFast(endingAt: end)
        let now = date(2026, 7, 29, 12, 0, tz: utc)

        let utcStrip = FastingEngine.lastDaysGoalMet([f], now: now, timeZone: utc, count: 7)
        let nyStrip = FastingEngine.lastDaysGoalMet([f], now: now, timeZone: ny, count: 7)

        // index 6 == today, index 5 == yesterday
        #expect(utcStrip[6] == true)   // UTC: ended today
        #expect(utcStrip[5] == false)
        #expect(nyStrip[6] == false)   // NY: ended yesterday
        #expect(nyStrip[5] == true)
    }

    @Test func durationIsAbsoluteAndDstDoesNotDistortIt() {
        // US spring-forward 2026-03-08 02:00 → 03:00 local. A 16h fast across it
        // is still 16h of absolute time.
        let start = date(2026, 3, 7, 20, 0, tz: ny)
        let end = start.addingTimeInterval(16 * 3600)
        let f = fast(start, end)
        #expect(approxEqual(f.finalDuration, 16 * 3600))
        #expect(f.isGoalMet)
    }
}

// MARK: - Rolling-window stats

@Suite struct RollingStatsTests {
    @Test func averageDurationOverLast30Days() {
        let now = date(2026, 7, 29, 12)
        let fasts = [
            fast(date(2026, 7, 20, 0), date(2026, 7, 20, 16)), // 16h
            fast(date(2026, 7, 25, 0), date(2026, 7, 25, 12)), // 12h
            fast(date(2026, 1, 1, 0), date(2026, 1, 1, 20)),   // outside window
        ]
        let avg = FastingEngine.averageDuration(fasts, now: now, days: 30)
        #expect(approxEqual(avg, 14 * 3600))
    }

    @Test func goalCompletionRateOverLast30Days() {
        let now = date(2026, 7, 29, 12)
        let fasts = [
            fast(date(2026, 7, 20, 0), date(2026, 7, 20, 16)), // met
            fast(date(2026, 7, 22, 0), date(2026, 7, 22, 16)), // met
            fast(date(2026, 7, 25, 0), date(2026, 7, 25, 10)), // missed
            fast(date(2026, 7, 27, 0), date(2026, 7, 27, 12)), // missed
        ]
        let rate = FastingEngine.goalCompletionRate(fasts, now: now, days: 30)
        #expect(rate == 0.5)
    }

    @Test func averageAndRateAreNilWithNoRecentFasts() {
        let now = date(2026, 7, 29, 12)
        #expect(FastingEngine.averageDuration([], now: now) == nil)
        #expect(FastingEngine.goalCompletionRate([], now: now) == nil)
    }

    @Test func last7DaysStripReflectsGoalDays() {
        let now = date(2026, 7, 29, 18)
        let fasts = [
            completedFast(endingAt: date(2026, 7, 29, 12)), // today
            completedFast(endingAt: date(2026, 7, 27, 12)), // 2 days ago
        ]
        let strip = FastingEngine.lastDaysGoalMet(fasts, now: now, timeZone: utc, count: 7)
        // oldest → today; index 6 = today, index 4 = two days ago
        #expect(strip.count == 7)
        #expect(strip[6] == true)
        #expect(strip[4] == true)
        #expect(strip[5] == false)
    }

    @Test func longestFastIncludesLiveOpenFast() {
        let now = date(2026, 7, 29, 12)
        let fasts = [
            fast(date(2026, 7, 1, 0), date(2026, 7, 1, 16)), // 16h closed
            fast(date(2026, 7, 29, 0), nil),                 // 12h and counting
        ]
        // Closed 16h still longest here.
        #expect(approxEqual(FastingEngine.longestFast(fasts, now: now), 16 * 3600))
        // Advance now so the open fast overtakes.
        let later = date(2026, 7, 29, 20)
        #expect(approxEqual(FastingEngine.longestFast(fasts, now: later), 20 * 3600))
    }

    @Test func openFastReportedAsCurrent() {
        let fasts = [fast(date(2026, 7, 29, 0), nil)]
        let now = date(2026, 7, 29, 6)
        let summary = FastingEngine.summary(fasts, now: now, timeZone: utc)
        #expect(approxEqual(summary.currentFastDuration, 6 * 3600))
    }
}

// MARK: - Eating window

@Suite struct EatingWindowTests {
    private let lastEnd = date(2026, 7, 28, 12) // a 16h fast ended at noon

    private func fastsEndingAtNoon() -> [FastRecord] {
        [completedFast(endingAt: lastEnd)]
    }

    @Test func windowOpensWhenTheLastFastEnded() {
        let window = FastingEngine.currentEatingWindow(
            fastsEndingAtNoon(), eatingHours: 8, now: date(2026, 7, 28, 14)
        )
        #expect(window?.start == lastEnd)
        #expect(window?.endsAt == date(2026, 7, 28, 20))
    }

    @Test func progressAndRemainingMidWindow() {
        let window = FastingEngine.currentEatingWindow(
            fastsEndingAtNoon(), eatingHours: 8, now: date(2026, 7, 28, 14)
        )!
        let now = date(2026, 7, 28, 14) // 2h into an 8h window
        #expect(abs(window.progress(asOf: now) - 0.25) < 0.001)
        #expect(approxEqual(window.remaining(asOf: now), 6 * 3600))
        #expect(!window.isOver(asOf: now))
    }

    @Test func windowGoesOverAndRemainingTurnsNegative() {
        let window = EatingWindow(start: lastEnd, goalHours: 8)
        let now = date(2026, 7, 28, 21) // 1h past the window
        #expect(window.isOver(asOf: now))
        #expect(window.progress(asOf: now) > 1)
        #expect(approxEqual(window.remaining(asOf: now), -3600))
    }

    @Test func noWindowBeforeTheFirstEverFast() {
        #expect(FastingEngine.currentEatingWindow([], eatingHours: 8, now: lastEnd) == nil)
    }

    @Test func noWindowWhenOnlyFastIsStillOpen() {
        let fasts = [fast(date(2026, 7, 28, 6), nil)]
        let window = FastingEngine.currentEatingWindow(
            fasts, eatingHours: 8, now: date(2026, 7, 28, 14)
        )
        #expect(window == nil)
    }

    @Test func noWindowWhileAFastIsRunningAfterAnEarlierOne() {
        let fasts = fastsEndingAtNoon() + [fast(date(2026, 7, 28, 20), nil)]
        let window = FastingEngine.currentEatingWindow(
            fasts, eatingHours: 8, now: date(2026, 7, 28, 22)
        )
        #expect(window == nil)
    }

    @Test func windowGoesStaleAfterADayAndFallsBackToReady() {
        let fasts = fastsEndingAtNoon()
        // 23h59m later: still shown (badly overrun, but the cadence is intact).
        #expect(FastingEngine.currentEatingWindow(
            fasts, eatingHours: 8, now: date(2026, 7, 29, 11, 59)
        ) != nil)
        // Past 24h: no window — the timer shows plain "Ready".
        #expect(FastingEngine.currentEatingWindow(
            fasts, eatingHours: 8, now: date(2026, 7, 29, 13)
        ) == nil)
    }

    @Test func windowAnchorsToTheMostRecentlyEndedFast() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 27, 12)),
            completedFast(endingAt: lastEnd),
        ]
        let window = FastingEngine.currentEatingWindow(
            fasts, eatingHours: 8, now: date(2026, 7, 28, 13)
        )
        #expect(window?.start == lastEnd)
    }

    @Test func windowLengthFollowsTheCurrentProtocolNotTheEndedFast() {
        // The ended fast was 16:8, but the user has since switched to OMAD 23:1.
        let window = FastingEngine.currentEatingWindow(
            fastsEndingAtNoon(), eatingHours: 1, now: date(2026, 7, 28, 12, 30)
        )
        #expect(window?.goalHours == 1)
        #expect(window?.endsAt == date(2026, 7, 28, 13))
    }

    @Test func futureDatedFastEndIsIgnored() {
        // A retroactively-added fast ending in the future must not anchor a
        // window that hasn't started yet.
        let fasts = [
            completedFast(endingAt: lastEnd),
            completedFast(endingAt: date(2026, 7, 29, 23)),
        ]
        let window = FastingEngine.currentEatingWindow(
            fasts, eatingHours: 8, now: date(2026, 7, 28, 14)
        )
        #expect(window?.start == lastEnd)
    }
}

// MARK: - "Ends at" labels

@Suite struct EndLabelTests {
    // The time portion follows the device's locale, so these assert the day
    // qualifier — the part that's ours to get right.

    @Test func sameDayIsJustTheTime() {
        let label = TimeFormat.endLabel(
            date(2026, 7, 28, 20), now: date(2026, 7, 28, 9), timeZone: utc
        )
        #expect(!label.contains("tomorrow"))
        #expect(!label.contains("Wed"))
    }

    @Test func nextDayIsQualifiedAsTomorrow() {
        // The common case: an evening 16h fast reaches goal after midnight.
        let label = TimeFormat.endLabel(
            date(2026, 7, 29, 12), now: date(2026, 7, 28, 20), timeZone: utc
        )
        #expect(label.contains("tomorrow"))
    }

    @Test func fartherOutGetsAWeekday() {
        let label = TimeFormat.endLabel(
            date(2026, 7, 31, 12), now: date(2026, 7, 28, 20), timeZone: utc
        )
        #expect(!label.contains("tomorrow"))
        #expect(label.contains("Fri"))
    }

    @Test func justBeforeMidnightIsStillToday() {
        let label = TimeFormat.endLabel(
            date(2026, 7, 28, 23, 59), now: date(2026, 7, 28, 0, 1), timeZone: utc
        )
        #expect(!label.contains("tomorrow"))
    }

    @Test func justAfterMidnightIsTomorrow() {
        let label = TimeFormat.endLabel(
            date(2026, 7, 29, 0, 1), now: date(2026, 7, 28, 23, 59), timeZone: utc
        )
        #expect(label.contains("tomorrow"))
    }

    @Test func dayIsJudgedInTheGivenTimeZoneNotTheDevices() {
        // 03:00 UTC on the 29th is still the evening of the 28th in New York.
        let label = TimeFormat.endLabel(
            date(2026, 7, 29, 3), now: date(2026, 7, 28, 22), timeZone: ny
        )
        #expect(!label.contains("tomorrow"))
    }
}

// MARK: - Start reminder scheduling

@Suite struct StartReminderDatesTests {
    // Reminder set for 20:00.
    private func dates(
        eatingWindowEnd: Date?,
        now: Date,
        daysAhead: Int = 7
    ) -> [Date] {
        FastingEngine.startReminderDates(
            hour: 20, minute: 0,
            eatingWindowEnd: eatingWindowEnd,
            now: now,
            timeZone: utc,
            daysAhead: daysAhead
        )
    }

    @Test func withNoEatingWindowItIsTheDailyTime() {
        let result = dates(eatingWindowEnd: nil, now: date(2026, 7, 28, 9))
        #expect(result.first == date(2026, 7, 28, 20))
    }

    @Test func windowClosingBeforeTheDailyTimeWins() {
        // Window ends 14:00 — earlier than 20:00, so the nudge moves up.
        let result = dates(eatingWindowEnd: date(2026, 7, 28, 14), now: date(2026, 7, 28, 9))
        #expect(result.first == date(2026, 7, 28, 14))
    }

    @Test func theDailyTimeIsSkippedOnTheDayTheWindowCoveredIt() {
        // Exactly the user's rule: one nudge per day, never two.
        let result = dates(eatingWindowEnd: date(2026, 7, 28, 14), now: date(2026, 7, 28, 9))
        #expect(!result.contains(date(2026, 7, 28, 20)))
        #expect(result[1] == date(2026, 7, 29, 20))
    }

    @Test func windowClosingAfterTheDailyTimeLosesToIt() {
        // Window ends 22:00, after the chosen 20:00 — the chosen time is sent.
        let result = dates(eatingWindowEnd: date(2026, 7, 28, 22), now: date(2026, 7, 28, 9))
        #expect(result.first == date(2026, 7, 28, 20))
        #expect(!result.contains(date(2026, 7, 28, 22)))
    }

    @Test func windowAlreadyClosedIsIgnored() {
        let result = dates(eatingWindowEnd: date(2026, 7, 28, 8), now: date(2026, 7, 28, 9))
        #expect(result.first == date(2026, 7, 28, 20))
    }

    @Test func lateEveningWindowBeatsTomorrowsDailyTime() {
        // 21:00 now, so today's 20:00 has passed; the next daily is tomorrow.
        // A window closing at 23:00 tonight is sooner, so it wins.
        let result = dates(eatingWindowEnd: date(2026, 7, 28, 23), now: date(2026, 7, 28, 21))
        #expect(result.first == date(2026, 7, 28, 23))
        #expect(result[1] == date(2026, 7, 29, 20))
    }

    @Test func aRollingWeekIsScheduledSoRemindersSurviveNotOpeningTheApp() {
        let result = dates(eatingWindowEnd: nil, now: date(2026, 7, 28, 9))
        #expect(result.count == 7)
        #expect(result == (0..<7).map { date(2026, 7, 28 + $0, 20) })
    }

    @Test func alwaysAscendingAndInTheFuture() {
        let now = date(2026, 7, 28, 9)
        for windowEnd in [nil, date(2026, 7, 28, 14), date(2026, 7, 28, 22)] {
            let result = dates(eatingWindowEnd: windowEnd, now: now)
            #expect(result.count == 7)
            #expect(result == result.sorted())
            #expect(result.allSatisfy { $0 > now })
        }
    }

    @Test func zeroDaysAheadSchedulesNothing() {
        #expect(dates(eatingWindowEnd: nil, now: date(2026, 7, 28, 9), daysAhead: 0).isEmpty)
    }
}

// MARK: - Validation

@Suite struct ValidationTests {
    private let existing = [
        FastRecord(id: UUID(), start: date(2026, 7, 10, 10), end: date(2026, 7, 10, 12), goalHours: 16),
    ]

    @Test func endMustBeAfterStart() {
        #expect(throws: FastValidationError.endNotAfterStart) {
            try FastValidation.validate(
                start: date(2026, 7, 1, 12), end: date(2026, 7, 1, 12),
                excludingID: nil, against: []
            )
        }
    }

    @Test func durationCappedAtSevenDays() {
        #expect(throws: FastValidationError.tooLong(maxDays: 7)) {
            try FastValidation.validate(
                start: date(2026, 7, 1, 0), end: date(2026, 7, 8, 1),
                excludingID: nil, against: []
            )
        }
    }

    @Test func exactlySevenDaysIsAllowed() {
        #expect(throws: Never.self) {
            try FastValidation.validate(
                start: date(2026, 7, 1, 0), end: date(2026, 7, 8, 0),
                excludingID: nil, against: []
            )
        }
    }

    @Test func overlappingFastIsRejectedWithConflictID() {
        let conflict = existing[0].id
        #expect(throws: FastValidationError.overlap(conflictID: conflict)) {
            try FastValidation.validate(
                start: date(2026, 7, 10, 11), end: date(2026, 7, 10, 13),
                excludingID: nil, against: existing
            )
        }
    }

    @Test func touchingEndpointsAreAllowed() {
        #expect(throws: Never.self) {
            try FastValidation.validate(
                start: date(2026, 7, 10, 12), end: date(2026, 7, 10, 14),
                excludingID: nil, against: existing
            )
        }
    }

    @Test func editingAFastDoesNotConflictWithItself() {
        let id = existing[0].id
        #expect(throws: Never.self) {
            try FastValidation.validate(
                start: date(2026, 7, 10, 10), end: date(2026, 7, 10, 13),
                excludingID: id, against: existing
            )
        }
    }

    @Test func newFastCannotOverlapAnOpenFast() {
        let open = [FastRecord(id: UUID(), start: date(2026, 7, 10, 10), end: nil, goalHours: 16)]
        #expect(throws: (any Error).self) {
            try FastValidation.validate(
                start: date(2026, 7, 11, 0), end: date(2026, 7, 11, 5),
                excludingID: nil, against: open
            )
        }
    }
}
