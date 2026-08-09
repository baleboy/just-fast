//
//  Theme.swift
//  Fastino
//
//  Design tokens (§5) for the "Ember" system: the fast reads as a fire burning
//  through metabolic zones. Deep plum-to-black in dark, warm paper in light, and
//  a gold→orange→pink heat scale that both the ring and the stats bars share.
//
//  Two ways to reach a token:
//  • `Theme.something` — a dynamic `Color` that resolves itself per trait, for
//    ordinary view code.
//  • `Theme.palette(for: colorScheme)` — the same values as *numbers* (`RGBA`),
//    which is what the ring needs: it interpolates between zone colours to place
//    the elapsed/remaining split mid-band, and you can't lerp a dynamic Color.
//

import SwiftUI
import UIKit

// MARK: - Numeric colour

/// A colour we can do arithmetic on. `Color` is opaque and a *dynamic* Color has
/// no single value at all, so the ring's gradient maths works on these instead.
nonisolated struct RGBA: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ hex: UInt32, _ a: Double = 1) {
        self.init(
            r: Double((hex >> 16) & 0xFF) / 255,
            g: Double((hex >> 8) & 0xFF) / 255,
            b: Double(hex & 0xFF) / 255,
            a: a
        )
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func alpha(_ newValue: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: newValue) }

    /// Straight component-wise mix. Good enough — the two ends of every band are
    /// neighbours on the heat scale, so there's no hue detour to worry about.
    static func mix(_ from: RGBA, _ to: RGBA, _ t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        return RGBA(
            r: from.r + (to.r - from.r) * t,
            g: from.g + (to.g - from.g) * t,
            b: from.b + (to.b - from.b) * t,
            a: from.a + (to.a - from.a) * t
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self = RGBA(hex, opacity).color
    }
}

// MARK: - Zone palette

/// The colours of one metabolic band. `from`/`to` are the ends of the gradient
/// *inside* the band on the ring; `label` is the flat colour used for text.
nonisolated struct ZonePalette: Equatable, Sendable {
    let from: RGBA
    let to: RGBA
    let label: RGBA
}

// MARK: - Full palette

