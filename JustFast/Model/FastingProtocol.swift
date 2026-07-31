//
//  FastingProtocol.swift
//  JustFast
//
//  The fixed list of supported intermittent-fasting protocols. The first
//  number in each label is the fasting *goal* in hours (§2 of the spec).
//

import Foundation

nonisolated enum FastingProtocol: String, CaseIterable, Identifiable, Sendable {
    case p1410 = "14:10"
    case p168 = "16:8"
    case p186 = "18:6"
    case p204 = "20:4"
    case omad = "23:1"

    var id: String { rawValue }

    /// Fasting goal in hours (the first number of the protocol label).
    var goalHours: Int {
        switch self {
        case .p1410: 14
        case .p168: 16
        case .p186: 18
        case .p204: 20
        case .omad: 23
        }
    }

    /// Length of the eating window in hours.
    var eatingHours: Int { 24 - goalHours }

    var displayName: String {
        self == .omad ? "OMAD (23:1)" : rawValue
    }

    /// Resolve a stored `protocolID` string back to a protocol, defaulting to
    /// 16:8 if an unknown value is encountered (forward-compatibility).
    static func from(id: String) -> FastingProtocol {
        FastingProtocol(rawValue: id) ?? .p168
    }
}
