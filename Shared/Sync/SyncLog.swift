//
//  SyncLog.swift
//  Fastino
//
//  A record of what CloudKit mirroring actually did (§3), because until now
//  nothing kept one.
//
//  Sync between the phone and the watch is a headline promise of the app, and
//  when it appears not to work there is no way to tell the three very different
//  causes apart: the export never left the writing device, the import never
//  reached the reading one, or the import arrived twenty seconds after the user
//  stopped looking. `CloudSyncStatus` collapses all of that into one traffic
//  light, and `RemoteChangeRefresher` acts on imports and forgets them. This
//  keeps the timestamps.
//
//  Two design points worth not undoing:
//
//  **One observer, three consumers.** `CloudSyncStatus` and
//  `RemoteChangeRefresher` used to register their own observers on
//  `NSPersistentCloudKitContainer.eventChangedNotification`, with subtly
//  different filters. They now both subscribe here instead, keeping their own
//  filters exactly as they were — the refresher still acts only on a completed,
//  successful `.import`. Adding a fourth consumer should mean another
//  `subscribe`, not another `NotificationCenter` registration.
//
//  **The wait window is not the launch.** A watch that has been in a pocket for
//  an hour knows exactly as little as one that has just launched, and the
//  failure users actually report is the backgrounded app, not the cold one. So
//  a window opens on launch *and* on a resume from a long enough background —
//  see `SyncTiming`, and `markForeground()`.
//
//  **In-flight events are recorded, not just finished ones.** An import that
//  began forty seconds ago and hasn't completed is the single most diagnostic
//  state there is, and it's invisible if you only log completions. Events are
//  keyed by `event.identifier` and updated in place when they finish, so an
//  event still appears once.
//
//  Persisted to the app group's `UserDefaults` — event metadata only, never
//  anything from a fast — so the record survives the app being killed, which on
//  the watch is most of the time. That is deliberately *not* the SwiftData
//  store: this is device-local diagnostics and has no business in CloudKit.
//

import CoreData
import Foundation
import OSLog

/// How long a launch is willing to wait to hear from another device before it
/// stops saying so. Shared by the log and by the watch screens that show the
/// waiting state, so the caption and the diagnostics can't disagree.
nonisolated enum SyncTiming {
    /// How long a **cold launch** waits. Mirroring has to set itself up before
    /// any data moves, and on watchOS that is unhurried.
    static let launchImportTimeout: TimeInterval = 15

    /// How long a **resume** waits.
    ///
    /// Measured, not guessed: a phone-started fast reached a backgrounded watch
    /// app on resume in ~30s, so this is that plus margin. It was 6s first, on
    /// the reasoning that a container which is already set up imports quickly.
    /// That reasoning was wrong, and the failure it produced was the worse kind
    /// — the watch said "Checking", gave up, claimed "Ready", and was
    /// contradicted twenty seconds later. **A wait that expires before the
    /// answer arrives is worse than no wait at all**, which is why the number
    /// errs long and why `isAwaitingImport` doesn't stop at it while an import
    /// is actually running.
    static let resumeImportTimeout: TimeInterval = 45

    /// How long the app has to have been away before a resume restarts the
    /// wait at all. Glancing away and back can't have made the state stale, and
    /// `scenePhase` reports `.inactive` for things as small as a notification
    /// banner.
    static let staleAfterBackground: TimeInterval = 30

    /// How long an import that has started but never reported a result is still
    /// believed to be running. A process suspended mid-import never posts its
    /// completion, and an unbounded "in flight" would leave the watch saying
    /// "Checking" for the rest of the launch.
    static let maxImportDuration: TimeInterval = 90

    /// The decision itself, pulled out as a pure function so it can be tested
    /// without a CloudKit container — the flag it depends on is global state
    /// that the test host has already decided by the time a test runs.
    static func isAwaitingImport(
        mirroringConfigured: Bool,
        windowStartedAt: Date,
        timeout: TimeInterval,
        importArrivedAt: Date?,
        importInFlight: Bool,
        now: Date
    ) -> Bool {
        // A device that never asked for mirroring has nothing to wait for, and
        // one that has already heard from another device is done waiting.
        guard mirroringConfigured, importArrivedAt == nil else { return false }
        if now.timeIntervalSince(windowStartedAt) < timeout { return true }
        // Past the timeout, keep waiting only on evidence: an import that is
        // genuinely running will finish, and giving up on it is what produces
        // the "Ready" that gets contradicted a moment later. The timeout is a
        // floor for the case where nothing ever starts, not a ceiling on a
        // slow import.
        return importInFlight
    }

    /// Whether the newest import is still running. Bounded by
    /// `maxImportDuration` so a completion that never arrives can't hang the
    /// wait forever.
    static func isImportInFlight(newestImport: SyncEvent?, now: Date) -> Bool {
        guard let newestImport, !newestImport.isFinished else { return false }
        return now.timeIntervalSince(newestImport.started) < maxImportDuration
    }

    /// Whether coming back from the background should restart the wait.
    static func resumeRestartsWait(backgroundedAt: Date?, now: Date) -> Bool {
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= staleAfterBackground
    }
}

