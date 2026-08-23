//
//  DemoSeeder.swift
//  Fastino
//
//  DEBUG-only helper to seed sample data for screenshots / manual testing.
//  Activated only when the process is launched with `-seedDemo 1`, and never
//  compiled into release builds.
//

import Foundation
import SwiftData

enum DemoSeeder {
    /// Sample notes for the seed. `nil` in most slots, because a note is the
    /// exception and a list where every row carries one wouldn't show that.
    private static let demoNotes: [String?] = [
        nil,
        "Felt easy today",
        "Broke early\nHeadache from about hour fourteen",
        "Long walk in the afternoon and no hunger at all until the very end",
        nil,
    ]

    static var isRequested: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-seedDemo")
            || seedsEatingWindow
            || seedsHistory
        #else
        return false
        #endif
    }

    /// `-seedHistory` extends the seed to three months of fasts, which is what
    /// the Stats screen's Health panels (§4.8) need before their weekly bars
    /// and 30-day columns show anything but a stub.
    ///
    /// The stop times deliberately track the same wobble
    /// `FixtureHealthProvider` uses for sleep and weight, so the two series on
    /// a panel line up rather than looking unrelated. Both sides are invented data;
    /// making them agree is what makes the screen reviewable.
    static var seedsHistory: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-seedHistory")
        #else
        return false
        #endif
    }

    /// `-seedEating` seeds an eating window (last fast closed) instead of an
    /// active fast, for checking the between-fasts state.
    static var seedsEatingWindow: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-seedEating")
        #else
        return false
        #endif
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        #if DEBUG
        guard isRequested else { return }
        let store = FastStore(context: context)
        guard store.allFasts().isEmpty else { return }

        let cal = Calendar.current
        let now = Date()
        let goal = 16

        // A handful of completed fasts on recent consecutive days (builds a streak).
        //
        // Each ends at noon rather than at whatever time the seed happens to
        // run, so the schedule reads like a real 16:8 — stop eating just before
        // 20:00, break the fast at midday. Anchoring to `now` instead put every
        // fast's start in the small hours, which the "stopped eating"
        // panel (§4.8) shows up immediately. The calendar days, and so the
        // streak and the week strip, are unaffected.
        for daysAgo in 1...(seedsHistory ? 89 : 4) {
            // A couple of missed days a month, so the gaps are exercised.
            if seedsHistory, daysAgo % 17 == 5 { continue }
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            // Fixed 16h15m normally. With a long history, the stop time moves
            // with the same wobble the health fixture uses (above), so a longer
            // fast means an earlier stop and a longer night.
            let wobble = seedsHistory ? sin(Double(daysAgo) * 0.7) : 0
            let start = end.addingTimeInterval(-Double(goal) * 3600 - 900 - wobble * 3600)
            let fast = Fast(start: start, end: end, goalHours: goal, protocolID: "16:8", createdVia: .app)
            // A few notes, so History's note line has something to draw — one
            // short, one long enough to truncate, one with a second line the
            // row must not show.
            fast.note = Self.demoNotes[daysAgo % demoNotes.count]
            context.insert(fast)
        }
        if seedsEatingWindow {
            // A fast that ended 2h ago, so the main screen shows the eating
            // window ring counting down to the next fast.
            let end = now.addingTimeInterval(-2 * 3600)
            let start = end.addingTimeInterval(-Double(goal) * 3600 - 900)
            context.insert(Fast(start: start, end: end, goalHours: goal, protocolID: "16:8", createdVia: .app))
        } else {
            // An open fast started 10h ago so the main screen shows an active ring.
            let openStart = now.addingTimeInterval(-10 * 3600)
            context.insert(Fast(start: openStart, end: nil, goalHours: goal, protocolID: "16:8", createdVia: .app))
        }

        try? context.save()
        #endif
    }
}
