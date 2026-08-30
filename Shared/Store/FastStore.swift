//
//  FastStore.swift
//  Fastino
//
//  The single write path for fasts (§4.6, §7). The app UI, App Intents, widgets
//  and the watch all mutate through these methods, so validation, notification
//  scheduling and widget reloads happen consistently regardless of entry point.
//

import Foundation
import SwiftData
import WidgetKit

nonisolated enum AppError: Error, Equatable {
    case alreadyFasting
    case notFasting

    var message: String {
        switch self {
        case .alreadyFasting: "A fast is already in progress."
        case .notFasting: "No fast is currently running."
        }
    }
}

/// Outcome of a start/end action, carrying the celebration-relevant facts so the
/// UI can decide whether to bloom the ring, roll the streak, or show a record.
struct FastActionResult: Equatable {
    enum Kind: Equatable { case started, ended }
    let kind: Kind
    let fast: FastRecord
    /// Only meaningful for `.ended`.
    var goalMet: Bool = false
    var isNewLongestFast: Bool = false
    var isNewLongestStreak: Bool = false
    var currentStreak: Int = 0
}

@MainActor
struct FastStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reads

    func allFasts() -> [Fast] {
        let descriptor = FetchDescriptor<Fast>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func records() -> [FastRecord] { allFasts().records }

    func openFast() -> Fast? {
        allFasts().first(where: \.isOpen)
    }

    /// Fetch the settings object, creating it on first use and collapsing the
    /// duplicates CloudKit can leave behind (see `AppSettings`).
    func settings() -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        let existing = (try? context.fetch(descriptor)) ?? []

        switch existing.count {
        case 0:
            // Placeholder, not a preference — dated `.distantPast` so the user's
            // real settings win when they sync in from another device. Creating
            // it with `Date()` would make a fresh 16:8 default outrank a plan
            // the user chose yesterday on their phone.
            let created = AppSettings.unedited()
            context.insert(created)
            try? context.save()
            return created
        case 1:
            // The steady state — no election, so the hot path costs what it always did.
            return existing[0]
        default:
            guard let winner = SettingsElection.survivor(among: existing.map(\.identity)),
                  let survivor = existing.first(where: { $0.id == winner.id })
            else { return existing[0] }

            for loser in existing where loser.id != winner.id {
                context.delete(loser)
            }
            // Both devices race to delete the same losers; deleting an
            // already-deleted record is a no-op, so the operation is idempotent.
            try? context.save()
            return survivor
        }
    }

    // MARK: Writes

    @discardableResult
    func startFast(at date: Date = Date(), createdVia: CreatedVia = .app) throws -> FastActionResult {
        guard openFast() == nil else { throw AppError.alreadyFasting }
        let settings = settings()
        let proto = settings.activeProtocol

        try FastValidation.validate(start: date, end: nil, excludingID: nil, against: records())

        let fast = Fast(
            start: date,
            end: nil,
            goalHours: proto.goalHours,
            protocolID: proto.rawValue,
            createdVia: createdVia
        )
        context.insert(fast)
        try context.save()

        NotificationManager.shared.scheduleGoalNotification(for: fast.record, enabled: settings.goalNotificationEnabled)
        NotificationManager.shared.scheduleMilestoneNotifications(for: fast.record, enabled: settings.milestoneNotificationsEnabled)
        NotificationManager.shared.cancelStartReminder() // suppressed while a fast runs (§4.4)
        reloadWidgets()

        return FastActionResult(kind: .started, fast: fast.record)
    }

    /// End the open fast (§4.1).
    ///
    /// `note` is *not* a value to store but a decision about the note: `nil`
    /// leaves whatever the fast already carries alone, which is what the
    /// intents and the watch want, since neither offers anywhere to type one. A
    /// non-`nil` string is the user's intent from the end sheet and replaces it
    /// — blank included, so clearing a prefilled note actually clears it.
    @discardableResult
    func endFast(
        at date: Date = Date(),
        note: String? = nil,
        createdVia: CreatedVia = .app
    ) throws -> FastActionResult {
        guard let fast = openFast() else { throw AppError.notFasting }

        // Records excluding the one being closed, for overlap validation.
        let others = records().filter { $0.id != fast.id }
        try FastValidation.validate(start: fast.start, end: date, excludingID: nil, against: others)

        // Snapshot pre-change bests to detect records.
        let allBefore = records()
        let previousLongestFast = FastingEngine.longestFast(allBefore.filter { $0.id != fast.id }, now: date)
        let previousLongestStreak = FastingEngine.longestStreak(allBefore, timeZone: .current)

        fast.end = date
        if let note { fast.note = note.nilIfBlank }
        if createdVia != .app { fast.createdVia = createdVia }
        try context.save()

        let closed = fast.record
        let after = records()
        let newLongestStreak = FastingEngine.longestStreak(after, timeZone: .current)

        NotificationManager.shared.cancelGoalNotification(for: closed.id)
        NotificationManager.shared.cancelMilestoneNotifications(for: closed.id)
        // Reconcile rather than reschedule directly: no fast is running now, so
        // the start reminder that was suppressed needs re-arming.
        reconcileNotifications()
        reloadWidgets()

        return FastActionResult(
            kind: .ended,
            fast: closed,
            goalMet: closed.isGoalMet,
            isNewLongestFast: closed.isGoalMet && (closed.finalDuration ?? 0) > previousLongestFast,
            isNewLongestStreak: newLongestStreak > previousLongestStreak,
            currentStreak: FastingEngine.currentStreak(after, now: date, timeZone: .current)
        )
    }

    /// Start if idle, end if a fast is open (§4.6 ToggleFastIntent).
    @discardableResult
    func toggle(at date: Date = Date(), createdVia: CreatedVia = .app) throws -> FastActionResult {
        if openFast() == nil {
            return try startFast(at: date, createdVia: createdVia)
        } else {
            return try endFast(at: date, createdVia: createdVia)
        }
    }

    /// Add a completely missed fast retroactively (§4.2).
    func addManual(start: Date, end: Date?, note: String?) throws {
        let settings = settings()
        let proto = settings.activeProtocol
        try FastValidation.validate(start: start, end: end, excludingID: nil, against: records())
        let fast = Fast(
            start: start,
            end: end,
            goalHours: proto.goalHours,
            protocolID: proto.rawValue,
            note: note?.nilIfBlank,
            createdVia: .manual
        )
        context.insert(fast)
        try context.save()
        reconcileNotifications()
        reloadWidgets()
    }

    /// Edit start/end/note of an existing fast (§4.2). Recomputes side effects.
    func update(_ fast: Fast, start: Date, end: Date?, note: String?) throws {
        try FastValidation.validate(start: start, end: end, excludingID: fast.id, against: records())
        fast.start = start
        fast.end = end
        fast.note = note?.nilIfBlank
        try context.save()
        reconcileNotifications()
        reloadWidgets()
    }

    /// Re-goal the fast in progress, because the user asked for it in as many
    /// words (§4.1).
    ///
    /// `goalHours`/`protocolID` are snapshotted at start and a Settings change
    /// still never reaches back on its own — the rule is unchanged. This is the
    /// one deliberate exception: the plan dialog offers it explicitly, and
    /// nothing else may call this. It is the only path by which a running
    /// fast's goal moves.
    ///
    /// No validation: the goal has no bearing on whether the interval itself is
    /// legal. Reconciling is the whole job — the goal alert and both milestones
    /// are derived from `goalHours` and would otherwise stay armed for the goal
    /// the user just replaced. A new goal already behind the fast simply arms
    /// nothing (`scheduleGoalNotification` drops a fire date in the past).
    func applyProtocol(_ proto: FastingProtocol, to fast: Fast) throws {
        fast.goalHours = proto.goalHours
        fast.protocolID = proto.rawValue
        try context.save()
        reconcileNotifications()
        reloadWidgets()
    }

    func delete(_ fast: Fast) {
        let id = fast.id
        context.delete(fast)
        try? context.save()
        NotificationManager.shared.cancelGoalNotification(for: id)
        NotificationManager.shared.cancelMilestoneNotifications(for: id)
        reconcileNotifications()
        reloadWidgets()
    }

    // MARK: Side effects

    /// Keep the goal notification and start reminders consistent with the current
    /// open fast + settings after an arbitrary edit.
    func reconcileNotifications() {
        let settings = settings()
        if let open = openFast() {
            NotificationManager.shared.scheduleGoalNotification(for: open.record, enabled: settings.goalNotificationEnabled)
            NotificationManager.shared.scheduleMilestoneNotifications(for: open.record, enabled: settings.milestoneNotificationsEnabled)
            NotificationManager.shared.cancelStartReminder() // suppressed while a fast runs (§4.4)
        } else if settings.startReminderEnabled {
            NotificationManager.shared.scheduleStartReminder(
                hour: settings.startReminderHour,
                minute: settings.startReminderMinute
            )
        } else {
            NotificationManager.shared.cancelStartReminder()
        }
    }

    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        // A control is not a timeline, so `WidgetCenter` never touches it.
        // Without this, starting a fast in the app leaves the Control Center
        // toggle reading "off" until the system next happens to poll its value
        // provider — which is not on any schedule the app can rely on.
        ControlCenter.shared.reloadControls(ofKind: FastinoWidgetKind.fastingControl)
        #endif
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
