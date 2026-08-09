//
//  MetabolicZoneTests.swift
//  FastinoTests
//
//  The zone bands behind the Ember ring, the zone cards and the milestone
//  notifications (§7 — pure logic, so it gets unit tests).
//

import Foundation
import Testing
@testable import Fastino

@Suite struct MetabolicZoneTests {

    @Test func zoneFollowsElapsedTime() {
        #expect(MetabolicZone.current(elapsed: 0) == .burning)
        #expect(MetabolicZone.current(elapsed: 11.9 * 3600) == .burning)
        // The boundary instant belongs to the zone it opens.
        #expect(MetabolicZone.current(elapsed: 12 * 3600) == .fatBurn)
        #expect(MetabolicZone.current(elapsed: 13.9 * 3600) == .fatBurn)
        #expect(MetabolicZone.current(elapsed: 14 * 3600) == .ketosis)
        // Past goal the last zone simply stays open.
        #expect(MetabolicZone.current(elapsed: 40 * 3600) == .ketosis)
    }

    @Test func boundariesAreAbsoluteHoursNotFractionsOfTheGoal() {
        // Fat burn opens 12h in whether the plan is 16:8 or 20:4 — the ring's
        // bands move relative to the goal, the physiology doesn't.
        #expect(MetabolicZone.fatBurn.span(forGoalHours: 16) == 12...14)
        #expect(MetabolicZone.fatBurn.span(forGoalHours: 20) == 12...14)
        #expect(MetabolicZone.burning.span(forGoalHours: 20) == 0...12)
    }

    @Test func theLastZoneRunsToTheGoal() {
        #expect(MetabolicZone.ketosis.span(forGoalHours: 16) == 14...16)
        #expect(MetabolicZone.ketosis.span(forGoalHours: 23) == 14...23)
    }

    @Test func aGoalShorterThanABoundaryLeavesTheZoneUnreachable() {
        // A 14:10 plan ends exactly where ketosis would start.
        #expect(MetabolicZone.ketosis.span(forGoalHours: 14) == nil)
        #expect(MetabolicZone.ketosis.isReachable(withGoalHours: 14) == false)
        #expect(MetabolicZone.fatBurn.span(forGoalHours: 14) == 12...14)

        // And a hypothetical goal below the first boundary leaves only zone one.
        #expect(MetabolicZone.fatBurn.isReachable(withGoalHours: 10) == false)
        #expect(MetabolicZone.burning.span(forGoalHours: 10) == 0...10)
    }

    @Test func spansTileTheWholeGoalWithoutGapsOrOverlap() {
        for goal in [14, 16, 18, 20, 23] {
            let spans = MetabolicZone.allCases.compactMap { $0.span(forGoalHours: goal) }
            #expect(spans.first?.lowerBound == 0)
            #expect(spans.last?.upperBound == Double(goal))
            for (a, b) in zip(spans, spans.dropFirst()) {
                #expect(a.upperBound == b.lowerBound)
            }
        }
    }
}
