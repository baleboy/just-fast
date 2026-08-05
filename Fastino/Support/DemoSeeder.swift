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
    static var isRequested: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-seedDemo") || seedsEatingWindow
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
        for daysAgo in 1...4 {
            let end = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            let start = end.addingTimeInterval(-Double(goal) * 3600 - 900) // 16h15m
            let fast = Fast(start: start, end: end, goalHours: goal, protocolID: "16:8", createdVia: .app)
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
