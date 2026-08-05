//
//  FastingEngine.swift
//  JustFast
//
//  Pure streak/stat engine (§2, §4.3, §7). Every function is a pure function of
//  `[FastRecord]` + a reference `now` + a `TimeZone`. No SwiftData, no globals,
//  no stored streak — everything is derived. This is what the unit-test suite
//  hammers (midnight spans, TZ shifts, edits, overlaps).
//
//  Streak rule (§2): a *goal day* is a calendar day (in the given time zone) on
//  which a completed fast **ended**. Streaks are strict — one calendar day
//  passing with no completed fast ending on it resets the streak to zero.
//

import Foundation

nonisolated enum FastingEngine {

    // MARK: Calendar helpers

    /// A gregorian calendar pinned to the given time zone.
    private static func calendar(for timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// A stable, comparable "day number": whole calendar days between the unix
    /// epoch's local start-of-day and the date's local start-of-day. DST-safe
    /// because it counts calendar days, not fixed 86 400-second chunks.
    static func dayNumber(of date: Date, timeZone: TimeZone) -> Int {
        let cal = calendar(for: timeZone)
        let reference = cal.startOfDay(for: Date(timeIntervalSince1970: 0))
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: reference, to: target).day ?? 0
    }

    // MARK: Goal days

    /// The set of day numbers on which at least one *completed* fast ended.
    static func goalDayNumbers(_ fasts: [FastRecord], timeZone: TimeZone) -> Set<Int> {
        var days = Set<Int>()
        for fast in fasts where fast.isGoalMet {
            guard let end = fast.end else { continue }
            days.insert(dayNumber(of: end, timeZone: timeZone))
        }
        return days
    }

    // MARK: Streaks

    /// Current streak: length of the run of consecutive goal days anchored at
    /// today (if today is already a goal day) or yesterday (today isn't over,
    /// so a goal day yesterday keeps the streak alive). Otherwise 0.
    static func currentStreak(_ fasts: [FastRecord], now: Date, timeZone: TimeZone) -> Int {
        let goalDays = goalDayNumbers(fasts, timeZone: timeZone)
        guard !goalDays.isEmpty else { return 0 }

        let today = dayNumber(of: now, timeZone: timeZone)
        let anchor: Int
        if goalDays.contains(today) {
            anchor = today
        } else if goalDays.contains(today - 1) {
            anchor = today - 1
        } else {
            return 0
        }

        var count = 0
        var day = anchor
        while goalDays.contains(day) {
            count += 1
            day -= 1
        }
        return count
    }

    /// Longest run of consecutive goal days anywhere in history.
    static func longestStreak(_ fasts: [FastRecord], timeZone: TimeZone) -> Int {
        let sorted = goalDayNumbers(fasts, timeZone: timeZone).sorted()
        guard !sorted.isEmpty else { return 0 }

        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if sorted[i] == sorted[i - 1] + 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }
        return longest
    }

    // MARK: Fasts of note

    /// The single open fast, if any (spec guarantees at most one).
    static func openFast(_ fasts: [FastRecord]) -> FastRecord? {
        fasts.first(where: \.isOpen)
    }

    /// Duration of the longest fast ever — counting the live open fast's
    /// current elapsed time so a record-breaking fast in progress is reflected.
    static func longestFast(_ fasts: [FastRecord], now: Date) -> TimeInterval {
        fasts.map { $0.duration(asOf: now) }.max() ?? 0
    }

    // MARK: Eating window

    /// How stale the last fast may be before the eating window stops being a
    /// useful frame. Past this the daily cadence is broken, so the timer falls
    /// back to the plain "Ready" state rather than showing a wildly overrun
    /// window (§4.1).
    static let eatingWindowStaleAfter: TimeInterval = 24 * 3600

    /// The eating window currently in progress, or `nil` when there isn't one to
    /// show: a fast is running, no fast has ever been closed, the last one ended
    /// longer ago than `staleAfter`, or the user is already past due (below).
    ///
    /// - Parameter anchor: the wall-clock time the user starts their fast, as
    ///   hour/minute components. The window closes at the next occurrence of it,
    ///   so the schedule never drifts: fasting past plan costs eating time rather
    ///   than pushing tomorrow's start later, and breaking early buys eating time
    ///   back. The protocol's `eatingHours` describes the shape of an on-plan day
    ///   but never sets this window's length.
    static func currentEatingWindow(
        _ fasts: [FastRecord],
        anchor: DateComponents,
        now: Date,
        timeZone: TimeZone,
        staleAfter: TimeInterval = eatingWindowStaleAfter
    ) -> EatingWindow? {
        guard openFast(fasts) == nil else { return nil }

        // The most recently *closed* fast. A retroactively-added fast ending in
        // the future must not anchor a window that hasn't opened yet.
        let closed = fasts.compactMap { record -> (record: FastRecord, end: Date)? in
            guard let end = record.end, end <= now else { return nil }
            return (record, end)
        }
        guard let last = closed.max(by: { $0.end < $1.end }) else { return nil }
        guard now.timeIntervalSince(last.end) < staleAfter else { return nil }

        let cal = calendar(for: timeZone)
        guard let end = cal.nextDate(after: last.end, matching: anchor, matchingPolicy: .nextTime) else {
            return nil
        }

        // The fast ran past its goal *and* past the user's own next start time —
        // they're already due, so there's no window left to count down. Without
        // this the next anchor is nearly a day out and the timer would show an
        // absurd ~24h window.
        //
        // Measured from the goal, not the fast's start: starting a few minutes
        // either side of the anchor is the on-plan case and must not count as a
        // missed one.
        let goalReachedAt = last.record.goalReachedAt
        if goalReachedAt < last.end,
           let missed = cal.nextDate(after: goalReachedAt, matching: anchor, matchingPolicy: .nextTime),
           missed <= last.end {
            return nil
        }

        return EatingWindow(start: last.end, end: end)
    }

    // MARK: Rolling windows

    /// For each of the last `count` calendar days (oldest first, ending today),
    /// whether it was a goal day.
    static func lastDaysGoalMet(
        _ fasts: [FastRecord],
        now: Date,
        timeZone: TimeZone,
        count: Int = 7
    ) -> [Bool] {
        let goalDays = goalDayNumbers(fasts, timeZone: timeZone)
        let today = dayNumber(of: now, timeZone: timeZone)
        return (0..<count).reversed().map { offset in
            goalDays.contains(today - offset)
        }
    }

    /// Fasts that *ended* within the last `days` days (default 30), closed only.
    static func recentlyEndedFasts(
        _ fasts: [FastRecord],
        now: Date,
        days: Int = 30
    ) -> [FastRecord] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return fasts.filter { fast in
            guard let end = fast.end else { return false }
            return end >= cutoff && end <= now
        }
    }

    /// Average duration of fasts that ended in the last `days` days; nil if none.
    static func averageDuration(
        _ fasts: [FastRecord],
        now: Date,
        days: Int = 30
    ) -> TimeInterval? {
        let recent = recentlyEndedFasts(fasts, now: now, days: days)
        guard !recent.isEmpty else { return nil }
        let total = recent.reduce(0.0) { $0 + ($1.finalDuration ?? 0) }
        return total / Double(recent.count)
    }

    /// Fraction (0...1) of fasts ended in the last `days` days that met goal;
    /// nil if there were none.
    static func goalCompletionRate(
        _ fasts: [FastRecord],
        now: Date,
        days: Int = 30
    ) -> Double? {
        let recent = recentlyEndedFasts(fasts, now: now, days: days)
        guard !recent.isEmpty else { return nil }
        let met = recent.filter(\.isGoalMet).count
        return Double(met) / Double(recent.count)
    }

    // MARK: One-shot summary

    /// Compute every derived statistic in one pass for the Stats screen.
    static func summary(_ fasts: [FastRecord], now: Date, timeZone: TimeZone) -> StatsSummary {
        StatsSummary(
            currentStreak: currentStreak(fasts, now: now, timeZone: timeZone),
            longestStreak: longestStreak(fasts, timeZone: timeZone),
            currentFastDuration: openFast(fasts)?.duration(asOf: now),
            longestFast: longestFast(fasts, now: now),
            last7Days: lastDaysGoalMet(fasts, now: now, timeZone: timeZone, count: 7),
            averageDuration30d: averageDuration(fasts, now: now, days: 30),
            goalCompletionRate30d: goalCompletionRate(fasts, now: now, days: 30)
        )
    }
}

