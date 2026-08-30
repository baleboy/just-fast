//
//  CreatedVia.swift
//  Fastino
//
//  Records which surface created a fast, per the data model in §3.
//

import Foundation

nonisolated enum CreatedVia: String, Codable, CaseIterable, Sendable {
    case app
    case lockScreenWidget
    case homeWidget
    /// The Control Center toggle (§4.5). Distinct from `homeWidget` because it
    /// is a different surface with different behaviour — no confirmation.
    case control
    case watch
    case manual
}