nonisolated struct EmberPalette: Equatable, Sendable {
    /// Three stops of the screen's radial gradient, centre → edge.
    let backgroundStops: [RGBA]

    let textPrimary: RGBA
    let textSecondary: RGBA
    let textTertiary: RGBA

    let cardBackground: RGBA
    let cardBorder: RGBA
    let cardSeparator: RGBA
    /// Drop shadow under cards. Transparent in dark, where cards separate by
    /// their own translucent fill instead.
    let cardShadow: RGBA

    let accent: RGBA
    /// Accent tuned for text on the screen background — the raw accent doesn't
    /// carry enough contrast at small sizes in either mode.
    let accentText: RGBA
    let accentChip: RGBA
    /// The soft halo that makes a highlighted card look lit from within.
    let accentGlow: RGBA

    let success: RGBA

    /// Left→right gradient for the primary button and for gradient-filled numerals.
    let heatGradient: [RGBA]
    /// Fill for a "missed day" bar and for an off toggle.
    let mutedFill: RGBA
    /// Knob of an off toggle.
    let mutedKnob: RGBA

    /// Gold, orange, pink — index-aligned with `MetabolicZone.allCases`.
    let zones: [ZonePalette]
    /// Alpha the not-yet-reached part of the ring fades to, at the start and end
    /// of a band.
    let zoneDimAlpha: (low: Double, high: Double)

    static func == (lhs: EmberPalette, rhs: EmberPalette) -> Bool {
        lhs.accent == rhs.accent && lhs.textPrimary == rhs.textPrimary
    }

    static let dark = EmberPalette(
        backgroundStops: [RGBA(0x2A1A3E), RGBA(0x181022), RGBA(0x120B1A)],
        textPrimary: RGBA(0xF3ECFF),
        textSecondary: RGBA(0xF3ECFF, 0.55),
        textTertiary: RGBA(0xF3ECFF, 0.4),
        cardBackground: RGBA(0xFFFFFF, 0.05),
        cardBorder: RGBA(0xFFFFFF, 0.12),
        cardSeparator: RGBA(0xFFFFFF, 0.08),
        cardShadow: RGBA(0x000000, 0),
        accent: RGBA(0xFF8A3D),
        accentText: RGBA(0xFFBE8F),
        accentChip: RGBA(0xFF8A3D, 0.16),
        accentGlow: RGBA(0xFF8A3D, 0.3),
        success: RGBA(0x7FE8C3),
        heatGradient: [RGBA(0xFFD066), RGBA(0xFF8A3D)],
        mutedFill: RGBA(0xFFFFFF, 0.1),
        mutedKnob: RGBA(0xFFFFFF, 0.6),
        zones: [
            ZonePalette(from: RGBA(0xFFE9A0), to: RGBA(0xFFC24D), label: RGBA(0xFFD066)),
            ZonePalette(from: RGBA(0xFF9A3D), to: RGBA(0xFF7A2E), label: RGBA(0xFF8A3D)),
            ZonePalette(from: RGBA(0xFF5470), to: RGBA(0xFF4468), label: RGBA(0xFF7089)),
        ],
        zoneDimAlpha: (0.16, 0.32)
    )

    static let light = EmberPalette(
        backgroundStops: [RGBA(0xFDF3E3), RGBA(0xF8F1E8), RGBA(0xF3ECE2)],
        textPrimary: RGBA(0x2A1A3E),
        textSecondary: RGBA(0x2A1A3E, 0.5),
        textTertiary: RGBA(0x2A1A3E, 0.35),
        cardBackground: RGBA(0xFFFFFF),
        cardBorder: RGBA(0x2A1A3E, 0.1),
        cardSeparator: RGBA(0x2A1A3E, 0.08),
        cardShadow: RGBA(0x2A1A3E, 0.05),
        accent: RGBA(0xFF8F2E),
        accentText: RGBA(0xC1500F),
        accentChip: RGBA(0xFF6F1E, 0.1),
        accentGlow: RGBA(0xFF8C3C, 0.25),
        success: RGBA(0x1F8A63),
        heatGradient: [RGBA(0xE0870F), RGBA(0xFF6F1E)],
        mutedFill: RGBA(0x2A1A3E, 0.08),
        mutedKnob: RGBA(0xFFFFFF),
        zones: [
            ZonePalette(from: RGBA(0xFFD98A), to: RGBA(0xFFB23D), label: RGBA(0xD98A12)),
            ZonePalette(from: RGBA(0xFF8F2E), to: RGBA(0xFF6F1E), label: RGBA(0xE0570F)),
            ZonePalette(from: RGBA(0xFF5470), to: RGBA(0xFF4468), label: RGBA(0xD63A5C)),
        ],
        zoneDimAlpha: (0.22, 0.36)
    )

    static func of(_ scheme: ColorScheme) -> EmberPalette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Dynamic tokens

enum Theme {
    static func palette(for scheme: ColorScheme) -> EmberPalette { .of(scheme) }

    /// Flat fallback behind the radial gradient — also what `.background` needs
    /// when a colour rather than a view is required.
    static let backgroundBase = dynamic(\.backgroundStops[1])

    static let primaryText = dynamic(\.textPrimary)
    static let secondaryText = dynamic(\.textSecondary)
    static let tertiaryText = dynamic(\.textTertiary)

    static let card = dynamic(\.cardBackground)
    static let cardBorder = dynamic(\.cardBorder)
    static let cardSeparator = dynamic(\.cardSeparator)
    static let cardShadow = dynamic(\.cardShadow)

    static let accent = dynamic(\.accent)
    static let accentText = dynamic(\.accentText)
    static let accentChip = dynamic(\.accentChip)
    static let accentGlow = dynamic(\.accentGlow)

    /// Success only (§5) — never decoration.
    static let success = dynamic(\.success)

    static let mutedFill = dynamic(\.mutedFill)

    static func heatGradient(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: EmberPalette.of(scheme).heatGradient.map(\.color),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static func dynamic(_ keyPath: KeyPath<EmberPalette, RGBA>) -> Color {
        Color(uiColor: UIColor { traits in
            let palette = EmberPalette.of(traits.userInterfaceStyle == .dark ? .dark : .light)
            return UIColor(palette[keyPath: keyPath].color)
        })
    }
}

// MARK: - Radii & shape

enum Radius {
    static let card: CGFloat = 20
    static let smallCard: CGFloat = 16
    static let planCard: CGFloat = 18
}
