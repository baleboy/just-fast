//
//  Theme.swift
//  Fastino
//
//  Design tokens (§5) for the "Flame Friend" system: warm, cute, peach-toned,
//  built around a little flame mascot who changes colour and expression with the
//  metabolic zone.
//
//  Two ways to reach a token:
//  • `Theme.something` — a dynamic `Color` that resolves itself per trait, for
//    ordinary view code.
//  • `Theme.palette(for: colorScheme)` — the same values as *numbers* (`RGBA`),
//    which is what the ring and the mascot need: they interpolate between zone
//    colours, and you can't lerp an opaque dynamic Color.
//
//  **The handoff specifies light only.** The dark palette below is derived, not
//  designed: the same hues over a deep cocoa ground, with the mascot and the
//  accents untouched so the character reads identically in both. Treat it as a
//  placeholder a designer may want to correct.
//

import SwiftUI
import UIKit

// MARK: - Numeric colour

/// A colour we can do arithmetic on. `Color` is opaque and a *dynamic* Color has
/// no single value at all, so the ring and mascot maths work on these instead.
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

/// The colours of one metabolic band, shared by the ring, the mascot and the
/// zone beads so they can never disagree.
nonisolated struct ZonePalette: Equatable, Sendable {
    /// Ends of the gradient inside the band (also the mascot's body gradient).
    let from: RGBA
    let to: RGBA
    /// The band's colour once you're past it but not in it — the ring's unreached
    /// segments and the "upcoming" bead dot.
    let dimmed: RGBA
    /// Flat colour for the bead dot when the zone is done.
    let dot: RGBA
}

// MARK: - Full palette

