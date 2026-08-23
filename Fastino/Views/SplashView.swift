//
//  SplashView.swift
//  Fastino
//
//  The launch screen (§5): the app's own mark — the mascot lighting up over the
//  lowercase wordmark — with the Baleware lockup underneath. It sits inside
//  `RootView`'s stack rather than above it in `FastinoApp` so it inherits the
//  appearance override and the same background the app opens onto; the fade
//  therefore reveals the running app rather than cutting to it.
//

import SwiftUI
import UIKit

/// Baleware's mark: six equal stripes, green at the top through to blue, as a
/// small rounded square. Taken from baleware.com's favicon, and fixed in both
/// schemes — it's someone else's identity, not a token of ours to re-tint.
struct BalewareMark: View {
    var size: CGFloat = 22

    /// Top to bottom, as drawn on the site.
    private static let stripes: [Color] = [
        Color(hex: 0x61BB46),   // green
        Color(hex: 0xFDB827),   // yellow
        Color(hex: 0xF5821F),   // orange
        Color(hex: 0xE03A3E),   // red
        Color(hex: 0x963D97),   // purple
        Color(hex: 0x009DDC),   // blue
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.stripes.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The publisher lockup: mark + wordmark, set in Baleware's own face rather
/// than the app's — the one place in Fastino that isn't Baloo 2, deliberately.
///
/// The site declares `"American Typewriter", "Courier New", Courier, monospace`,
/// and iOS resolves that chain differently than a Mac does: American Typewriter
/// is a *downloadable* iOS font, not a resident one, so asking for it by name
/// silently yields the system face — which on this screen means the wordmark
/// quietly renders in the app's own font and stops being Baleware's. So walk
/// the brand's own fallback list and take the first face that actually exists.
struct BalewareLockup: View {
    /// In the site's order. `Courier New` is resident on iOS, so the chain
    /// always terminates before the system fallback.
    private static let brandFaces = [
        "AmericanTypewriter-Bold",
        "CourierNewPS-BoldMT",
        "Courier-Bold",
    ]

    private static let brandFace: String? = brandFaces.first { UIFont(name: $0, size: 17) != nil }

    var body: some View {
        HStack(spacing: 8) {
            BalewareMark()
            Text("baleware")
                .font(Self.brandFace.map { .custom($0, fixedSize: 16) } ?? .flameFixed(17, .bold))
                .foregroundStyle(Theme.body)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("By Baleware")
    }
}

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the one piece of motion: the flame growing into place. Under
    /// Reduce Motion it starts settled and only the fade remains.
    @State private var lit = false

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ZStack {
            // The resting stops, not the active ones: the app has no idea yet
            // whether a fast is running, and the calmer gradient is the one it
            // can cross-fade out of without a visible jump either way.
            FlameBackground(resting: true)

            VStack(spacing: 0) {
                Spacer()

                // `.inZone(.burning)` rather than `.lit`: the small lit flame
                // has no tip, which at this size reads as an egg rather than a
                // flame. The first zone is also the honest one to open on — it
                // is what the app looks like the moment a fast begins.
                FlameMascot.inZone(
                    .burning,
                    palette: palette,
                    height: 132,
                    bobDuration: reduceMotion ? nil : 3
                )
                    .scaleEffect(lit ? 1 : 0.86)
                    .opacity(lit ? 1 : 0)

                Text("fastino")
                    .font(.flame(34, .extraBold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 18)
                    .opacity(lit ? 1 : 0)

                Spacer()

                VStack(spacing: 10) {
                    Text("by")
                        .flameSectionLabel()
                    BalewareLockup()
                }
                .opacity(lit ? 1 : 0)
                .padding(.bottom, 44)
            }
            .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { lit = true; return }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) { lit = true }
        }
        // One element, one announcement — VoiceOver shouldn't walk a screen
        // that's about to disappear.
        .accessibilityElement(children: .contain)
    }
}

#Preview("Light") {
    SplashView().preferredColorScheme(.light)
}

#Preview("Dark") {
    SplashView().preferredColorScheme(.dark)
}
