//
//  WidgetSurfaceTests.swift
//  FastinoTests
//
//  The pure half of the widget surfaces (§4.5, §4.7): when a running fast
//  changes what's on screen, and the URL the Lock Screen widget opens.
//
//  The views themselves, the Control Center toggle and the store reads all need
//  a real process and a real tap, so they are verified by hand — see
//  IMPLEMENTATION.md. What's here is what a mistake in would be invisible.
//

import Foundation
import SwiftData
import Testing
@testable import Fastino

private let start = Date(timeIntervalSince1970: 1_700_000_000)

private func openFast(goal: Int = 16) -> FastRecord {
    FastRecord(start: start, end: nil, goalHours: goal)
}

// MARK: - Timeline instants

@Suite("Widget timeline")
struct FastingTimelineTests {

    /// The regression this whole helper exists for: without the hour marks the
    /// display sits on "9h" for an hour at a time while the fast runs on.
    @Test func includesEveryWholeHourMark() {
        let dates = FastingTimeline.refreshDates(for: openFast(), now: start)
        for hour in 1...48 {
            let mark = start.addingTimeInterval(Double(hour) * 3600)
            #expect(dates.contains(mark), "missing the \(hour)h mark")
        }
    }

    @Test func includesEveryZoneBoundaryAndTheGoal() {
        let fast = openFast()
        let dates = FastingTimeline.refreshDates(for: fast, now: start)
        for zone in MetabolicZone.allCases where zone.startHours > 0 {
            #expect(dates.contains(start.addingTimeInterval(zone.startHours * 3600)))
        }
        #expect(dates.contains(fast.goalReachedAt))
    }

    @Test func excludesInstantsAtOrBeforeNow() {
        let now = start.addingTimeInterval(3 * 3600)
        let dates = FastingTimeline.refreshDates(for: openFast(), now: now)
        #expect(dates.allSatisfy { $0 > now })
        // The 1h, 2h and 3h marks are all in the past; 4h is the first left.
        #expect(dates.first == start.addingTimeInterval(4 * 3600))
    }

    /// With a 12-hour goal the 12h mark, the fat-burn boundary and the goal are
    /// all the same instant. A widget asked to draw the same moment three times
    /// is a wasted timeline slot.
    @Test func collapsesCoincidentInstants() {
        let dates = FastingTimeline.refreshDates(for: openFast(goal: 12), now: start)
        let twelve = start.addingTimeInterval(12 * 3600)
        #expect(dates.count(where: { $0 == twelve }) == 1)
    }

    @Test func isSortedAscending() {
        let dates = FastingTimeline.refreshDates(for: openFast(), now: start)
        #expect(dates == dates.sorted())
    }

    /// A fast this long is past anything FastValidation accepts, but the
    /// provider still has to hand WidgetKit something bounded.
    @Test func capsHowFarAheadItSchedules() {
        let now = start.addingTimeInterval(60 * 3600)
        let dates = FastingTimeline.refreshDates(for: openFast(), now: now)
        #expect(dates.allSatisfy { $0 <= start.addingTimeInterval(48 * 3600) })
    }
}

// MARK: - Entry

@Suite("Widget entry")
struct FastingEntryTests {

    /// Past the goal the ring stays full rather than wrapping round to empty.
    @Test func progressClampsAtTheGoal() {
        let entry = FastingEntry(
            date: start.addingTimeInterval(20 * 3600),
            fast: openFast()
        )
        #expect(entry.progress == 1)
    }

    @Test func idleEntryHasNoZoneAndNoProgress() {
        let entry = FastingEntry(date: start, fast: nil)
        #expect(entry.zone == nil)
        #expect(entry.progress == 0)
        #expect(entry.shortLabel == "—")
    }

    /// Hours only — minutes on a fast measured in hours are noise at this size.
    @Test func labelRoundsDownToWholeHours() {
        let entry = FastingEntry(
            date: start.addingTimeInterval(9 * 3600 + 59 * 60),
            fast: openFast()
        )
        #expect(entry.shortLabel == "9h")
    }
}

// MARK: - URL scheme

@Suite("Fastino URL")
struct FastinoURLTests {

    @Test func theTimerURLRoundTrips() {
        #expect(FastinoURL.tabName(from: FastinoURL.timer) == "timer")
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(FastinoURL.tabName(from: URL(string: "fastino://Stats")!) == "stats")
    }

    @Test func aForeignSchemeIsRejected() {
        #expect(FastinoURL.tabName(from: URL(string: "https://timer")!) == nil)
    }

    @Test func aHostlessURLIsRejected() {
        #expect(FastinoURL.tabName(from: URL(string: "fastino://")!) == nil)
    }

    /// The other half of the hop `RootView.onOpenURL` makes. iOS always asks
    /// the user to confirm a custom-scheme open from `simctl`, and simctl can't
    /// tap, so the routing is proven here rather than on a booted device.
    @Test func everyTabIsReachableByName() {
        for tab in FlameTab.allCases {
            let url = URL(string: "fastino://\(tab.rawValue.lowercased())")!
            let name = try? #require(FastinoURL.tabName(from: url))
            #expect(name.flatMap(FlameTab.named) == tab)
        }
    }

    @Test func anUnknownHostRoutesNowhere() {
        #expect(FlameTab.named("elsewhere") == nil)
    }
}

// MARK: - What the Control Center toggle does to the store

/// `SetFastingIntent` lives in the widget extension, which `FastinoTests` can't
/// reach — but its whole body is these four branches against `FastStore`, which
/// is the single write path and is right here. Guarding on the store rather
/// than trusting the control's `value` is what makes a stale toggle a no-op
/// instead of a thrown error surfacing in Control Center.
@MainActor
@Suite("Control Center toggle")
struct ControlToggleTests {
    private func makeStore() -> FastStore {
        FastStore(context: ModelContext(AppContainer.inMemory()))
    }

    @Test func turningOnWhileIdleStartsAFast() throws {
        let store = makeStore()
        try store.startFast(createdVia: .control)
        let open = try #require(store.openFast())
        #expect(open.createdVia == .control)
    }

    @Test func turningOffWhileFastingEndsIt() throws {
        let store = makeStore()
        try store.startFast(createdVia: .control)
        _ = try store.endFast(createdVia: .control)
        #expect(store.openFast() == nil)
    }

    /// The stale-snapshot cases the intent's guards exist for.
    @Test func startingWhileAlreadyFastingIsRefused() throws {
        let store = makeStore()
        try store.startFast(createdVia: .control)
        #expect(throws: AppError.alreadyFasting) {
            try store.startFast(createdVia: .control)
        }
        #expect(store.allFasts().count == 1)
    }

    @Test func endingWhileIdleIsRefused() {
        let store = makeStore()
        #expect(throws: AppError.notFasting) {
            _ = try store.endFast(createdVia: .control)
        }
        #expect(store.allFasts().isEmpty)
    }
}
