//
//  FlameChrome.swift
//  Fastino
//
//  The shared surfaces of the Flame Friend system (§5): the warm screen
//  gradient, the soft white card, the chunky 3D-press button, and the pill
//  toggle. Everything is rounded, nothing is sharp.
//

import SwiftUI

// MARK: - Screen background

/// The peach gradient behind every screen. The eating window uses the calmer
/// `resting` variant, which is the same idea a shade quieter — the fire is out.
struct FlameBackground: View {
    var resting: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let stops = resting ? palette.restingBackgroundStops : palette.backgroundStops
        Rectangle()
            .fill(LinearGradient(colors: stops.map(\.color), startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: resting)
    }
}

// MARK: - Cards

extension View {
    /// The standard card: white, generously rounded, with a warm soft shadow.
    /// `fill`/`border` carry the selected state (peach surface + 2.5pt border).
    func flameCard(
        radius: CGFloat = Radius.card,
        fill: Color? = nil,
        border: Color? = nil,
        borderWidth: CGFloat = 2.5
    ) -> some View {
        modifier(FlameCard(radius: radius, fill: fill, border: border, borderWidth: borderWidth))
    }
}

private struct FlameCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    let fill: Color?
    let border: Color?
    let borderWidth: CGFloat

    func body(content: Content) -> some View {
        let palette = Theme.palette(for: colorScheme)
        content
            .background(
                (fill ?? palette.card.color)
                    // A selected card carries its own border instead of a shadow,
                    // exactly as in the mock — it sits *on* the page, not above it.
                    .shadow(.drop(
                        color: border == nil ? palette.cardShadow.color : .clear,
                        radius: 7,
                        y: 4
                    )),
                in: .rect(cornerRadius: radius)
            )
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(border, lineWidth: borderWidth)
                }
            }
    }
}

// MARK: - Primary button

/// Full-width gradient pill with a **hard 3D shadow** — a solid colour offset
/// straight down, no blur. Pressing moves the cap down onto it, which is where
/// the toy-like feel of this direction comes from.
struct FlamePrimaryButton: View {
    let title: String
    var resting: Bool = false
    /// The celebration state: goal reached, so the action reads as banking a win.
    var celebrating: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Button(action: action) {
            Text(title)
                .font(.flame(19, .extraBold, relativeTo: .headline))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(palette.buttonLabel.color)
        }
        .buttonStyle(
            HardShadowButtonStyle(
                gradient: gradient(palette),
                shadow: shadowColor(palette)
            )
        )
        .animation(.snappy(duration: 0.3), value: celebrating)
    }

    private func gradient(_ palette: FlamePalette) -> LinearGradient {
        if celebrating {
            return LinearGradient(
                colors: [palette.success.color.opacity(0.92), palette.success.color],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return Theme.buttonGradient(colorScheme, resting: resting)
    }

    private func shadowColor(_ palette: FlamePalette) -> Color {
        if celebrating {
            return palette.success.color.opacity(colorScheme == .dark ? 0.55 : 0.75)
        }
        return (resting ? palette.restingButtonShadow : palette.buttonShadow).color
    }
}

/// The press: the cap travels down 3pt and the shadow shrinks to match, so the
/// two always add up to the same height and the button looks physically pushed.
struct HardShadowButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    let shadow: Color

    private let depth: CGFloat = 6
    private let travel: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(gradient, in: .rect(cornerRadius: Radius.button))
            .background(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.button)
                    .fill(shadow)
                    .offset(y: pressed ? depth - travel : depth)
            }
            .offset(y: pressed ? travel : 0)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .padding(.bottom, depth)
    }
}

/// Press feedback for cards and rows, which don't get the 3D treatment.
struct FlamePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Toggle

/// 48×29 pill: on = warm gradient with the knob right, off = neutral tint with
/// the knob left. The knob keeps its own small shadow in both states.
struct FlameToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn
                      ? AnyShapeStyle(LinearGradient(
                          colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF8A5C)],
                          startPoint: .leading,
                          endPoint: .trailing))
                      : AnyShapeStyle(palette.toggleOff.color))
                .frame(width: 48, height: 29)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.white : palette.toggleKnobOff.color)
                        .frame(width: 23, height: 23)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
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

// MARK: - Success chip

/// The green pill that reports a streak or a met goal. Green is success-only (§5).
struct SuccessChip: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Text(text)
            .font(.flame(13, .extraBold, relativeTo: .footnote))
            .foregroundStyle(palette.success.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(palette.successSurface.color, in: .capsule)
    }
}
