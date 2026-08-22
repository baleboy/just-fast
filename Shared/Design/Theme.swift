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
//  Both schemes come from the handoff (light 4a/5a/5b/6a, dark 7a/7b/7c — "cozy
//  campfire night"). Dark isn't a tint of light: cards become translucent warm
//  film with no drop shadow, and everything lit — mascot, ring, bars, the
//  progress dot — earns a glow it doesn't have in daylight.
//

import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

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
    /// The tab bar and the zone beads sit a touch above the cards in dark; the
    /// same white in light.
    let elevated: RGBA
    /// Transparent in dark, where cards separate by their own fill instead.
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

    /// Face ink on a *lit* flame. Not `ink` — the face has to read against the
    /// flame's own colour, which is warm in both schemes.
    let flameInk: RGBA
    /// Unlit mascot fill (with a face) and the ink used on it.
    let mutedFlame: RGBA
    let mutedFlameInk: RGBA
    /// Label on a zone bead that isn't the active one.
    let beadLabel: RGBA
    /// A day with no fast, in the Stats histogram.
    let chartNeutral: RGBA
    /// Text on the primary button.
    let buttonLabel: RGBA
    /// Fill of the ring's progress dot.
    let dotFill: RGBA
    /// Halo around lit things — mascot, ring, bars, dot. Clear in light: the
    /// glow is what makes the dark scheme a campfire rather than an inversion.
    let glow: RGBA
    /// The dot on a zone bead you haven't reached yet.
    let idleDot: RGBA
    /// The dashed circle of the waiting ring.
    let waitingRing: RGBA
    /// Off state of a toggle, and the knob that sits on it.
    let toggleOff: RGBA
    let toggleKnobOff: RGBA

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
        elevated: RGBA(0xFFFFFF),
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
        flameInk: RGBA(0x4A2A1E),
        mutedFlame: RGBA(0xE8CDB8),
        mutedFlameInk: RGBA(0x8A5A42),
        beadLabel: RGBA(0x8A5A42),
        chartNeutral: RGBA(0x5A3A2E, 0.1),
        buttonLabel: RGBA(0xFFFFFF),
        dotFill: RGBA(0xFFFFFF),
        glow: RGBA(0xFF7D52, 0),
        idleDot: RGBA(0xD9B8A5),
        waitingRing: RGBA(0xF3DDC8),
        toggleOff: RGBA(0xE8D5C5),
        toggleKnobOff: RGBA(0xFFFFFF),
        zones: [
            ZonePalette(from: RGBA(0xFFD88A), to: RGBA(0xFFB36B), dimmed: RGBA(0xFFEBD2), dot: RGBA(0xFFD88A)),
            ZonePalette(from: RGBA(0xFF9068), to: RGBA(0xFF7D52), dimmed: RGBA(0xFFD9C2), dot: RGBA(0xFF8A5C)),
            ZonePalette(from: RGBA(0xF78AA8), to: RGBA(0xF06B92), dimmed: RGBA(0xF7C3CF), dot: RGBA(0xF78AA8)),
        ]
    )

    /// "Cozy campfire night" (handoff 7a/7b/7c). The eating window's dark
    /// variant wasn't drawn, so it reuses these stops — the handoff says to
    /// derive it from the light 6a with the dark tokens, and the calmer light
    /// background has no dark counterpart to be calmer *than*.
    static let dark = FlamePalette(
        backgroundStops: [RGBA(0x2B1A12), RGBA(0x211107)],
        restingBackgroundStops: [RGBA(0x2B1A12), RGBA(0x211107)],
        ink: RGBA(0xFFF3E4),
        body: RGBA(0xF5DFC8),
        muted: RGBA(0xC99A7D),
        brand: RGBA(0xFFB98A),
        accentText: RGBA(0xFFB98A),
        card: RGBA(0xFFDCB4, 0.07),
        elevated: RGBA(0xFFDCB4, 0.08),
        cardShadow: RGBA(0x000000, 0),
        accentSurface: RGBA(0xFF7D52, 0.16),
        accentBorder: RGBA(0xFF9E7D),
        onAccentSurface: RGBA(0xE8A583),
        divider: RGBA(0xFFDCB4, 0.12),
        success: RGBA(0x6FD8B0),
        successSurface: RGBA(0x6FD8B0, 0.14),
        buttonGradient: [RGBA(0xFF9E7D), RGBA(0xF27A52)],
        buttonShadow: RGBA(0xA8431F),
        restingButtonGradient: [RGBA(0xFFB36B), RGBA(0xF2905C)],
        restingButtonShadow: RGBA(0xA85A2A),
        flameInk: RGBA(0x3A1C10),
        mutedFlame: RGBA(0x6B4A38),
        mutedFlameInk: RGBA(0x2B1A12),
        beadLabel: RGBA(0xE8C4A0),
        chartNeutral: RGBA(0xFFDCB4, 0.1),
        buttonLabel: RGBA(0x3A1505),
        dotFill: RGBA(0x3A2418),
        glow: RGBA(0xFF7D52, 0.5),
        idleDot: RGBA(0xA87E68),
        waitingRing: RGBA(0xFFDCB4, 0.14),
        toggleOff: RGBA(0xFFDCB4, 0.14),
        toggleKnobOff: RGBA(0xC9A88A),
        zones: [
            ZonePalette(from: RGBA(0xFFD88A), to: RGBA(0xFFB36B), dimmed: RGBA(0xFFD88A, 0.18), dot: RGBA(0xFFD88A)),
            ZonePalette(from: RGBA(0xFF9068), to: RGBA(0xFF7D52), dimmed: RGBA(0xFFB482, 0.18), dot: RGBA(0xFF8A5C)),
            ZonePalette(from: RGBA(0xF78AA8), to: RGBA(0xF06B92), dimmed: RGBA(0xF78AA8, 0.2), dot: RGBA(0xF78AA8)),
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
    static let elevated = dynamic(\.elevated)
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
        #if os(watchOS)
        // watchOS has no light appearance, and no UITraitCollection to resolve
        // against — so the "cozy campfire night" palette resolves statically.
        // Appearance in Settings is an iOS-only control by the same logic.
        FlamePalette.of(.dark)[keyPath: keyPath].color
        #else
        Color(uiColor: UIColor { traits in
            let palette = FlamePalette.of(traits.userInterfaceStyle == .dark ? .dark : .light)
            return UIColor(palette[keyPath: keyPath].color)
        })
        #endif
    }
}

// MARK: - Radii & shape

enum Radius {
    static let card: CGFloat = 24
    static let row: CGFloat = 22
    static let smallCard: CGFloat = 20
    static let button: CGFloat = 26
    /// Rows on the watch are half the height of the phone's, so the phone radii
    /// round them all the way into capsules. This keeps them reading as cards.
    static let watchRow: CGFloat = 12
}