/// The stretch between the end of one fast and the start of the next (§4.1).
/// Deliberately shaped like `FastRecord`'s goal accessors so the timer screen can
/// drive the same ring from either.
nonisolated struct EatingWindow: Equatable, Sendable {
    /// When the last fast ended — the instant the eating window opened.
    let start: Date
    /// When the next fast is due: the user's daily start-time anchor.
    let end: Date

    /// This window's length. Unlike the fast's goal it is *not* fixed — it's
    /// whatever the anchor leaves once the fast actually ended. That's the point:
    /// a long fast shortens today's window instead of moving tomorrow's start.
    var goalInterval: TimeInterval { max(0, end.timeIntervalSince(start)) }

    func elapsed(asOf now: Date) -> TimeInterval { max(0, now.timeIntervalSince(start)) }

    /// Time left before the next fast is due; negative once the window is over.
    func remaining(asOf now: Date) -> TimeInterval { end.timeIntervalSince(now) }

    /// 0...∞ — exceeds 1 once the window has been over for a while.
    func progress(asOf now: Date) -> Double {
        guard goalInterval > 0 else { return 1 }
        return elapsed(asOf: now) / goalInterval
    }

    func isOver(asOf now: Date) -> Bool { now >= end }
}

nonisolated struct StatsSummary: Equatable, Sendable {
    var currentStreak: Int
    var longestStreak: Int
    /// Live elapsed duration of the open fast; nil when idle.
    var currentFastDuration: TimeInterval?
    var longestFast: TimeInterval
    /// Oldest-first, length 7, true where the day was a goal day.
    var last7Days: [Bool]
    var averageDuration30d: TimeInterval?
    var goalCompletionRate30d: Double?
}
