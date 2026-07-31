//
//  FastIntents.swift
//  JustFast
//
//  App Intents shared by Shortcuts, Siri, Back Tap, widgets and the watch
//  (§4.6). One implementation, reused everywhere, writing through FastStore so
//  the same validation and side effects apply.
//

import AppIntents
import SwiftData
import WidgetKit

@MainActor
private func makeStore() -> FastStore {
    FastStore(context: AppContainer.shared.mainContext)
}

// MARK: - Start

struct StartFastIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Fast"
    static let description = IntentDescription("Start a new fast now.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = makeStore()
        guard store.openFast() == nil else {
            return .result(dialog: "You’re already fasting.")
        }
        try store.startFast(createdVia: .app)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Fast started. 🎯")
    }
}

// MARK: - End

struct EndFastIntent: AppIntent {
    static let title: LocalizedStringResource = "End Fast"
    static let description = IntentDescription("End the fast in progress.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = makeStore()
        guard store.openFast() != nil else {
            return .result(dialog: "No fast is running.")
        }
        let result = try store.endFast(createdVia: .app)
        WidgetCenter.shared.reloadAllTimelines()
        let dur = DurationFormat.hoursMinutes(result.fast.finalDuration ?? 0)
        let tail = result.goalMet ? " — goal reached ✓" : " — logged"
        return .result(dialog: "Fast ended: \(dur)\(tail)")
    }
}

// MARK: - Toggle (Back Tap headline use case, §4.6)

struct ToggleFastIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Fast"
    static let description = IntentDescription("Start a fast if none is running, otherwise end the current one.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = makeStore()

        // State-aware confirmation — what makes it safe to bind to Back Tap.
        if let open = store.openFast() {
            let elapsed = DurationFormat.hoursMinutes(open.record.duration(asOf: Date()))
            let goalTail = open.record.duration(asOf: Date()) >= open.record.goalInterval ? " — goal reached ✓" : ""
            try await requestConfirmation(
                result: .result(dialog: "End fast? \(elapsed) elapsed\(goalTail)"),
                confirmationActionName: .go
            )
            let result = try store.endFast(createdVia: .app)
            WidgetCenter.shared.reloadAllTimelines()
            let dur = DurationFormat.hoursMinutes(result.fast.finalDuration ?? 0)
            return .result(dialog: "Fast ended: \(dur).")
        } else {
            try await requestConfirmation(
                result: .result(dialog: "Start fasting now?"),
                confirmationActionName: .start
            )
            try store.startFast(createdVia: .app)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Fast started. 🎯")
        }
    }
}

// MARK: - App Shortcuts (zero-setup, Siri-invocable)

struct JustFastShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleFastIntent(),
            phrases: [
                "Toggle my fast in \(.applicationName)",
                "\(.applicationName) toggle fast"
            ],
            shortTitle: "Toggle Fast",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StartFastIntent(),
            phrases: [
                "Start my fast in \(.applicationName)",
                "Start fasting with \(.applicationName)"
            ],
            shortTitle: "Start Fast",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: EndFastIntent(),
            phrases: [
                "End my fast in \(.applicationName)",
                "Stop fasting with \(.applicationName)"
            ],
            shortTitle: "End Fast",
            systemImageName: "stop.circle"
        )
    }
}
