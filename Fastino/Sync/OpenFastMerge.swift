//
//  OpenFastMerge.swift
//  Fastino
//
//  Resolving the one conflict CloudKit sync can actually produce (§6): two
//  devices each start a fast while offline, so after the merge there are two
//  open fasts and the app's core invariant — at most one — is broken.
//
//  §6 specifies "last-writer-wins on the single open fast, with overlap
//  validation on merge (later start wins, other record closed at that instant)".
//
//  Kept pure and free of SwiftData so the rule is unit-testable without a
//  container or a device — this is the logic most able to lose a user's data,
//  so it should be the easiest thing here to test. `SyncReconciler` applies the
//  plan; this file only decides.
//

import Foundation

nonisolated enum OpenFastMerge {
    enum Action: Equatable, Sendable {
        /// Close a losing fast at the winner's start instant.
        case close(id: UUID, at: Date)
        /// Drop a losing fast that can't be closed into a valid record.
        case delete(id: UUID)
    }

    /// The plan that restores "at most one open fast".
    ///
    /// The winner is the latest `start`, ties broken by the lowest `id` string.
    /// Both rules read only replicated data, so every device computes the same
    /// winner and the merge converges instead of devices undoing each other.
    static func plan(for records: [FastRecord]) -> [Action] {
        let open = records.filter(\.isOpen)
        guard open.count > 1 else { return [] }

        guard let winner = open.max(by: { a, b in
            a.start == b.start ? a.id.uuidString > b.id.uuidString : a.start < b.start
        }) else { return [] }

        return open.filter { $0.id != winner.id }.map { loser in
            // Identical starts: closing at the winner's start would give
            // end == start, which FastValidation rejects — so there is no valid
            // record to keep and the duplicate is dropped. Without this the
            // reconciler would throw on every pass, forever.
            guard loser.start < winner.start else { return .delete(id: loser.id) }

            // A fast abandoned long before the winner would otherwise be closed
            // into a record longer than FastValidation's 7-day cap — i.e. one
            // the app itself considers invalid and won't let the user edit.
            // Clamp rather than fabricate a duration past the cap.
            let cap = loser.start.addingTimeInterval(FastValidation.maxDuration)
            return .close(id: loser.id, at: min(winner.start, cap))
        }
    }
}
