//
//  Typography.swift
//  Fastino
//
//  Space Grotesk, bundled at three weights (see Resources/Fonts, OFL licensed).
//  The design specifies 400/600/700 only, so those are the three faces we ship —
//  asking for anything else snaps to the nearest of them rather than letting iOS
//  synthesise a smeared bold.
//

import SwiftUI

enum EmberFont {
    enum Weight {
        case regular, semibold, bold

        var faceName: String {
            switch self {
            case .regular: "SpaceGrotesk-Regular"
            case .semibold: "SpaceGrotesk-SemiBold"
            case .bold: "SpaceGrotesk-Bold"
            }
        }
    }
}

extension Font {
    /// Body-ish text: scales with Dynamic Type, relative to the given style.
    static func ember(
        _ size: CGFloat,
        _ weight: EmberFont.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(weight.faceName, size: size, relativeTo: style)
    }

    /// Fixed-size cut, for the few places where growth would break the layout —
    /// the ring's numerals and the pips inside chips and bars.
    static func emberFixed(_ size: CGFloat, _ weight: EmberFont.Weight = .regular) -> Font {
        .custom(weight.faceName, fixedSize: size)
    }
}

// MARK: - Recurring text roles

extension View {
    /// Screen title: 16/700, uppercase, wide tracking, centred (§ handoff type scale).
    func emberScreenTitle() -> some View {
        font(.ember(16, .bold, relativeTo: .headline))
            .tracking(3.5)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
    }

    /// The 11/600 uppercase label that sits above a card's value or a group.
    func emberSectionLabel() -> some View {
        font(.ember(11, .semibold, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(Theme.secondaryText)
    }
}
