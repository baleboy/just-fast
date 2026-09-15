//
//  SleepSplitTests.swift
//  FastinoTests
//
//  The sleep scatter's one summary (§4.8): mean sleep either side of the
//  planned stop. Pure — no Charts, no HealthKit, no view.
//

import Foundation
import Testing
@testable import Fastino

private func evening(_ hour: Double) -> Double { hour - 24 }
private func night(_ stop: Double, _ asleep: Double) -> (stop: Double, asleep: Double) {
    (stop: stop, asleep: asleep)
}

@Suite("Sleep split")
struct SleepSplitTests {

    private let sixNights = [
        night(evening(19), 8), night(evening(19.5), 7), night(evening(20), 7.5),
        night(evening(21), 6), night(evening(21.5), 6.5), night(evening(22), 6.5),
    ]

    @Test func splitsAtTheAnchor() throws {
        let s = try #require(SleepSplit.summary(nights: sixNights, anchor: evening(20)))
        #expect(s.isAnchor)
        #expect(s.threshold == evening(20))
        #expect(s.earlier == SleepSplit.Group(meanHours: 7.5, nights: 3))
        #expect(s.later.nights == 3)
        #expect(abs(s.later.meanHours - 6.333) < 0.01)
    }

    /// A stop exactly on the line counts as keeping to it.
    @Test func onTheLineIsEarlier() throws {
        let s = try #require(SleepSplit.summary(nights: sixNights, anchor: evening(20)))
        #expect(s.earlier.nights == 3)
    }

    @Test func fallsBackToTheMedianWithoutAnAnchor() throws {
        let s = try #require(SleepSplit.summary(nights: sixNights, anchor: nil))
        #expect(!s.isAnchor)
        #expect(s.earlier.nights >= SleepSplit.minimumNights)
        #expect(s.later.nights >= SleepSplit.minimumNights)
    }

    // MARK: Nothing to say

    @Test func tooFewNightsSaysNothing() {
        #expect(SleepSplit.summary(nights: Array(sixNights.prefix(5)), anchor: evening(20)) == nil)
    }

    /// Enough nights in all, but all on one side of the line: an average of
    /// two nights is not a fact.
    @Test func aThinSideSaysNothing() {
        let lopsided = sixNights + [night(evening(18), 8), night(evening(18.5), 8)]
        #expect(SleepSplit.summary(nights: lopsided, anchor: evening(23)) == nil)
    }

    @Test func emptyIsNil() {
        #expect(SleepSplit.summary(nights: [], anchor: evening(20)) == nil)
    }
}
