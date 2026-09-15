//
//  SleepScatterScaleTests.swift
//  FastinoTests
//
//  The sleep scatter's two axes (§4.8): clock time across, hours asleep up.
//  All pure — no Charts, no HealthKit, no view.
//

import Foundation
import Testing
@testable import Fastino

/// Signed hours from the day's midnight, the way the panel measures them: an
/// evening time the day *before* the column is negative.
private func evening(_ hour: Double) -> Double { hour - 24 }

private func scale(
    _ nights: [(stop: Double, asleep: Double)],
    anchor: Double? = nil
) -> SleepScatterScale.Scale? {
    SleepScatterScale.scale(nights: nights, anchor: anchor)
}

private func night(_ stop: Double, _ asleep: Double = 7) -> (stop: Double, asleep: Double) {
    (stop: stop, asleep: asleep)
}

@Suite("Sleep scatter scale")
struct SleepScatterScaleTests {

    @Test func nothingToDrawHasNoScale() {
        #expect(scale([]) == nil)
    }

    /// Half an hour of air past the stops, so no dot sits on the frame.
    @Test func padsTheStops() throws {
        let s = try #require(scale([night(evening(20)), night(evening(21))]))
        #expect(s.xDomain.lowerBound == evening(20) - 0.5)
        #expect(s.xDomain.upperBound == evening(21) + 0.5)
    }

    /// Later is to the right — the values are drawn as they are.
    @Test func laterIsRight() throws {
        let s = try #require(scale([night(evening(20)), night(0.5)]))
        #expect(s.xDomain.lowerBound < evening(20))
        #expect(s.xDomain.upperBound > 0.5)
    }

    // MARK: Hours asleep

    /// The sleep axis frames the nights on whole hours, not the whole day:
    /// a zero base would spend half the panel on hours nobody sleeps.
    @Test func sleepAxisFramesTheNights() throws {
        let s = try #require(scale([night(evening(20), 6.2), night(evening(21), 8.1)]))
        #expect(s.yDomain == 5...9)
    }

    @Test func sleepAxisNeverBelowZero() throws {
        let s = try #require(scale([night(evening(20), 0.2)]))
        #expect(s.yDomain.lowerBound == 0)
    }

    @Test func sleepIsNeverFiltered() throws {
        let s = try #require(scale([night(evening(20), 7), night(evening(20.5), 13.5)]))
        #expect(s.yDomain.upperBound >= 13.5)
    }

    // MARK: The anchor

    /// An anchor near the times actually kept is context worth having, and
    /// widens the scale to fit.
    @Test func anchorNearTheDataIsKept() throws {
        let s = try #require(scale([night(evening(21))], anchor: evening(20)))
        #expect(s.anchor == evening(20))
        #expect(s.xDomain.lowerBound <= evening(20))
    }

    /// An anchor nobody is keeping is dropped rather than allowed to squash the
    /// real times into a band — which is exactly when the real times matter most.
    @Test func anchorFarFromTheDataIsDropped() throws {
        let s = try #require(scale([night(evening(23)), night(evening(23.5))], anchor: evening(14)))
        #expect(s.anchor == nil)
        #expect(s.xDomain.lowerBound == evening(23) - 0.5)
    }

    @Test func noAnchorGivenIsNotDrawn() throws {
        let s = try #require(scale([night(evening(20))]))
        #expect(s.anchor == nil)
    }

    // MARK: Ticks

    /// An axis of times has to be labelled at times — every tick is a whole
    /// clock hour, and every sleep tick a whole hour.
    @Test func ticksLandOnWholeHours() throws {
        let s = try #require(scale([night(evening(20.4), 6.3), night(evening(22.7), 8.6)]))
        #expect(!s.xTicks.isEmpty)
        #expect(!s.yTicks.isEmpty)
        for tick in s.xTicks + s.yTicks {
            #expect(tick.truncatingRemainder(dividingBy: 1) == 0)
        }
    }

    @Test func ticksStayInsideTheScales() throws {
        let s = try #require(scale([night(evening(19.4), 5.1), night(evening(23.2), 9.4)]))
        for tick in s.xTicks { #expect(s.xDomain.contains(tick)) }
        for tick in s.yTicks { #expect(s.yDomain.contains(tick)) }
    }

    /// A narrow evening is labelled every hour; a wide one every two, so the
    /// labels don't collide across a phone's width.
    @Test func narrowEveningTicksEveryHour() throws {
        let s = try #require(scale([night(evening(19)), night(evening(22))]))
        #expect(s.xTicks == [evening(19), evening(20), evening(21), evening(22)])
    }

    @Test func wideEveningTicksEveryTwoHours() throws {
        let s = try #require(scale([night(evening(17)), night(1)]))
        for tick in s.xTicks {
            #expect(tick.truncatingRemainder(dividingBy: 2) == 0)
        }
    }

    @Test func wideSleepRangeTicksEveryTwoHours() throws {
        let s = try #require(scale([night(evening(20), 3), night(evening(21), 10)]))
        for tick in s.yTicks {
            #expect(tick.truncatingRemainder(dividingBy: 2) == 0)
        }
    }

    // MARK: Outliers

    /// A fast started in the morning lands a long way from the evening the
    /// panel is drawn around. One of those must not stretch the axis across a
    /// day and pile every real night into one column.
    @Test func aMorningStopDoesNotSetTheScale() throws {
        let ordinary = [evening(20), evening(20.5), evening(21), evening(19.5)].map { night($0) }
        let s = try #require(scale(ordinary + [night(evening(4))]))
        #expect(s.xDomain.lowerBound > evening(4))
        let without = try #require(scale(ordinary))
        #expect(s.xDomain == without.xDomain)
    }

    /// A clock axis wider than a day would print the same time twice.
    @Test func neverWiderThanADay() throws {
        let s = try #require(scale([night(evening(2)), night(6), night(14), night(22)]))
        #expect(s.xDomain.upperBound - s.xDomain.lowerBound <= 24)
    }
}
