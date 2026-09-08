//
//  CompanionRelay.swift
//  Fastino
//
//  The one fact the watch tells the phone directly, instead of through iCloud
//  (§4.4, §4.7): whether a fast is running.
//
//  Everything else the two apps share travels through CloudKit, deliberately —
//  see `CompanionProbe`. This is the exception, and it exists because
//  cancelling a notification is not something CloudKit can carry.
//
//  The start reminder is a repeating calendar trigger armed on the *phone*, and
//  `removePendingNotificationRequests` is device-local: only the phone can
//  cancel it. Start a fast on the watch with the phone suspended in a pocket and
//  the phone runs no code at all, so at the anchor it fires a reminder to start
//  a fast that has been running for a quarter of an hour. The mirroring push
//  that would have told it is best-effort and budget-throttled by iOS; the
//  reported failure is exactly the case where it doesn't arrive in time.
//
//  `transferUserInfo` does wake a suspended counterpart app in the background,
//  which is why the fact travels this way. What crosses is *scheduling state*,
//  not the record of truth — the fast itself still arrives as a CloudKit
//  import, and the phone re-derives everything from its own store the moment
//  one lands. Nothing here is persisted, and nothing reads it back.
//
//  One direction only. The watch schedules nothing while a phone app exists
//  (`NotificationOwnership`), so the phone has nothing to tell it.
//

import Foundation

/// The scheduling-relevant state of the sending device: the open fast, or its
/// absence. A value type with no transport in it, so the encoding is unit-tested
/// without WatchConnectivity, which is untestable.
nonisolated struct CompanionRelayPayload: Equatable, Sendable {
    /// The fast running when this was sent, or `nil` for "none is".
    let openFast: FastRecord?
    /// When the sending device believed it. Used to drop a queued transfer that
    /// arrives after a fresher one — deliveries are ordered, but a payload can
    /// still land after CloudKit has already told the phone something newer.
    let sentAt: Date

    init(openFast: FastRecord?, sentAt: Date = Date()) {
        self.openFast = openFast
        self.sentAt = sentAt
    }

    // MARK: Wire format

    private enum Key {
        static let marker = "fastino.relay"
        static let sentAt = "sentAt"
        static let fastID = "fastID"
        static let start = "start"
        static let goalHours = "goalHours"
    }

    /// A property-list dictionary, which is all `transferUserInfo` accepts —
    /// hence the `UUID` going across as a string.
    var userInfo: [String: Any] {
        var info: [String: Any] = [Key.marker: true, Key.sentAt: sentAt]
        if let openFast {
            info[Key.fastID] = openFast.id.uuidString
            info[Key.start] = openFast.start
            info[Key.goalHours] = openFast.goalHours
        }
        return info
    }

    /// `nil` for anything that isn't one of ours, or is missing a piece — an
    /// open fast is all three of id, start and goal or it is not a fast.
    init?(userInfo: [String: Any]) {
        guard userInfo[Key.marker] as? Bool == true,
              let sentAt = userInfo[Key.sentAt] as? Date
        else { return nil }

        if let idString = userInfo[Key.fastID] as? String,
           let id = UUID(uuidString: idString),
           let start = userInfo[Key.start] as? Date,
           let goalHours = userInfo[Key.goalHours] as? Int {
            self.openFast = FastRecord(id: id, start: start, end: nil, goalHours: goalHours)
        } else {
            self.openFast = nil
        }
        self.sentAt = sentAt
    }

    /// Whether a payload that just arrived says anything the receiver hasn't
    /// already been told. Equal timestamps count as stale: the same state sent
    /// twice is nothing to act on.
    static func isFresh(_ incoming: CompanionRelayPayload, lastApplied: Date?) -> Bool {
        guard let lastApplied else { return true }
        return incoming.sentAt > lastApplied
    }
}

/// The seam `FastStore` announces through.
///
/// Lives in `Shared/` because `FastStore` does, but the transport doesn't:
/// WatchConnectivity is linked only by the two app targets, never by the widget
/// extensions, which compile this file too. Unset — on iOS, and in every
/// extension — announcing is a no-op.
@MainActor
enum CompanionRelay {
    static var transport: (@MainActor (CompanionRelayPayload) -> Void)?

    static func announce(openFast: FastRecord?) {
        transport?(CompanionRelayPayload(openFast: openFast))
    }
}
