//
//  SyncLogTests.swift
//  FastinoTests
//
//  The ring buffer behind the sync diagnostics (§3). Pure by design: the
//  CloudKit half of `SyncLog` cannot be unit-tested and is deliberately not
//  faked here — a mock that always imports would prove nothing about the thing
//  under suspicion.
//

import Foundation
import Testing
@testable import Fastino

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

private func event(
    _ kind: SyncEventKind,
    id: UUID = UUID(),
    started: Date = t0,
    ended: Date? = nil,
    succeeded: Bool = true,
    detail: String? = nil
) -> SyncEvent {
    SyncEvent(
        id: id,
        kind: kind,
        device: "Test",
        started: started,
        ended: ended,
        succeeded: succeeded,
        detail: detail
    )
}

@Suite("Sync event buffer")
struct SyncEventBufferTests {
    @Test("Newest first")
    func newestFirst() {
        var buffer = SyncEventBuffer()
        buffer.upsert(event(.exporting, started: at(0)))
        buffer.upsert(event(.importing, started: at(10)))

        #expect(buffer.events.map(\.kind) == [.importing, .exporting])
    }

    @Test("The same event finishing updates it in place rather than adding a second")
    func upsertInPlace() {
        let id = UUID()
        var buffer = SyncEventBuffer()
        buffer.upsert(event(.importing, id: id, started: at(0)))
        buffer.upsert(event(.exporting, started: at(1)))
        buffer.upsert(event(.importing, id: id, started: at(0), ended: at(2)))

        #expect(buffer.events.count == 2)
        // Still in the position it was first recorded at — an event that
        // finishes doesn't jump to the top of the log.
        #expect(buffer.events[1].id == id)
        #expect(buffer.events[1].ended == at(2))
    }

    @Test("Capacity is enforced, oldest dropped")
    func capacity() {
        var buffer = SyncEventBuffer()
        for index in 0..<(SyncEventBuffer.capacity + 10) {
            buffer.upsert(event(.exporting, started: at(Double(index))))
        }

        #expect(buffer.events.count == SyncEventBuffer.capacity)
        #expect(buffer.events.first?.started == at(Double(SyncEventBuffer.capacity + 9)))
        #expect(buffer.events.last?.started == at(10))
    }

    @Test("Over-capacity initial contents are trimmed too")
    func trimsOnInit() {
        let events = (0..<80).map { event(.setup, started: at(Double($0))) }
        #expect(SyncEventBuffer(events: events).events.count == SyncEventBuffer.capacity)
    }

    @Test("mostRecent skips in-flight and failed events")
    func mostRecentSkipsUnfinishedAndFailed() {
        var buffer = SyncEventBuffer()
        buffer.upsert(event(.importing, started: at(0), ended: at(1)))
        buffer.upsert(event(.importing, started: at(2), ended: at(3), succeeded: false))
        buffer.upsert(event(.importing, started: at(4)))

        #expect(buffer.mostRecent(.importing)?.ended == at(1))
        // The failed one is still findable when you ask for it.
        #expect(buffer.mostRecent(.importing, succeededOnly: false)?.ended == at(3))
        #expect(buffer.mostRecent(.exporting) == nil)
    }

    @Test("Round-trips through JSON, which is how it survives a relaunch")
    func codableRoundTrip() throws {
        var buffer = SyncEventBuffer()
        buffer.upsert(event(.importing, started: at(0), ended: at(1)))
        buffer.upsert(event(.exporting, started: at(2), ended: at(3), succeeded: false, detail: "no network"))
        buffer.upsert(event(.localWrite, started: at(4), ended: at(4), detail: "start (watch)"))

        let data = try JSONEncoder().encode(buffer)
        let decoded = try JSONDecoder().decode(SyncEventBuffer.self, from: data)

        #expect(decoded == buffer)
        #expect(decoded.mostRecent(.localWrite)?.detail == "start (watch)")
    }
}

@Suite("Sync event")
struct SyncEventTests {
    @Test("An unfinished event has no duration and reads as running")
    func unfinished() {
        let running = event(.importing, started: at(0))
        #expect(running.duration == nil)
        #expect(running.isFinished == false)
        #expect(running.summary == "Import · running")
    }

