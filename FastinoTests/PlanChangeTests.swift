//
//  PlanChangeTests.swift
//  FastinoTests
//
//  Re-goaling the fast in progress (§4.1) — `FastStore.applyProtocol`.
//
//  The rule everywhere else is that goalHours/protocolID are snapshotted at
//  start and a Settings change never reaches back. This is the single sanctioned
//  exception, reached only from the plan dialog's explicit "this fast too", so
//  what these guard is that it stays *narrow*: the open fast moves, nothing else
//  does, and the settings row is not the thing being read.
//

import Foundation
import SwiftData
import Testing
@testable import Fastino

@MainActor
@Suite("Applying a plan to the fast in progress")
struct PlanChangeTests {
    /// A fresh in-memory store plus its FastStore, so each test starts empty.
    private func makeStore() -> (FastStore, ModelContext) {
        let context = ModelContext(AppContainer.inMemory())
        return (FastStore(context: context), context)
    }

    private func insert(_ fast: Fast, into context: ModelContext) -> Fast {
        context.insert(fast)
        return fast
    }

    @Test("The open fast takes the new goal and protocol")
    func openFastIsRegoaled() throws {
        let (store, context) = makeStore()
        let fast = insert(Fast(start: Date().addingTimeInterval(-4 * 3600), goalHours: 16,
                               protocolID: FastingProtocol.p168.rawValue), into: context)

        try store.applyProtocol(.p204, to: fast)

        #expect(fast.goalHours == 20)
        #expect(fast.protocolID == FastingProtocol.p204.rawValue)
        #expect(fast.isOpen, "re-goaling must not close the fast")
    }

    @Test("Fasts other than the one passed in are untouched")
    func historyIsNotRewritten() throws {
        let (store, context) = makeStore()
        let old = insert(Fast(start: Date().addingTimeInterval(-40 * 3600),
                              end: Date().addingTimeInterval(-24 * 3600),
                              goalHours: 16, protocolID: FastingProtocol.p168.rawValue), into: context)
        let open = insert(Fast(start: Date().addingTimeInterval(-2 * 3600), goalHours: 16,
                               protocolID: FastingProtocol.p168.rawValue), into: context)

        try store.applyProtocol(.p1410, to: open)

        #expect(open.goalHours == 14)
        #expect(old.goalHours == 16, "a completed fast keeps the goal it was judged against")
        #expect(old.protocolID == FastingProtocol.p168.rawValue)
    }

    /// Switching *down* mid-fast can put the goal behind you. That's allowed —
    /// the fast is legal whatever its goal, and the goal notification simply
    /// finds a fire date in the past and arms nothing.
    @Test("A goal the fast has already passed is accepted")
    func shorterGoalAlreadyBehindTheFast() throws {
        let (store, context) = makeStore()
        let start = Date().addingTimeInterval(-17 * 3600)
        let fast = insert(Fast(start: start, goalHours: 20,
                               protocolID: FastingProtocol.p204.rawValue), into: context)

        try store.applyProtocol(.p1410, to: fast)

        #expect(fast.goalHours == 14)
        #expect(fast.record.goalReachedAt < Date())
        // Still open, so isGoalMet stays false until it's actually ended —
        // completion is a property of a *closed* fast (§2).
        #expect(fast.record.isGoalMet == false)
    }

    @Test("Ending after a re-goal is judged against the new goal")
    func endedFastIsJudgedAgainstTheNewGoal() throws {
        let (store, context) = makeStore()
        let fast = insert(Fast(start: Date().addingTimeInterval(-15 * 3600), goalHours: 16,
                               protocolID: FastingProtocol.p168.rawValue), into: context)

        // 15h in: short of 16:8, comfortably past 14:10.
        #expect(fast.record.duration(asOf: Date()) < fast.record.goalInterval)
        try store.applyProtocol(.p1410, to: fast)
        let result = try store.endFast()

        #expect(result.goalMet, "the goal in force when it ended is the one that counts")
    }
}