// MARK: - The value types (pure)

nonisolated enum SyncEventKind: String, Codable, Sendable {
    /// Mirroring setting itself up — the phase that runs before any data moves.
    case setup
    /// Data arriving from another device.
    case importing
    /// Data leaving for another device.
    case exporting
    /// A write this device made itself. Not a CloudKit event: it's the anchor
    /// the export after it and the import on the other device are measured from.
    case localWrite
    /// The app coming back to the foreground. Also not a CloudKit event, and
    /// there for the same reason: the question "does an import follow a resume,
    /// or only a cold launch?" is unanswerable without a mark in the log for
    /// where the resume was.
    case appActive

    var displayName: String {
        switch self {
        case .setup: "Setup"
        case .importing: "Import"
        case .exporting: "Export"
        case .localWrite: "Local write"
        case .appActive: "App active"
        }
    }
}

nonisolated struct SyncEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: SyncEventKind
    /// Which device recorded it. Constant within one store, but the log is read
    /// side by side with the other device's, so it earns its bytes.
    var device: String
    var started: Date
    /// `nil` while the event is still in flight.
    var ended: Date?
    var succeeded: Bool
    /// The error text for a failure, or the name of the write for a local one.
    var detail: String?

    var isFinished: Bool { ended != nil }

    var duration: TimeInterval? {
        ended.map { $0.timeIntervalSince(started) }
    }

    /// "Import · 2.4s" / "Import · running" / "Import · failed"
    var summary: String {
        guard let duration else { return "\(kind.displayName) · running" }
        let outcome = succeeded ? String(format: "%.1fs", duration) : "failed"
        return "\(kind.displayName) · \(outcome)"
    }

    static var deviceName: String {
        #if os(watchOS)
        "Watch"
        #else
        "iPhone"
        #endif
    }
}

/// The ring buffer, split out from `SyncLog` so the part with all the ordering
/// rules in it is a pure value type with unit tests (`SyncLogTests`).
nonisolated struct SyncEventBuffer: Codable, Equatable, Sendable {
    /// Enough to cover a launch and the launch before it; small enough to sit
    /// in `UserDefaults` without a thought.
    static let capacity = 50

    /// Newest first, which is the order both diagnostics screens read in.
    private(set) var events: [SyncEvent] = []

    init(events: [SyncEvent] = []) {
        self.events = events
        trim()
    }

    /// Insert, or update in place when the same event is seen again — CloudKit
    /// posts an event twice, once starting and once finished, and those are one
    /// thing that happened, not two.
    mutating func upsert(_ event: SyncEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.insert(event, at: 0)
        }
        trim()
    }

    func mostRecent(_ kind: SyncEventKind, succeededOnly: Bool = true) -> SyncEvent? {
        events.first {
            $0.kind == kind && $0.isFinished && (!succeededOnly || $0.succeeded)
        }
    }

    private mutating func trim() {
        if events.count > Self.capacity {
            events.removeLast(events.count - Self.capacity)
        }
    }
}

// MARK: - The log

@MainActor
@Observable
final class SyncLog {
    static let shared = SyncLog()

    private(set) var buffer = SyncEventBuffer()

    /// The start of the current *wait window* — the period during which this
    /// device might still be about to hear from another one.
    ///
    /// A window opens on launch, and again on a resume from a long enough
    /// background. It is deliberately **not** just the launch time: the
    /// screen's whole job is to stop claiming "Ready" before the answer is in,
    /// and a watch that has been in someone's pocket for an hour is exactly as
    /// uninformed as one that has just launched. Views observe this and restart
    /// their own timers from it.
    private(set) var awaitWindowStartedAt = Date()

    /// The timeout for the window currently open — see `SyncTiming`.
    private(set) var awaitWindowTimeout = SyncTiming.launchImportTimeout

    /// The first import to complete inside the current window. Deliberately not
    /// restored from disk: the question it answers is about *now*.
    private(set) var importArrivedInWindow: Date?

    /// When the app last went away, so a resume can tell a glance from an hour.
    private var backgroundedAt: Date?

    /// Seconds from the window opening to the import that closed it — the one
    /// number that says whether sync is broken or merely slower than the user's
    /// patience.
    var secondsToFirstImport: TimeInterval? {
        importArrivedInWindow.map { $0.timeIntervalSince(awaitWindowStartedAt) }
    }

    var lastSuccessfulImport: SyncEvent? { buffer.mostRecent(.importing) }
    var lastSuccessfulExport: SyncEvent? { buffer.mostRecent(.exporting) }
    var lastLocalWrite: SyncEvent? { buffer.mostRecent(.localWrite) }