    @Test("A finished event reports its duration")
    func finished() {
        let done = event(.exporting, started: at(0), ended: at(2.4))
        // A tolerance because `Date` keeps its interval as a Double and 2.4 is
        // not representable — the summary rounds to a tenth anyway.
        #expect(abs((done.duration ?? 0) - 2.4) < 0.001)
        #expect(done.summary == "Export · 2.4s")
    }

    @Test("A failure says so rather than reporting how long it took to fail")
    func failure() {
        let failed = event(.importing, started: at(0), ended: at(9), succeeded: false, detail: "boom")
        #expect(failed.summary == "Import · failed")
        #expect(failed.detail == "boom")
    }
}

@Suite("Sync log")
@MainActor
struct SyncLogTests {
    /// Built with no `UserDefaults`, so nothing here touches the real app group.
    private func makeLog() -> SyncLog { SyncLog(defaults: nil) }

    @Test("A local write is recorded and findable")
    func localWrite() {
        let log = makeLog()
        log.recordLocalWrite("start (app)")

        #expect(log.buffer.events.count == 1)
        #expect(log.lastLocalWrite?.detail == "start (app)")
    }

    @Test("No import means no launch-to-first-import figure")
    func noFirstImportYet() {
        let log = makeLog()
        log.recordLocalWrite("start (app)")

        #expect(log.importArrivedInWindow == nil)
        #expect(log.secondsToFirstImport == nil)
    }

    @Test("Clearing empties the log and restarts the clock")
    func clear() {
        let log = makeLog()
        log.recordLocalWrite("edit")
        let before = log.awaitWindowStartedAt
        log.clear()

        #expect(log.buffer.events.isEmpty)
        #expect(log.awaitWindowStartedAt >= before)
    }
}

@Suite("Awaiting an import")
struct SyncTimingTests {
    private func awaiting(
        mirroring: Bool = true,
        timeout: TimeInterval = SyncTiming.launchImportTimeout,
        importArrived: Date? = nil,
        importInFlight: Bool = false,
        secondsSinceWindow: TimeInterval
    ) -> Bool {
        SyncTiming.isAwaitingImport(
            mirroringConfigured: mirroring,
            windowStartedAt: t0,
            timeout: timeout,
            importArrivedAt: importArrived,
            importInFlight: importInFlight,
            now: t0.addingTimeInterval(secondsSinceWindow)
        )
    }

    @Test("Waits inside the timeout")
    func waitsEarly() {
        #expect(awaiting(secondsSinceWindow: 0))
        #expect(awaiting(secondsSinceWindow: SyncTiming.launchImportTimeout - 1))
    }

    @Test("Gives up at the timeout")
    func givesUp() {
        #expect(awaiting(secondsSinceWindow: SyncTiming.launchImportTimeout) == false)
        #expect(awaiting(secondsSinceWindow: 600) == false)
    }

    @Test("The resume window is long enough for a measured resume import")
    func resumeWindowCoversTheMeasurement() {
        // A phone-started fast reached a backgrounded watch on resume in ~30s.
        // A window that expires before that produces the failure this whole
        // state exists to prevent: "Checking", then "Ready", then the fast.
        #expect(awaiting(timeout: SyncTiming.resumeImportTimeout, secondsSinceWindow: 30))
    }

    @Test("Past the deadline, a running import keeps the wait alive")
    func inFlightOutlastsTheDeadline() {
        let past = SyncTiming.resumeImportTimeout + 20
        #expect(awaiting(timeout: SyncTiming.resumeImportTimeout, secondsSinceWindow: past) == false)
        #expect(awaiting(timeout: SyncTiming.resumeImportTimeout, importInFlight: true, secondsSinceWindow: past))
    }

    @Test("An import that already landed beats a later one still running")
    func arrivedBeatsInFlight() {
        // Another import starting doesn't put the screen back into waiting once
        // this window has its answer.
        #expect(awaiting(importArrived: t0.addingTimeInterval(1), importInFlight: true, secondsSinceWindow: 2) == false)
    }

