//
//  AppSettings.swift
//  Fastino
//
//  The single settings object (§3). Stored via SwiftData. The start-reminder
//  wall-clock time is stored as hour/minute Ints rather than DateComponents so
//  it round-trips cleanly through SwiftData + CloudKit.
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    var activeProtocolID: String = FastingProtocol.p168.rawValue
    var startReminderEnabled: Bool = true
    var startReminderHour: Int = 20
    var startReminderMinute: Int = 0
    var goalNotificationEnabled: Bool = true
    /// "Fat burn" / "Ketosis" nudges as the fast crosses `MetabolicZone` boundaries.
    var milestoneNotificationsEnabled: Bool = true
    var appearanceID: String = Appearance.system.rawValue

    init(
        activeProtocolID: String = FastingProtocol.p168.rawValue,
        startReminderEnabled: Bool = true,
        startReminderHour: Int = 20,
        startReminderMinute: Int = 0,
        goalNotificationEnabled: Bool = true,
        milestoneNotificationsEnabled: Bool = true,
        appearanceID: String = Appearance.system.rawValue
    ) {
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
}