nonisolated struct FlamePalette: Equatable, Sendable {
    /// Two stops of the screen's vertical gradient, top → bottom.
    let backgroundStops: [RGBA]
    /// Calmer variant used by the eating-window screen.
    let restingBackgroundStops: [RGBA]

    /// Headings and numbers.
    let ink: RGBA
    /// Body copy and row labels.
    let body: RGBA
    /// Captions and secondary values.
    let muted: RGBA
    /// The lowercase "fastino" wordmark.
    let brand: RGBA
    /// Accent text — the one colour that says "this is the live thing".
    let accentText: RGBA

    let card: RGBA
    let cardShadow: RGBA
    /// Peach surface behind a selected card, bead or tab chip.
    let accentSurface: RGBA
    /// 2.5pt border around a selected card.
    let accentBorder: RGBA
    /// Ink used on top of `accentSurface` (the goal-rate card).
    let onAccentSurface: RGBA
    /// Dashed row dividers inside grouped cards.
    let divider: RGBA

    let success: RGBA
    let successSurface: RGBA

    /// The primary button: gradient top → bottom, plus the hard 3D press shadow.
    let buttonGradient: [RGBA]
    let buttonShadow: RGBA
    /// Softer variant used on the eating-window screen.
    let restingButtonGradient: [RGBA]
    let restingButtonShadow: RGBA

    /// Unlit mascot fill (with a face) and the ink used on it.
    let mutedFlame: RGBA
    let mutedFlameInk: RGBA
    /// Unlit mascot fill with no face — the missed days in the week strip.
    let plainFlame: RGBA
    /// The dashed circle of the waiting ring.
    let waitingRing: RGBA
    /// Off state of a toggle.
    let toggleOff: RGBA

    /// Gold, orange, pink — index-aligned with `MetabolicZone.allCases`.
    let zones: [ZonePalette]

    static let light = FlamePalette(
        backgroundStops: [RGBA(0xFFF3E4), RGBA(0xFFE8D1)],
        restingBackgroundStops: [RGBA(0xFFF8EF), RGBA(0xFDEEDE)],
        ink: RGBA(0x4A2A1E),
        body: RGBA(0x5A3A2E),
        muted: RGBA(0xB07A5A),
        brand: RGBA(0xC96F4A),
        accentText: RGBA(0xC9502E),
        card: RGBA(0xFFFFFF),
        cardShadow: RGBA(0xC96F4A, 0.12),
        accentSurface: RGBA(0xFFE0C2),
        accentBorder: RGBA(0xFF9E7D),
        onAccentSurface: RGBA(0xA8623E),
        divider: RGBA(0xFFE8D1),
        success: RGBA(0x2A8A6B),
        successSurface: RGBA(0xE3F5EC),
        buttonGradient: [RGBA(0xFF9E7D), RGBA(0xF27A52)],
        buttonShadow: RGBA(0xD95F3A),
        restingButtonGradient: [RGBA(0xFFB36B), RGBA(0xF2905C)],
        restingButtonShadow: RGBA(0xD97A42),
        mutedFlame: RGBA(0xE8CDB8),
        mutedFlameInk: RGBA(0x8A5A42),
        plainFlame: RGBA(0xD9B8A5),
        waitingRing: RGBA(0xF3DDC8),
        toggleOff: RGBA(0xE8D5C5),
        zones: [
            ZonePalette(from: RGBA(0xFFD88A), to: RGBA(0xFFB36B), dimmed: RGBA(0xFFEBD2), dot: RGBA(0xFFD88A)),
            ZonePalette(from: RGBA(0xFF9068), to: RGBA(0xFF7D52), dimmed: RGBA(0xFFD9C2), dot: RGBA(0xFF8A5C)),
            ZonePalette(from: RGBA(0xF78AA8), to: RGBA(0xF06B92), dimmed: RGBA(0xF7C3CF), dot: RGBA(0xF78AA8)),
        ]
    )

    /// Derived, not designed — see the file header.
    static let dark = FlamePalette(
        backgroundStops: [RGBA(0x36221A), RGBA(0x281811)],
        restingBackgroundStops: [RGBA(0x2F1E17), RGBA(0x22140F)],
        ink: RGBA(0xFFF0E0),
        body: RGBA(0xEFD9C7),
        muted: RGBA(0xB9927A),
        brand: RGBA(0xFFAE86),
        accentText: RGBA(0xFF9E7D),
        card: RGBA(0x452B20),
        cardShadow: RGBA(0x000000, 0.35),
        accentSurface: RGBA(0x5A3020),
        accentBorder: RGBA(0xFF9E7D),
        onAccentSurface: RGBA(0xFFC9A5),
        divider: RGBA(0x593628),
        success: RGBA(0x6FD8B0),
        successSurface: RGBA(0x1E4438),
        buttonGradient: [RGBA(0xFF9E7D), RGBA(0xF27A52)],
        buttonShadow: RGBA(0x9E3F22),
        restingButtonGradient: [RGBA(0xFFB36B), RGBA(0xF2905C)],
        restingButtonShadow: RGBA(0xA85A2A),
        mutedFlame: RGBA(0x5E3D2C),
        mutedFlameInk: RGBA(0xC5A085),
        plainFlame: RGBA(0x543527),
        waitingRing: RGBA(0x4C2E22),
        toggleOff: RGBA(0x5A3B2C),
        zones: [
            ZonePalette(from: RGBA(0xFFD88A), to: RGBA(0xFFB36B), dimmed: RGBA(0x513425), dot: RGBA(0xFFD88A)),
            ZonePalette(from: RGBA(0xFF9068), to: RGBA(0xFF7D52), dimmed: RGBA(0x5A3122), dot: RGBA(0xFF8A5C)),
            ZonePalette(from: RGBA(0xF78AA8), to: RGBA(0xF06B92), dimmed: RGBA(0x532834), dot: RGBA(0xF78AA8)),
        ]
    )

    static func of(_ scheme: ColorScheme) -> FlamePalette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Dynamic tokens

enum Theme {
    static func palette(for scheme: ColorScheme) -> FlamePalette { .of(scheme) }

    /// Flat fallback behind the screen gradient, and what `.background` needs
    /// when a colour rather than a view is required.
    static let backgroundBase = dynamic(\.backgroundStops[1])

    static let ink = dynamic(\.ink)
    static let body = dynamic(\.body)
    static let muted = dynamic(\.muted)
    static let brand = dynamic(\.brand)
    static let accentText = dynamic(\.accentText)

    static let card = dynamic(\.card)
    static let cardShadow = dynamic(\.cardShadow)
    static let accentSurface = dynamic(\.accentSurface)
    static let accentBorder = dynamic(\.accentBorder)
    static let onAccentSurface = dynamic(\.onAccentSurface)
    static let divider = dynamic(\.divider)

    /// Success only (§5) — never decoration.
    static let success = dynamic(\.success)
    static let successSurface = dynamic(\.successSurface)

    static let mutedFlame = dynamic(\.mutedFlame)

    static func buttonGradient(_ scheme: ColorScheme, resting: Bool = false) -> LinearGradient {
        let palette = FlamePalette.of(scheme)
        return LinearGradient(
            colors: (resting ? palette.restingButtonGradient : palette.buttonGradient).map(\.color),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func dynamic(_ keyPath: KeyPath<FlamePalette, RGBA>) -> Color {
        Color(uiColor: UIColor { traits in
            let palette = FlamePalette.of(traits.userInterfaceStyle == .dark ? .dark : .light)
            return UIColor(palette[keyPath: keyPath].color)
        })
    }
}

// MARK: - Radii & shape

enum Radius {
    static let card: CGFloat = 24
    static let row: CGFloat = 22
    static let smallCard: CGFloat = 20
    static let button: CGFloat = 26
}
