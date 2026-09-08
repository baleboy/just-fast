//
//  CompanionRelayTests.swift
//  FastinoTests
//
//  The pure half of the watch → phone notification relay (§4.4): the wire
//  format and the staleness rule. WatchConnectivity itself is untestable and
//  deliberately not faked — the transport is a handful of guards, and a mock
//  session that always delivers would prove nothing about a phone in a pocket.
//

import Foundation
import Testing
@testable import Fastino

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("Companion relay payload")
struct CompanionRelayPayloadTests {

    @Test("An open fast survives the round trip intact")
    func openFastRoundTrips() throws {
        let fast = FastRecord(start: t0, end: nil, goalHours: 16)
        let sent = CompanionRelayPayload(openFast: fast, sentAt: t0)

        let received = try #require(CompanionRelayPayload(userInfo: sent.userInfo))
        #expect(received == sent)
        #expect(received.openFast?.id == fast.id)
        #expect(received.openFast?.goalReachedAt == fast.goalReachedAt)
    }

    @Test("No open fast round trips as no open fast")
    func absenceRoundTrips() throws {
        let sent = CompanionRelayPayload(openFast: nil, sentAt: t0)
        let received = try #require(CompanionRelayPayload(userInfo: sent.userInfo))
        #expect(received.openFast == nil)
        #expect(received.sentAt == t0)
    }

    @Test("The wire format is property-list types only, as transferUserInfo demands")
    func wireFormatIsPropertyList() {
        let payload = CompanionRelayPayload(openFast: FastRecord(start: t0, end: nil, goalHours: 18))
        #expect(PropertyListSerialization.propertyList(payload.userInfo, isValidFor: .binary))
    }

    @Test("Someone else's userInfo is not ours to act on")
    func foreignPayloadIsRejected() {
        #expect(CompanionRelayPayload(userInfo: [:]) == nil)
        #expect(CompanionRelayPayload(userInfo: ["sentAt": t0]) == nil)
    }

    /// A half-described fast is read as "no fast running", never as a fast with
    /// a guessed goal — the phone would arm a goal alert at the wrong hour.
    @Test("A payload missing part of the fast reads as no fast")
    func partialFastIsNoFast() throws {
        var info = CompanionRelayPayload(openFast: FastRecord(start: t0, end: nil, goalHours: 16)).userInfo
        info["goalHours"] = nil

        let received = try #require(CompanionRelayPayload(userInfo: info))
        #expect(received.openFast == nil)
    }

    @Test("Only a payload newer than the last one applied is acted on")
    func staleDeliveriesAreDropped() {
        let older = CompanionRelayPayload(openFast: nil, sentAt: t0)
        let newer = CompanionRelayPayload(openFast: nil, sentAt: t0.addingTimeInterval(60))

        #expect(CompanionRelayPayload.isFresh(older, lastApplied: nil))
        #expect(CompanionRelayPayload.isFresh(newer, lastApplied: t0))
        #expect(!CompanionRelayPayload.isFresh(older, lastApplied: newer.sentAt))
        // The same state announced twice is nothing to re-arm for.
        #expect(!CompanionRelayPayload.isFresh(older, lastApplied: t0))
    }
}
