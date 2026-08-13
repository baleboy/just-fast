//
//  SyncMergeTests.swift
//  FastinoTests
//
//  The two rules CloudKit sync introduces (§6): collapsing duplicate open fasts
//  and electing a single AppSettings row. Both are pure functions precisely so
//  they can be tested here — no container, no iCloud account, no device.
//

import Foundation
import Testing
@testable import Fastino

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

private func open(_ start: Date, id: UUID = UUID()) -> FastRecord {
    FastRecord(id: id, start: start, end: nil, goalHours: 16)
}

private func closed(_ start: Date, _ end: Date, id: UUID = UUID()) -> FastRecord {
    FastRecord(id: id, start: start, end: end, goalHours: 16)
}

@Suite("Open-fast merge")
struct OpenFastMergeTests {

    @Test func noOpenFastsIsANoOp() {
        #expect(OpenFastMerge.plan(for: [closed(at(0), at(16))]).isEmpty)
    }

    @Test func singleOpenFastIsANoOp() {
        #expect(OpenFastMerge.plan(for: [open(at(0)), closed(at(-40), at(-24))]).isEmpty)
    }

    @Test func laterStartWinsAndTheOtherClosesAtThatInstant() {
        let loser = UUID()
        let winner = UUID()
        let plan = OpenFastMerge.plan(for: [
            open(at(0), id: loser),
            open(at(3), id: winner),
        ])
        #expect(plan == [.close(id: loser, at: at(3))])
    }

    @Test func winnerIsIndependentOfInputOrder() {
        let a = open(at(0))
        let b = open(at(3))
        #expect(OpenFastMerge.plan(for: [a, b]) == OpenFastMerge.plan(for: [b, a]))
    }

    @Test func threeOpenFastsAllCloseAtTheWinnersStart() {
        let plan = OpenFastMerge.plan(for: [open(at(0)), open(at(1)), open(at(5))])
        #expect(plan.count == 2)
        #expect(plan.allSatisfy { action in
            if case .close(_, let date) = action { return date == at(5) }
            return false
        })
    }

    /// Closing at the winner's start would give end == start, which
    /// FastValidation rejects — so the duplicate is dropped instead.
    @Test func identicalStartsDropTheLoserRatherThanMakeAnInvalidRecord() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        let plan = OpenFastMerge.plan(for: [open(at(2), id: low), open(at(2), id: high)])
        // Ties break on the lowest id string, so `low` survives.
        #expect(plan == [.delete(id: high)])
    }

    /// A fast abandoned long before the winner must not be closed into a record
    /// longer than FastValidation's 7-day cap.
    @Test func abandonedFastIsClampedToTheMaximumDuration() {
        let stale = UUID()
        let plan = OpenFastMerge.plan(for: [
            open(at(0), id: stale),
            open(at(24 * 30), id: UUID()),
        ])
        #expect(plan == [.close(id: stale, at: at(0).addingTimeInterval(FastValidation.maxDuration))])
    }

    @Test func resultingStateIsValidAndTheMergeIsIdempotent() throws {
        let loser = UUID()
        let winner = UUID()
        let records = [open(at(0), id: loser), open(at(3), id: winner)]

        let merged = records.map { record -> FastRecord in
            guard record.id == loser else { return record }
            return closed(record.start, at(3), id: loser)
        }

        // Touching endpoints are legal, so the merged pair passes validation...
        for record in merged {
            try FastValidation.validate(
                start: record.start,
                end: record.end,
                excludingID: record.id,
                against: merged
            )
        }
        // ...and running the plan again finds nothing left to do.
        #expect(OpenFastMerge.plan(for: merged).isEmpty)
    }
}

@Suite("Settings election")
struct SettingsElectionTests {

    private func identity(_ updatedAt: Date, _ id: UUID = UUID()) -> SettingsIdentity {
        SettingsIdentity(id: id, updatedAt: updatedAt)
    }

    @Test func noCandidatesElectsNobody() {
        #expect(SettingsElection.survivor(among: []) == nil)
    }

    @Test func singleCandidateWins() {
        let only = identity(at(0))
        #expect(SettingsElection.survivor(among: [only]) == only)
    }

    @Test func mostRecentlyUpdatedWins() {
        let old = identity(at(0))
        let new = identity(at(5))
        #expect(SettingsElection.survivor(among: [old, new]) == new)
        #expect(SettingsElection.survivor(among: [new, old]) == new)
    }

    /// The property that makes the dedupe converge: same data in, same survivor
    /// out, on every device regardless of fetch order.
    @Test func tiesBreakDeterministicallyOnTheLowestID() {
        let low = identity(at(1), UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = identity(at(1), UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!)
        #expect(SettingsElection.survivor(among: [low, high]) == low)
        #expect(SettingsElection.survivor(among: [high, low]) == low)
    }

    @Test func electionIsStableAcrossShuffles() {
        let candidates = (0..<8).map { identity(at(Double($0 % 3))) }
        let winner = SettingsElection.survivor(among: candidates)
        for _ in 0..<20 {
            #expect(SettingsElection.survivor(among: candidates.shuffled()) == winner)
        }
    }
}
