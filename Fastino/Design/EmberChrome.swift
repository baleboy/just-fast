//
//  EmberChrome.swift
//  Fastino
//
//  The shared surfaces of the Ember system (§5): the radial screen background,
//  the card treatment (translucent + hairline border in dark, white + soft
//  shadow in light), and the primary gradient pill button.
//

import SwiftUI

// MARK: - Screen background

/// `radial-gradient(120% 80% at 50% 0%, …)` — the glow sits above the ring and
/// falls away to near-black (or warm paper) at the bottom of the screen.
struct EmberBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        // A Rectangle, not a bare GeometryReader: this is used as a `.background`
        // and as a ZStack layer, and a GeometryReader on its own collapses to its
        // ideal size in both — which is how you get a black screen.
        Rectangle()
            .fill(palette.backgroundStops[2].color)
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    RadialGradient(
                        stops: [
                            .init(color: palette.backgroundStops[0].color, location: 0),
                            .init(color: palette.backgroundStops[1].color, location: 0.55),
                            .init(color: palette.backgroundStops[2].color, location: 1),
                        ],
                        center: .init(x: 0.5, y: 0),
                        startRadius: 0,
                        // The CSS ellipse is 120% wide × 80% tall; SwiftUI only
                        // offers a circular radial, so we take the larger of the
                        // two and let the corners resolve to the outer stop.
                        endRadius: max(size.width * 0.6, size.height * 0.8)
                    )
                }
            }
            .ignoresSafeArea()
    }
}

// MARK: - Cards

extension View {
    /// The standard card: fill, hairline border, and (light mode only) a soft
    /// drop shadow. `glow` lights the card from within for selected/active state.
    func emberCard(
        radius: CGFloat = Radius.card,
        fill: Color? = nil,
        border: Color? = nil,
        glow: Color? = nil
    ) -> some View {
        modifier(EmberCard(radius: radius, fill: fill, border: border, glow: glow))
    }
}

private struct EmberCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    let fill: Color?
    let border: Color?
    let glow: Color?

    func body(content: Content) -> some View {
        let palette = Theme.palette(for: colorScheme)
        content
            .background((fill ?? palette.cardBackground.color).shadow(.drop(
                color: glow ?? palette.cardShadow.color,
                radius: glow == nil ? 7 : 12,
                y: glow == nil ? 4 : 0
            )), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(border ?? palette.cardBorder.color, lineWidth: 1)
            }
    }
}

// MARK: - Primary button

/// Full-width gradient pill — one per screen, always the single next action.
struct EmberPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let action: () -> Void

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Button(action: action) {
            Text(title)
                .font(.ember(18, .bold, relativeTo: .headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .foregroundStyle(colorScheme == .dark ? Color(hex: 0x2A1206) : Color(hex: 0x3A1A05))
                .background(Theme.heatGradient(colorScheme), in: .capsule)
                .shadow(color: palette.accent.alpha(0.4).color, radius: 15, y: 6)
        }
        .buttonStyle(EmberPressStyle())
    }
}

/// Platform-standard press feedback, since the mocks only cover active/selected.
struct EmberPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Toggle

/// 46×28 pill: on = heat gradient with the knob right, off = neutral tint with
/// the knob left.
struct EmberToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn
                      ? AnyShapeStyle(Theme.heatGradient(colorScheme))
                      : AnyShapeStyle(palette.mutedFill.color))
                .frame(width: 46, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.white : palette.mutedKnob.color)
                        .frame(width: 22, height: 22)
                        .padding(.horizontal, 3)
                }
                .contentShape(.capsule)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
                }
                .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
        }
    }
}
