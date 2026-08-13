//
//  SyncReconciler.swift
//  Fastino
//
//  Applies `OpenFastMerge`'s plan to the store after CloudKit hands us a second
//  open fast (§6).
//
//  When it runs: SwiftData exposes no public "remote change arrived" callback,
//  so @Query is the hook — it republishes when mirrored changes merge into the
//  main context, so observing the open-fast count observes exactly the condition
//  we care about, using only supported API. FastinoApp's existing
//  scenePhase == .active pass catches changes that merged while suspended.
//
//  Why the debounce: CloudKit delivers in batches, and the ordering within a
//  batch is not guaranteed. A device can import another device's `start` before
//  the matching `end` for the *same* fast — a window in which there genuinely
//  appear to be two open fasts, and acting immediately would truncate a fast
//  that was already properly closed. Waiting for the condition to hold still
//  after a quiet period narrows this to a real conflict.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class SyncReconciler {
    /// How long the "two open fasts" condition must persist before we act.
    /// Long enough to outlast a batch of related records arriving out of order,
    /// short enough that a real conflict resolves while the user is still looking.
    private static let settleDelay: Duration = .seconds(3)

    /// Set when a merge actually changed something, so the UI can tell the user
    /// their fast was truncated rather than silently mutating it under them.
    var notice: String?

    private var pending: Task<Void, Never>?

    /// Called whenever the open-fast count changes. Cheap and idempotent.
    func openFastCountChanged(to count: Int, context: ModelContext) {
        guard count > 1 else {
            pending?.cancel()
            pending = nil
            return
        }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.reconcile(context: context)
        }
    }

    /// Apply the merge if it's still needed. Safe to call at any time.
    func reconcile(context: ModelContext) {
        let store = FastStore(context: context)
        let fasts = store.allFasts()
        let actions = OpenFastMerge.plan(for: fasts.records)
        guard !actions.isEmpty else { return }

        var byID: [UUID: Fast] = [:]
        for fast in fasts { byID[fast.id] = fast }

        var closed = 0
        for action in actions {
            switch action {
            case .close(let id, let date):
                guard let fast = byID[id] else { continue }
                fast.end = date
                closed += 1
            case .delete(let id):
                guard let fast = byID[id] else { continue }
                context.delete(fast)
            }
        }
        try? context.save()

        // Both already handle being called redundantly.
        store.reconcileNotifications()
        store.reloadWidgets()

        if closed > 0 {
            notice = "Two fasts were running on different devices. The later one was kept."
        }
    }
}
