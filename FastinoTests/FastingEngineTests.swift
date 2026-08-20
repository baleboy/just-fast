//
//  FastingEngineTests.swift
//  FastinoTests
//
//  Exhaustive tests for the pure streak/stat engine (§7): midnight spans, TZ
//  shifts, edits, overlaps, and the rolling-window stats.
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

    @Test func dayBarsCarryTheLongestFastEndingOnEachDay() {
        let now = date(2026, 7, 29, 18)
        let fasts = [
            fast(date(2026, 7, 26, 20), date(2026, 7, 27, 12)), // 16h, goal met
            fast(date(2026, 7, 27, 14), date(2026, 7, 27, 20)), // 6h, same day
            fast(date(2026, 7, 24, 22), date(2026, 7, 25, 8)),  // 10h, missed
        ]
        let bars = FastingEngine.lastDays(fasts, now: now, timeZone: utc, count: 7)
        #expect(bars.count == 7)

        // index 6 = today, 4 = two days ago (27th), 2 = four days ago (25th)
        #expect(approxEqual(bars[4].duration, 16 * 3600))   // the longer of the two
        #expect(bars[4].goalMet == true)
        #expect(approxEqual(bars[2].duration, 10 * 3600))
        #expect(bars[2].goalMet == false)
        #expect(bars[6].duration == 0)                      // nothing today
        #expect(bars[6].isInProgress == false)
    }

    @Test func todaysDayBarTracksTheLiveOpenFast() {
        let now = date(2026, 7, 29, 18)
        let bars = FastingEngine.lastDays(
            [fast(date(2026, 7, 29, 6), nil)], now: now, timeZone: utc, count: 7
        )
        let today = bars[6]
        #expect(today.isInProgress)
        #expect(approxEqual(today.duration, 12 * 3600))
        // Still running, so the day isn't a goal day yet — that's what makes the
        // bar render dashed rather than solid.
        #expect(today.goalMet == false)
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
    // The user starts their fast at 20:00 every day. That anchor — not the length
    // of the last fast — is what closes the eating window.
    private let anchor = DateComponents(hour: 20, minute: 0)
    private let lastEnd = date(2026, 7, 28, 12) // an on-plan 16h fast ended at noon

    private func window(
        _ fasts: [FastRecord],
        now: Date,
        anchor: DateComponents? = nil,
        tz: TimeZone = utc
    ) -> EatingWindow? {
        FastingEngine.currentEatingWindow(
            fasts, anchor: anchor ?? self.anchor, now: now, timeZone: tz
        )
    }

    private func fastsEndingAtNoon() -> [FastRecord] {
        [completedFast(endingAt: lastEnd)]
    }

    @Test func windowOpensAtTheLastFastEndAndClosesAtTheAnchor() {
        let result = window(fastsEndingAtNoon(), now: date(2026, 7, 28, 14))
        #expect(result?.start == lastEnd)
        #expect(result?.end == date(2026, 7, 28, 20))
    }

    // The case this whole model exists for: overrunning must cost eating time,
    // not push the next start later.
    @Test func overrunningTheFastShortensTheWindowRatherThanMovingTheAnchor() {
        // Started 20:00 on a 16:8, meant to break at 12:00, actually broke at 14:00.
        let fasts = [fast(date(2026, 7, 27, 20), date(2026, 7, 28, 14))]
        let result = window(fasts, now: date(2026, 7, 28, 15))
        #expect(result?.end == date(2026, 7, 28, 20)) // unmoved
        #expect(approxEqual(result?.goalInterval, 6 * 3600)) // 8h plan, 6h actual
    }

    @Test func breakingEarlyLengthensTheWindowRatherThanMovingTheAnchor() {
        let fasts = [fast(date(2026, 7, 27, 20), date(2026, 7, 28, 10))]
        let result = window(fasts, now: date(2026, 7, 28, 11))
        #expect(result?.end == date(2026, 7, 28, 20))
        #expect(approxEqual(result?.goalInterval, 10 * 3600))
    }

    @Test func fastingStraightThroughTheAnchorLeavesNoWindow() {
        // Blew past 20:00 by five minutes: already due, so the timer shows plain
        // "Ready" rather than counting down ~24h to tomorrow's anchor.
        let fasts = [fast(date(2026, 7, 27, 20), date(2026, 7, 28, 20, 5))]
        #expect(window(fasts, now: date(2026, 7, 28, 20, 30)) == nil)
    }

    @Test func endingExactlyOnTheAnchorLeavesNoWindow() {
        let fasts = [fast(date(2026, 7, 27, 20), date(2026, 7, 28, 20))]
        #expect(window(fasts, now: date(2026, 7, 28, 20, 1)) == nil)
    }

    @Test func startingSlightlyBeforeTheAnchorIsStillOnPlan() {
        // A fast begun at 19:58 contains the 20:00 occurrence, but that's the
        // anchor it started *on* — it must not read as a missed one.
        let fasts = [fast(date(2026, 7, 27, 19, 58), date(2026, 7, 28, 12))]
        #expect(window(fasts, now: date(2026, 7, 28, 14))?.end == date(2026, 7, 28, 20))
    }

    @Test func progressAndRemainingMidWindow() {
        let result = window(fastsEndingAtNoon(), now: date(2026, 7, 28, 14))!
        let now = date(2026, 7, 28, 14) // 2h into an 8h window
        #expect(abs(result.progress(asOf: now) - 0.25) < 0.001)
        #expect(approxEqual(result.remaining(asOf: now), 6 * 3600))
        #expect(!result.isOver(asOf: now))
    }

    @Test func windowGoesOverAndRemainingTurnsNegative() {
        let result = EatingWindow(start: lastEnd, end: date(2026, 7, 28, 20))
        let now = date(2026, 7, 28, 21) // 1h past the window
        #expect(result.isOver(asOf: now))
        #expect(result.progress(asOf: now) > 1)
        #expect(approxEqual(result.remaining(asOf: now), -3600))
    }

    @Test func noWindowBeforeTheFirstEverFast() {
        #expect(window([], now: lastEnd) == nil)
    }

    @Test func noWindowWhenOnlyFastIsStillOpen() {
        #expect(window([fast(date(2026, 7, 28, 6), nil)], now: date(2026, 7, 28, 14)) == nil)
    }

    @Test func noWindowWhileAFastIsRunningAfterAnEarlierOne() {
        let fasts = fastsEndingAtNoon() + [fast(date(2026, 7, 28, 20), nil)]
        #expect(window(fasts, now: date(2026, 7, 28, 22)) == nil)
    }

    @Test func windowGoesStaleAfterADayAndFallsBackToReady() {
        let fasts = fastsEndingAtNoon()
        // 23h59m later: still shown (badly overrun, but the cadence is intact).
        #expect(window(fasts, now: date(2026, 7, 29, 11, 59)) != nil)
        // Past 24h: no window — the timer shows plain "Ready".
        #expect(window(fasts, now: date(2026, 7, 29, 13)) == nil)
    }

    @Test func windowAnchorsToTheMostRecentlyEndedFast() {
        let fasts = [
            completedFast(endingAt: date(2026, 7, 27, 12)),
            completedFast(endingAt: lastEnd),
        ]
        #expect(window(fasts, now: date(2026, 7, 28, 13))?.start == lastEnd)
    }

    @Test func windowLengthIsIndependentOfTheProtocol() {
        // Same break time, wildly different protocols: the close is the anchor's
        // to set, so changing protocol never resizes the window.
        let short = [fast(date(2026, 7, 28, 11), lastEnd, goal: 1)]
        let long = [fast(date(2026, 7, 27, 13), lastEnd, goal: 23)]
        let now = date(2026, 7, 28, 14)
        #expect(window(short, now: now)?.end == date(2026, 7, 28, 20))
        #expect(window(long, now: now)?.end == date(2026, 7, 28, 20))
    }

    @Test func futureDatedFastEndIsIgnored() {
        // A retroactively-added fast ending in the future must not anchor a
        // window that hasn't started yet.
        let fasts = [
            completedFast(endingAt: lastEnd),
            completedFast(endingAt: date(2026, 7, 29, 23)),
        ]
        #expect(window(fasts, now: date(2026, 7, 28, 14))?.start == lastEnd)
    }

    @Test func anchorHoldsItsWallClockTimeAcrossADSTChange() {
        // NY clocks go back at 02:00 on 2026-11-01. A window opened at 23:00 the
        // night before still closes at 20:00 — 22 absolute hours later, not 21.
        let fasts = [fast(date(2026, 10, 31, 12, tz: ny), date(2026, 10, 31, 23, tz: ny))]
        let result = window(fasts, now: date(2026, 11, 1, 10, tz: ny), tz: ny)
        #expect(result?.end == date(2026, 11, 1, 20, tz: ny))
        #expect(approxEqual(result?.goalInterval, 22 * 3600))
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

// MARK: - Eating stops (§4.8)

@Suite("Eating stops")
struct EatingStopTests {

    private let now = date(2026, 7, 15, 18)

    @Test func noFastsGivesNoStops() {
        #expect(FastingEngine.eatingStops([], now: now, timeZone: utc, count: 30).isEmpty)
    }

    @Test func anEveningStopIsNegativeHoursFromTheEndDaysMidnight() {
        // Stopped eating 20:00 on the 14th, ended 12:00 on the 15th. Credited
        // to the 15th, four hours before its midnight.
        let fasts = [fast(date(2026, 7, 14, 20), date(2026, 7, 15, 12))]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        #expect(stops.count == 1)
        #expect(stops[0].date == date(2026, 7, 15))
        #expect(stops[0].stoppedAt == date(2026, 7, 14, 20))
        #expect(stops[0].hoursFromMidnight == -4)
    }

    @Test func aStopAfterMidnightIsPositive() {
        let fasts = [fast(date(2026, 7, 15, 1, 30), date(2026, 7, 15, 18))]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        #expect(stops[0].hoursFromMidnight == 1.5)
    }

    @Test func theScaleIsContinuousAcrossMidnight() {
        // 23:50 and 00:10 are twenty minutes apart and must read that way —
        // this is the case a wrapped 0–24 axis ruins.
        let fasts = [
            fast(date(2026, 7, 13, 23, 50), date(2026, 7, 14, 12)),
            fast(date(2026, 7, 15, 0, 10), date(2026, 7, 15, 12))
        ]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)
        let tenMinutes: Double = 10.0 / 60
        let gap: Double = stops[1].hoursFromMidnight - stops[0].hoursFromMidnight

        #expect(abs(stops[0].hoursFromMidnight + tenMinutes) < 0.0001)
        #expect(abs(stops[1].hoursFromMidnight - tenMinutes) < 0.0001)
        #expect(abs(gap - tenMinutes * 2) < 0.0001)
    }

    @Test func stopsShareTheirColumnWithTheBarForTheSameFast() {
        let fasts = [fast(date(2026, 7, 14, 20), date(2026, 7, 15, 12))]
        let bars = FastingEngine.lastDays(fasts, now: now, timeZone: utc, count: 30)
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        let barDate = bars.first { $0.duration > 0 }?.date
        #expect(barDate == stops[0].date)
    }

    @Test func theLongestFastOfADayWins() {
        // Same rule as `lastDays`, so the dot describes the fast the bar draws.
        let fasts = [
            fast(date(2026, 7, 15, 2), date(2026, 7, 15, 8)),
            fast(date(2026, 7, 14, 18), date(2026, 7, 15, 14))
        ]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        #expect(stops.count == 1)
        #expect(stops[0].stoppedAt == date(2026, 7, 14, 18))
    }

    @Test func theOpenFastIsCreditedToToday() {
        let fasts = [FastRecord(start: date(2026, 7, 14, 21), end: nil, goalHours: 16)]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        #expect(stops.count == 1)
        #expect(stops[0].date == date(2026, 7, 15))
        #expect(stops[0].hoursFromMidnight == -3)
    }

    @Test func daysWithoutAFastAreAbsentRatherThanZero() {
        let fasts = [
            fast(date(2026, 7, 11, 20), date(2026, 7, 12, 12)),
            fast(date(2026, 7, 14, 20), date(2026, 7, 15, 12))
        ]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        #expect(stops.map(\.date) == [date(2026, 7, 12), date(2026, 7, 15)])
    }

    @Test func onlyTheRequestedWindowIsReturned() {
        let fasts = [
            fast(date(2026, 7, 14, 20), date(2026, 7, 15, 12)),
            fast(date(2026, 5, 1, 20), date(2026, 5, 2, 12))
        ]
        let stops = FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)

        #expect(stops.count == 1)
    }

    @Test func theOffsetIsMeasuredAgainstTheLocalMidnightSoDSTCannotSkewIt() {
        // 2026-03-08, America/New_York: the clocks go forward at 02:00. A 20:00
        // stop the evening before is still four hours before the 8th's midnight,
        // even though the 8th is only 23 hours long.
        let fasts = [fast(date(2026, 3, 7, 20, tz: ny), date(2026, 3, 8, 13, tz: ny))]
        let stops = FastingEngine.eatingStops(
            fasts, now: date(2026, 3, 8, 18, tz: ny), timeZone: ny, count: 30
        )

        #expect(stops[0].date == date(2026, 3, 8, tz: ny))
        #expect(stops[0].hoursFromMidnight == -4)
    }

    @Test func theDayIsJudgedInTheGivenTimeZone() {
        // Ended 02:00 UTC on the 15th, which is still the 14th in New York.
        let fasts = [fast(date(2026, 7, 14, 10), date(2026, 7, 15, 2))]

        #expect(FastingEngine.eatingStops(fasts, now: now, timeZone: utc, count: 30)[0].date
                == date(2026, 7, 15))
        #expect(FastingEngine.eatingStops(fasts, now: now, timeZone: ny, count: 30)[0].date
                == date(2026, 7, 14, tz: ny))
    }
}
