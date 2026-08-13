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
    case watch
    case manual
}
