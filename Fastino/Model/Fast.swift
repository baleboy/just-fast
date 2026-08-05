//
//  Fast.swift
//  Fastino
//
//  A single fasting session (§3). Stored via SwiftData; every property has a
//  default so the schema is CloudKit-compatible (CloudKit requires all
//  attributes to be optional or defaulted, and forbids unique constraints).
//

import Foundation
import SwiftData

@Model
final class Fast {
    var id: UUID = UUID()
    /// Absolute instant (UTC) the fast began.
    var start: Date = Date()
    /// Absolute instant the fast ended; `nil` while in progress.
    var end: Date?
    /// Snapshot of the protocol goal (hours) at start — never changes retroactively.
    var goalHours: Int = 16
    /// Snapshot of the protocol id (e.g. "16:8") at start.
    var protocolID: String = FastingProtocol.p168.rawValue
    var note: String?
    var createdViaRaw: String = CreatedVia.app.rawValue

    init(
        id: UUID = UUID(),
        start: Date = Date(),
        end: Date? = nil,
        goalHours: Int,
        protocolID: String,
        note: String? = nil,
        createdVia: CreatedVia = .app
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.goalHours = goalHours
        self.protocolID = protocolID
        self.note = note
        self.createdViaRaw = createdVia.rawValue
    }

    var createdVia: CreatedVia {
        get { CreatedVia(rawValue: createdViaRaw) ?? .app }
        set { createdViaRaw = newValue.rawValue }
    }

    var isOpen: Bool { end == nil }

    /// Pure value snapshot for the engine / validation.
    var record: FastRecord {
        FastRecord(id: id, start: start, end: end, goalHours: goalHours)
    }
}

extension Array where Element == Fast {
    /// Snapshot an array of model objects into pure records for the engine.
    var records: [FastRecord] { map(\.record) }
}
