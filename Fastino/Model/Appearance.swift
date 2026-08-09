//
//  Appearance.swift
//  Fastino
//
//  The UI-mode preference (§3, §5). "System" follows iOS; the other two pin the
//  app to one of the two palettes regardless of the device setting.
//

import SwiftUI

nonisolated enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "don't override" — the value `preferredColorScheme` wants for
    /// the system-following case.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Resolve a stored id, defaulting to system for unknown values
    /// (forward-compatibility, same as `FastingProtocol.from(id:)`).
    static func from(id: String) -> Appearance {
        Appearance(rawValue: id) ?? .system
    }
}
