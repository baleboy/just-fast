//
//  AppSettings.swift
//  Fastino
//
//  The settings object (§3). Stored via SwiftData. The start-reminder wall-clock
//  time is stored as hour/minute Ints rather than DateComponents so it
//  round-trips cleanly through SwiftData + CloudKit.
//
//  "Singleton" is a convention here, not a constraint — CloudKit forbids unique
//  constraints, so two devices that first launch offline each create a row and
//  sync keeps both. `id` + `updatedAt` exist to resolve that: see
//  `SettingsElection`, which every device runs to pick the same survivor from
//  the same data. Both are defaulted, so they stay CloudKit-compatible.
//
//  **A row nobody has edited must lose that election.** `FastStore.settings()`
//  auto-creates one whenever it finds none, and a row created *now* would beat
//  the user's real settings edited yesterday on another device — silently
//  resetting their plan to the 16:8 default. That's why `unedited()` exists and
//  why it stamps `.distantPast`: an auto-created row is a placeholder, not a
//  preference, and it should yield to any genuine edit that reaches it.
//  `touch()` promotes it to a real timestamp the moment the user changes
//  anything.
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    var id: UUID = UUID()
    /// Bumped by `touch()` on every user edit; drives `elect(from:)`.
    var updatedAt: Date = Date()
    var activeProtocolID: String = FastingProtocol.p168.rawValue
    var startReminderEnabled: Bool = true
    var startReminderHour: Int = 20
    var startReminderMinute: Int = 0
    var goalNotificationEnabled: Bool = true
    /// "Fat burn" / "Ketosis" nudges as the fast crosses `MetabolicZone` boundaries.
    var milestoneNotificationsEnabled: Bool = true
    var appearanceID: String = Appearance.system.rawValue

    init(
        id: UUID = UUID(),
        updatedAt: Date = Date(),
        activeProtocolID: String = FastingProtocol.p168.rawValue,
        startReminderEnabled: Bool = true,
        startReminderHour: Int = 20,
        startReminderMinute: Int = 0,
        goalNotificationEnabled: Bool = true,
        milestoneNotificationsEnabled: Bool = true,
        appearanceID: String = Appearance.system.rawValue
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.activeProtocolID = activeProtocolID
        self.startReminderEnabled = startReminderEnabled
        self.startReminderHour = startReminderHour
        self.startReminderMinute = startReminderMinute
        self.goalNotificationEnabled = goalNotificationEnabled
        self.milestoneNotificationsEnabled = milestoneNotificationsEnabled
        self.appearanceID = appearanceID
    }

    var activeProtocol: FastingProtocol {
        get { FastingProtocol.from(id: activeProtocolID) }
        set { activeProtocolID = newValue.rawValue }
    }

    var appearance: Appearance {
        get { Appearance.from(id: appearanceID) }
        set { appearanceID = newValue.rawValue }
    }

    var startReminderComponents: DateComponents {
        DateComponents(hour: startReminderHour, minute: startReminderMinute)
    }

    /// A placeholder row, created because none existed yet — not a choice the
    /// user has made. Dated `.distantPast` so that any real settings arriving
    /// from another device win the election; see the note at the top of this
    /// file. `touch()` promotes it on the first genuine edit.
    static func unedited() -> AppSettings {
        AppSettings(updatedAt: .distantPast)
    }

    /// Whether this row is still a placeholder.
    var isUnedited: Bool { updatedAt == .distantPast }

    /// Record a user edit. Views bind to this object directly with `@Bindable`,
    /// bypassing `FastStore`, so they must call this for the election to have
    /// anything to order by.
    func touch(at date: Date = Date()) {
        updatedAt = date
    }

    var identity: SettingsIdentity { SettingsIdentity(id: id, updatedAt: updatedAt) }

    /// Every user-editable field, and deliberately *not* `updatedAt` — views
    /// watch this to know when to `touch()`, so including the timestamp would
    /// make the observation re-trigger itself.
    var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            activeProtocolID: activeProtocolID,
            startReminderEnabled: startReminderEnabled,
            startReminderHour: startReminderHour,
            startReminderMinute: startReminderMinute,
            goalNotificationEnabled: goalNotificationEnabled,
            milestoneNotificationsEnabled: milestoneNotificationsEnabled,
            appearanceID: appearanceID
        )
    }
}

nonisolated struct SettingsSnapshot: Equatable, Sendable {
    let activeProtocolID: String
    let startReminderEnabled: Bool
    let startReminderHour: Int
    let startReminderMinute: Int
    let goalNotificationEnabled: Bool
    let milestoneNotificationsEnabled: Bool
    let appearanceID: String
}

/// The subset of `AppSettings` the election needs — pulled out so the rule is a
/// pure function testable without a `ModelContainer`.
nonisolated struct SettingsIdentity: Equatable, Sendable {
    let id: UUID
    let updatedAt: Date
}

nonisolated enum SettingsElection {
    /// Pick the row that survives when sync leaves more than one.
    ///
    /// Newest `updatedAt` wins; ties break on the lowest `id` string. Both rules
    /// are functions of the replicated data alone, so every device independently
    /// reaches the same answer — which is what makes the dedupe converge instead
    /// of two devices deleting each other's survivor forever.
    ///
    /// Last-writer-wins on the whole object, deliberately: merging seven
    /// independent toggles field-by-field would produce a settings state neither
    /// user ever chose.
    static func survivor(among candidates: [SettingsIdentity]) -> SettingsIdentity? {
        candidates.max { a, b in
            a.updatedAt == b.updatedAt
                ? a.id.uuidString > b.id.uuidString
                : a.updatedAt < b.updatedAt
        }
    }
}