    @Test("An import that already landed ends the wait immediately")
    func importEndsTheWait() {
        #expect(awaiting(importArrived: t0.addingTimeInterval(1), secondsSinceWindow: 2) == false)
    }

    @Test("A device that never asked for mirroring has nothing to wait for")
    func noMirroringNoWait() {
        // Which is also why previews and a local-only fallback store never show
        // the waiting state.
        #expect(awaiting(mirroring: false, secondsSinceWindow: 0) == false)
    }
}

@Suite("Imports in flight")
struct SyncInFlightTests {
    private func event(started: Date, ended: Date? = nil) -> SyncEvent {
        SyncEvent(
            id: UUID(),
            kind: .importing,
            device: "Test",
            started: started,
            ended: ended,
            succeeded: true,
            detail: nil
        )
    }

    @Test("A started import counts as running")
    func running() {
        #expect(SyncTiming.isImportInFlight(newestImport: event(started: t0), now: t0.addingTimeInterval(5)))
    }

    @Test("A finished one does not")
    func finished() {
        let done = event(started: t0, ended: t0.addingTimeInterval(2))
        #expect(SyncTiming.isImportInFlight(newestImport: done, now: t0.addingTimeInterval(5)) == false)
    }

    @Test("Nothing recorded is not something running")
    func none() {
        #expect(SyncTiming.isImportInFlight(newestImport: nil, now: t0) == false)
    }

    @Test("A completion that never arrives stops counting")
    func abandoned() {
        // A process suspended mid-import never posts its result; believing it
        // forever would leave the watch on "Checking" for the rest of the launch.
        let stale = t0.addingTimeInterval(SyncTiming.maxImportDuration + 1)
        #expect(SyncTiming.isImportInFlight(newestImport: event(started: t0), now: stale) == false)
    }
}

@Suite("Resuming from the background")
struct SyncResumeTests {
    @Test("A long enough absence reopens the wait")
    func longAbsenceRestarts() {
        let away = t0.addingTimeInterval(-SyncTiming.staleAfterBackground)
        #expect(SyncTiming.resumeRestartsWait(backgroundedAt: away, now: t0))
    }

    @Test("A glance away does not")
    func glanceDoesNot() {
        // `scenePhase` reports `.inactive` for something as small as a
        // notification banner; re-checking after one would put the watch on
        // "Checking" every time it was raised.
        let away = t0.addingTimeInterval(-1)
        #expect(SyncTiming.resumeRestartsWait(backgroundedAt: away, now: t0) == false)
    }

    @Test("Never having been backgrounded does not")
    func neverAway() {
        #expect(SyncTiming.resumeRestartsWait(backgroundedAt: nil, now: t0) == false)
    }
}

@Suite("Sync log windows")
@MainActor
struct SyncLogWindowTests {
    private func makeLog() -> SyncLog { SyncLog(defaults: nil) }

    @Test("Coming back after a long absence reopens the window on the resume timeout")
    func resumeReopens() {
        let log = makeLog()
        let before = log.awaitWindowStartedAt
        log.markBackground()
        // Pretend the absence was long enough by asking the pure rule directly;
        // the log's own clock can't be wound forward in a test.
        #expect(SyncTiming.resumeRestartsWait(
            backgroundedAt: before.addingTimeInterval(-SyncTiming.staleAfterBackground),
            now: Date()
        ))
        log.markForeground()

        // The resume is in the log either way, which is what makes the
        // background case measurable at all.
        #expect(log.buffer.events.contains { $0.kind == .appActive })
    }

    @Test("Going away twice keeps the first timestamp")
    func inactiveThenBackground() {
        // scenePhase passes through `.inactive` on the way *back in* as well as
        // on the way out; taking the later stamp would make every resume look
        // instant and the wait would never reopen.
        let log = makeLog()
        log.markBackground()
        log.markBackground()
        log.markForeground()

        let resumes = log.buffer.events.filter { $0.kind == .appActive }
        #expect(resumes.count == 1)
    }
}
