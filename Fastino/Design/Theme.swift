//
//  Theme.swift
//  Fastino
//
//  Design tokens (§5): distinctive, calm, warm. Deep aubergine in dark, cream
//  paper in light, warm amber for the active ring, mint reserved exclusively for
//  success. Values are tokens tuned during design.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Theme {
    // Backgrounds
    static let background = Color.dynamicToken(light: 0xFAF3E8, dark: 0x2B1B33)
    static let surface = Color.dynamicToken(light: 0xFFFFFF, dark: 0x3A2542)
    static let ringTrack = Color.dynamicToken(light: 0xE7DCC9, dark: 0x452E4F)

    // Content
    static let primaryText = Color.dynamicToken(light: 0x2B1B33, dark: 0xFAF3E8)
    static let secondaryText = Color.dynamicToken(light: 0x7A6E63, dark: 0xB9A8C4)

    // Accents
    static let amber = Color(hex: 0xFFB25E)          // active fast ring
    static let mint = Color(hex: 0x7FE0C3)           // success ONLY (§5)
    static let amberSoft = Color(hex: 0xFFC98A)
    /// Eating window ring — a calm lilac that sits between the two aubergine
    /// backgrounds. Deliberately not mint (success-only, §5) and not amber, so
    /// "eating" never reads as "fasting" at a glance.
    static let lilac = Color(hex: 0xB48AD6)
    static let lilacSoft = Color(hex: 0xD5B6EC)

    static let ringGradient = [amber, amberSoft]
    static let successGradient = [mint, Color(hex: 0xA8ECD8)]
    static let eatingGradient = [lilac, lilacSoft]
}

private extension Color {
    static func dynamicToken(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}
