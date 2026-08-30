//
//  SetFastingIntent.swift
//  Fastino Widgets
//
//  What the Control Center toggle runs (§4.5).
//
//  **It writes from the extension process**, which is the one place in the app
//  that isn't the app. `AppContainer.readOnly()` is for surfaces that display;
//  this one has to act, so it goes through `writableShared()` — same file, same
//  `FastStore`, same validation and side effects, mirroring still off. The
//  write reaches CloudKit via persistent history the next time the app runs.
//  Anything less (opening the app on every tap, or queueing the intent for
//  later) would either defeat the point of a toggle or mean the fast doesn't
//  exist until the app is next opened.
//
//  Reconciling notifications here is not optional: without it a fast started
//  from Control Center has no goal alert armed until the app is opened, which
//  is the same bug `RemoteChangeRefresher` exists to prevent on the watch.
//  `FastStore` does it on every write, so it happens for free — and it is safe
//  here, because `NotificationOwnership.schedulesLocally` is unconditionally
//  true off watchOS, so no WatchConnectivity is touched.
//
//  Deliberately **not** an App Shortcut and not discoverable: `ToggleFastIntent`
//  (§4.6) is the Shortcuts/Back Tap action, and two near-identical entries would
//  make the Shortcuts library worse, not better.
//

import AppIntents
import SwiftData
import WidgetKit

struct SetFastingIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Fasting"
    static let description = IntentDescription("Start or end a fast from Control Center.")
    static var isDiscoverable: Bool { false }
    static let openAppWhenRun = false

    @Parameter(title: "Fasting")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = AppContainer.writableShared() else { return .result() }
        let store = FastStore(context: ModelContext(container))

        // Guarded on the store rather than trusting `value`: the control's
        // snapshot can be stale (a fast started on the watch, or in the app
        // before the reload landed), and a toggle that throws into Control
        // Center is worse than one that does nothing.
        if value {
            guard store.openFast() == nil else { return .result() }
            try store.startFast(createdVia: .control)
        } else {
            guard store.openFast() != nil else { return .result() }
            try store.endFast(createdVia: .control)
        }
        return .result()
    }
}
