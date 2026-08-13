//
//  Typography.swift
//  Fastino
//
//  Baloo 2, bundled at the three weights the design uses (see Resources/Fonts,
//  OFL licensed, subset to Latin). Everything in Flame Friend is rounded and
//  chunky — 600 is the lightest thing on screen.
//

import SwiftUI

enum FlameFont {
    enum Weight {
        case semibold   // 600 — captions, subtitles
        case bold       // 700 — inactive labels
        case extraBold  // 800 — headings, numbers, everything that matters

        var faceName: String {
            switch self {
            case .semibold: "Baloo2-SemiBold"
            case .bold: "Baloo2-Bold"
            case .extraBold: "Baloo2-ExtraBold"
            }
        }
    }
}

extension Font {
    /// Scales with Dynamic Type, relative to the given style.
    static func flame(
        _ size: CGFloat,
        _ weight: FlameFont.Weight = .semibold,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(weight.faceName, size: size, relativeTo: style)
    }

    /// Fixed-size cut, for the few places where growth would break the layout —
    /// text inside the ring, and the labels on the little flames.
    static func flameFixed(_ size: CGFloat, _ weight: FlameFont.Weight = .semibold) -> Font {
        .custom(weight.faceName, fixedSize: size)
    }
}

// MARK: - Recurring text roles

extension View {
    /// Screen title: 26/800 in ink, left-aligned (Stats, Settings).
    func flameScreenTitle() -> some View {
        font(.flame(26, .extraBold, relativeTo: .title))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The 12–13/800 uppercase label above a card's value or a settings group.
    func flameSectionLabel(_ color: Color = Theme.muted) -> some View {
        font(.flame(12, .extraBold, relativeTo: .caption2))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}