    /// True while this device could still be waiting to hear from another one —
    /// no import has landed in this window and its timeout hasn't run out.
    ///
    /// `isCloudKitConfigured` gates it because a device that never asked for
    /// mirroring has nothing to wait for; that also keeps previews and tests,
    /// which never touch `AppContainer.shared`, out of the waiting state.
    func isAwaitingImport(now: Date = Date()) -> Bool {
        SyncTiming.isAwaitingImport(
            mirroringConfigured: AppContainer.isCloudKitConfigured,
            windowStartedAt: awaitWindowStartedAt,
            timeout: awaitWindowTimeout,
            importArrivedAt: importArrivedInWindow,
            importInFlight: isImportInFlight(now: now),
            now: now
        )
    }

    /// Whether an import is running right now. This is what in-flight events
    /// were recorded for: it's the difference between "slow" and "never".
    func isImportInFlight(now: Date = Date()) -> Bool {
        SyncTiming.isImportInFlight(
            newestImport: buffer.events.first { $0.kind == .importing },
            now: now
        )
    }

    /// The app went away. Only the *first* call counts, because `scenePhase`
    /// passes through `.inactive` on the way back in as well as on the way out,
    /// and taking the later timestamp would make every resume look instant.
    func markBackground() {
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    /// The app came back. Marks the log, and reopens the wait window if it was
    /// away long enough for the other device to have changed something.
    func markForeground() {
        let now = Date()
        let restarts = SyncTiming.resumeRestartsWait(backgroundedAt: backgroundedAt, now: now)
        record(SyncEvent(
            id: UUID(),
            kind: .appActive,
            device: SyncEvent.deviceName,
            started: now,
            ended: now,
            succeeded: true,
            detail: restarts ? "waiting for an import" : "resumed"
        ))
        backgroundedAt = nil
        guard restarts else { return }
        openAwaitWindow(timeout: SyncTiming.resumeImportTimeout)
    }

    private func openAwaitWindow(timeout: TimeInterval) {
        awaitWindowStartedAt = Date()
        awaitWindowTimeout = timeout
        importArrivedInWindow = nil
    }

    private var observer: (any NSObjectProtocol)?
    private var subscribers: [(SyncEvent) -> Void] = []
    private let defaults: UserDefaults?
    private let log = Logger(subsystem: "com.baleware.fastino", category: "CloudSync")

    private static let storageKey = "sync.eventLog.v1"

    /// `defaults` is injectable so a test can drive the log without touching the
    /// real app group.
    init(defaults: UserDefaults? = UserDefaults(suiteName: AppContainer.appGroupID)) {
        self.defaults = defaults
        buffer = Self.load(from: defaults) ?? SyncEventBuffer()
    }

    /// Begin observing CloudKit mirroring. Idempotent, and safe to call from
    /// every consumer rather than only from the app entry point.
    func start() {
        guard observer == nil else { return }
        openAwaitWindow(timeout: SyncTiming.launchImportTimeout)

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event else { return }
            let value = SyncEvent(
                id: event.identifier,
                kind: Self.kind(of: event.type),
                device: SyncEvent.deviceName,
                started: event.startDate,
                ended: event.endDate,
                succeeded: event.succeeded,
                detail: event.error?.localizedDescription
            )
            Task { @MainActor [weak self] in
                self?.record(value)
            }
        }
    }

    /// Subscribe to every event, in flight or finished. Consumers do their own
    /// filtering — the two that exist want different things.
    func subscribe(_ handler: @escaping (SyncEvent) -> Void) {
        subscribers.append(handler)
    }

    /// Note a write this device made, so the export that follows it and the
    /// import on the other device can be measured against something.
    func recordLocalWrite(_ label: String) {
        let now = Date()
        record(SyncEvent(
            id: UUID(),
            kind: .localWrite,
            device: SyncEvent.deviceName,
            started: now,
            ended: now,
            succeeded: true,
            detail: label
        ))
    }

    private func record(_ event: SyncEvent) {
        buffer.upsert(event)
        persist()

        if event.kind == .importing, event.isFinished, event.succeeded, importArrivedInWindow == nil {
            importArrivedInWindow = event.ended
        }

        if event.isFinished {
            if event.succeeded {
                log.info("\(event.kind.displayName, privacy: .public) finished in \(event.duration ?? 0, format: .fixed(precision: 2))s")
            } else {
                log.error("\(event.kind.displayName, privacy: .public) failed: \(event.detail ?? "unknown error", privacy: .public)")
            }
        } else {
            log.info("\(event.kind.displayName, privacy: .public) started")
        }

        for handler in subscribers { handler(event) }
    }

    /// Wipe the record. Only reachable from the diagnostics screens, which are
    /// DEBUG-only — the point is to start a measurement from a clean slate.
    func clear() {
        buffer = SyncEventBuffer()
        openAwaitWindow(timeout: awaitWindowTimeout)
        persist()
    }

    // MARK: Persistence

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(buffer) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults?) -> SyncEventBuffer? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(SyncEventBuffer.self, from: data)
    }

    private static func kind(of type: NSPersistentCloudKitContainer.EventType) -> SyncEventKind {
        switch type {
        case .setup: .setup
        case .import: .importing
        case .export: .exporting
        @unknown default: .setup
        }
    }
}
