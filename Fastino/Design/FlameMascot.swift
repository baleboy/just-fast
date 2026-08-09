//
//  FlameMascot.swift
//  Fastino
//
//  The Flame Friend (§5) — a little flame who lives inside the ring and changes
//  colour and expression with the metabolic zone. Drawn from shapes, not assets,
//  so it stays crisp at every size it's used: 74×86 in the ring, 58×68 resting,
//  38×46 down to 26×31 on the plan cards, 30×34 in the week strip.
//
//  All geometry is expressed as fractions of the 74×86 reference body from the
//  mock, so one component serves every size.
//

import SwiftUI

// MARK: - Blob shape

/// A CSS-style elliptical-corner rounded rectangle: the four horizontal radii as
/// fractions of the width, the four vertical radii as fractions of the height,
/// in the order top-left, top-right, bottom-right, bottom-left.
///
/// This is how the mock builds every flame
/// (`border-radius: 50% 50% 46% 46% / 62% 62% 40% 40%`), so reproducing the rule
/// — including CSS's rescaling when two radii on one edge would overlap — gets
/// the silhouette exactly rather than approximately.
nonisolated struct BlobShape: Shape {
    /// Horizontal radii ÷ width: TL, TR, BR, BL.
    let horizontal: [CGFloat]
    /// Vertical radii ÷ height: TL, TR, BR, BL.
    let vertical: [CGFloat]

    /// The body: a teardrop, widest across the shoulders, tapering to a round base.
    static let body = BlobShape(
        horizontal: [0.50, 0.50, 0.46, 0.46],
        vertical: [0.62, 0.62, 0.40, 0.40]
    )

    /// The little tip that rises off the top of the body.
    static let tip = BlobShape(
        horizontal: [0.50, 0.50, 0.50, 0.50],
        vertical: [0.70, 0.70, 0.32, 0.32]
    )

    /// Circular-arc approximation constant for a quarter ellipse.
    private static let kappa: CGFloat = 0.5523

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return Path() }

        var rx = horizontal.map { $0 * w }
        var ry = vertical.map { $0 * h }

        // CSS shrinks every radius by one common factor when any edge is
        // over-subscribed, which is what keeps the corners smooth.
        let factors = [
            rx[0] + rx[1] > 0 ? w / (rx[0] + rx[1]) : .infinity,   // top
            ry[1] + ry[2] > 0 ? h / (ry[1] + ry[2]) : .infinity,   // right
            rx[3] + rx[2] > 0 ? w / (rx[3] + rx[2]) : .infinity,   // bottom
            ry[0] + ry[3] > 0 ? h / (ry[0] + ry[3]) : .infinity,   // left
        ]
        let scale = min(1, factors.min() ?? 1)
        rx = rx.map { $0 * scale }
        ry = ry.map { $0 * scale }

        let k = Self.kappa
        let x = rect.minX
        let y = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: x + rx[0], y: y))
        path.addLine(to: CGPoint(x: x + w - rx[1], y: y))
        path.addCurve(
            to: CGPoint(x: x + w, y: y + ry[1]),
            control1: CGPoint(x: x + w - rx[1] + k * rx[1], y: y),
            control2: CGPoint(x: x + w, y: y + ry[1] - k * ry[1])
        )
        path.addLine(to: CGPoint(x: x + w, y: y + h - ry[2]))
        path.addCurve(
            to: CGPoint(x: x + w - rx[2], y: y + h),
            control1: CGPoint(x: x + w, y: y + h - ry[2] + k * ry[2]),
            control2: CGPoint(x: x + w - rx[2] + k * rx[2], y: y + h)
        )
        path.addLine(to: CGPoint(x: x + rx[3], y: y + h))
        path.addCurve(
            to: CGPoint(x: x, y: y + h - ry[3]),
            control1: CGPoint(x: x + rx[3] - k * rx[3], y: y + h),
            control2: CGPoint(x: x, y: y + h - ry[3] + k * ry[3])
        )
        path.addLine(to: CGPoint(x: x, y: y + ry[0]))
        path.addCurve(
            to: CGPoint(x: x + rx[0], y: y),
            control1: CGPoint(x: x, y: y + ry[0] - k * ry[0]),
            control2: CGPoint(x: x + rx[0] - k * rx[0], y: y)
        )
        path.closeSubpath()
        return path
    }
}

/// Lets a flame be *outlined* rather than filled — the dashed "today" flame in
/// the week strip needs `strokeBorder`, which only insettable shapes offer.
extension BlobShape: InsettableShape {
    func inset(by amount: CGFloat) -> InsetBlobShape {
        InsetBlobShape(base: self, amount: amount)
    }
}

nonisolated struct InsetBlobShape: InsettableShape {
    let base: BlobShape
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        base.path(in: rect.insetBy(dx: amount, dy: amount))
    }

    func inset(by amount: CGFloat) -> InsetBlobShape {
        InsetBlobShape(base: base, amount: self.amount + amount)
    }
}

// MARK: - Expression

/// What the flame's face is doing. Which one you get is a property of context,
/// not of the mascot: the zone picks it while fasting, the plan card picks it by
/// intensity, and the pilot light is always dozing.
nonisolated enum FlameExpression: Equatable, Sendable {
    /// Wide eyes, open smile.
    case happy
    /// Closed eyes, small smile — the pilot light, content between fasts.
    case dozing
    /// Closed eyes, a tiny flat mouth — the gentlest plan, fast asleep.
    case sleepy
    /// Angled brows over wide eyes, smiling. Fat burn.
    case determined
    /// Steeper brows, flat mouth. The 18:6 plan.
    case focused
    /// Steepest brows, big filled grin. The 20:4 plan.
    case fierce
    /// Brows plus a wider smile. Ketosis.
    case proud

    var browAngle: Double? {
        switch self {
        case .happy, .dozing, .sleepy: nil
        case .determined: 14
        case .proud: 16
        case .focused: 18
        case .fierce: 24
        }
    }

    var hasOpenEyes: Bool { self != .dozing && self != .sleepy }

    /// Mouth width ÷ body width.
    var mouthWidth: CGFloat {
        switch self {
        case .sleepy: 0.09
        case .dozing: 0.16
        case .focused: 0.16
        case .happy, .determined: 0.216
        case .proud: 0.26
        case .fierce: 0.30
        }
    }

    /// A flat bar rather than a smile — focused and dozing don't grin.
    var mouthIsFlat: Bool { self == .focused || self == .sleepy }
    /// A filled half-disc rather than a stroked arc — the warrior's grin.
    var mouthIsFilled: Bool { self == .fierce }
}

// MARK: - Mascot

struct FlameMascot: View {
    /// Height of the body in points. Width follows the 74:86 reference ratio.
    var height: CGFloat
    /// Body gradient, top → bottom. A single-element array fills flat.
    var body_: [Color]
    /// Colour of the tip that rises off the top; `nil` draws no tip.
    var tip: Color?
    /// Face ink. `nil` draws no face at all (the missed days in the week strip).
    var ink: Color?
    var expression: FlameExpression = .happy
    var blush: Bool = false
    /// Idle bob: 3s while fasting, 4.5s at rest, `nil` to hold still.
    var bobDuration: Double? = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobbing = false

    private var width: CGFloat { height * (74.0 / 86.0) }

    var body: some View {
        ZStack {
            if let tip {
                BlobShape.tip
                    .fill(tip)
                    .frame(width: width * 0.351, height: height * 0.349)
                    // Overlaps the body's shoulders rather than floating above
                    // it — the mock's tip starts 16pt *above* an 86pt body, so
                    // their centres are 0.512 of the body's height apart.
                    .offset(y: -height * 0.512)
            }

            BlobShape.body
                .fill(bodyFill)
                .frame(width: width, height: height)

            if let ink {
                face(ink: ink)
            }
        }
        .frame(width: width, height: height)
        .offset(y: bobbing ? -height * 0.07 : 0)
        .onAppear(perform: startBobbing)
        .onChange(of: reduceMotion) { _, _ in startBobbing() }
        .accessibilityHidden(true)
    }

    private var bodyFill: LinearGradient {
        LinearGradient(colors: body_, startPoint: .top, endPoint: .bottom)
    }

    private func startBobbing() {
        guard let bobDuration, !reduceMotion else {
            bobbing = false
            return
        }
        withAnimation(.easeInOut(duration: bobDuration / 2).repeatForever(autoreverses: true)) {
            bobbing = true
        }
    }

    // MARK: Face

    /// Positions are fractions of the 74×86 reference, measured from the mock.
    @ViewBuilder
    private func face(ink: Color) -> some View {
        let eyeW = width * 0.122
        let eyeH = height * 0.140
        let eyeX = width * 0.243 + eyeW / 2
        let eyeY = height * 0.395 + eyeH / 2

        ZStack(alignment: .topLeading) {
            Color.clear

            if let angle = expression.browAngle {
                brow(ink: ink, angle: angle, leading: true)
                brow(ink: ink, angle: -angle, leading: false)
            }

            if expression.hasOpenEyes {
                eye(ink: ink, size: CGSize(width: eyeW, height: eyeH), center: CGPoint(x: eyeX, y: eyeY))
                eye(ink: ink, size: CGSize(width: eyeW, height: eyeH), center: CGPoint(x: width - eyeX, y: eyeY))
            } else {
                closedEye(ink: ink, leading: true)
                closedEye(ink: ink, leading: false)
            }

            mouth(ink: ink)

            if blush {
                blushMark(leading: true)
                blushMark(leading: false)
            }
        }
        .frame(width: width, height: height)
    }

    private func eye(ink: Color, size: CGSize, center: CGPoint) -> some View {
        Ellipse()
            .fill(ink)
            .frame(width: size.width, height: size.height)
            .position(center)
    }

    /// A closed eye is a short curved bar, tilted outward.
    private func closedEye(ink: Color, leading: Bool) -> some View {
        let w = width * 0.135
        let h = max(1.6, height * 0.035)
        return Capsule()
            .fill(ink)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(leading ? 8 : -8))
            .position(x: leading ? width * 0.176 + w / 2 : width - (width * 0.176 + w / 2),
                      y: height * 0.41)
    }

    private func brow(ink: Color, angle: Double, leading: Bool) -> some View {
        let w = width * 0.176
        let h = max(1.8, height * 0.047)
        return Capsule()
            .fill(ink)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(angle))
            .position(x: leading ? width * 0.216 + w / 2 : width - (width * 0.216 + w / 2),
                      y: height * 0.302 + h / 2)
    }

    @ViewBuilder
    private func mouth(ink: Color) -> some View {
        let w = width * expression.mouthWidth
        let h = w * 0.5
        let stroke = max(1.5, width * 0.041)
        let centre = CGPoint(x: width / 2, y: height * 0.605 + h / 2)

        if expression.mouthIsFlat {
            Capsule()
                .fill(ink)
                .frame(width: w, height: stroke)
                .position(centre)
        } else if expression.mouthIsFilled {
            // A half-disc: the bottom half of an ellipse, flat side up.
            HalfDisc()
                .fill(ink)
                .frame(width: w, height: h)
                .position(centre)
        } else {
            SmileArc()
                .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: w, height: h)
                .position(centre)
        }
    }

    private func blushMark(leading: Bool) -> some View {
        let w = width * 0.135
        let h = height * 0.070
        return Ellipse()
            .fill(Color(hex: 0xFF785A, opacity: 0.55))
            .frame(width: w, height: h)
            .position(x: leading ? width * 0.108 + w / 2 : width - (width * 0.108 + w / 2),
                      y: height * 0.512 + h / 2)
    }
}

/// The bottom half of an ellipse, drawn as a stroke — the open smile.
private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
        )
        return path
    }
}

/// The same shape, filled — the warrior's grin.
private struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Ready-made mascots

extension FlameMascot {
    /// The mascot as it appears mid-fast: the current zone's colours and face.
    static func inZone(
        _ zone: MetabolicZone,
        palette: FlamePalette,
        height: CGFloat,
        showsTip: Bool = true,
        blush: Bool = true,
        bobDuration: Double? = 3
    ) -> FlameMascot {
        let colors = palette.zones[zone.rawValue]
        // The tip is always a shade lighter than the body it rises from: the
        // previous zone's warm end, or — in the first zone, which has nothing
        // before it — its own pale gold.
        let tipColor = zone == .burning
            ? palette.zones[0].from.color
            : palette.zones[zone.rawValue - 1].to.color
        return FlameMascot(
            height: height,
            body_: [colors.from.color, colors.to.color],
            tip: showsTip ? tipColor : nil,
            ink: palette.ink.color,
            expression: zone.expression,
            blush: blush,
            bobDuration: bobDuration
        )
    }

    /// The pilot light: pale, eyes closed, breathing slowly.
    static func pilotLight(palette: FlamePalette, height: CGFloat) -> FlameMascot {
        FlameMascot(
            height: height,
            body_: [Color(hex: 0xFFD3A8), Color(hex: 0xFFB98A)],
            tip: nil,
            ink: palette.ink.color,
            expression: .dozing,
            blush: true,
            bobDuration: 4.5
        )
    }

    /// A small lit flame — the week strip's goal days and the record card's corner.
    static func lit(palette: FlamePalette, height: CGFloat, animated: Bool = false) -> FlameMascot {
        FlameMascot(
            height: height,
            body_: [Color(hex: 0xFFB36B), Color(hex: 0xFF8A5C)],
            tip: nil,
            ink: palette.ink.color,
            expression: .happy,
            bobDuration: animated ? 3 : nil
        )
    }

    /// An unlit flame with no face — a day with nothing logged.
    static func unlit(palette: FlamePalette, height: CGFloat) -> FlameMascot {
        FlameMascot(
            height: height,
            body_: [palette.plainFlame.color],
            tip: nil,
            ink: nil,
            bobDuration: nil
        )
    }
}

extension MetabolicZone {
    /// The face the flame pulls in this zone.
    var expression: FlameExpression {
        switch self {
        case .burning: .happy
        case .fatBurn: .determined
        case .ketosis: .proud
        }
    }
}

#Preview("Mascots") {
    let palette = FlamePalette.light
    return ZStack {
        LinearGradient(colors: palette.backgroundStops.map(\.color), startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack(spacing: 40) {
            HStack(spacing: 30) {
                FlameMascot.inZone(.burning, palette: palette, height: 86)
                FlameMascot.inZone(.fatBurn, palette: palette, height: 86)
                FlameMascot.inZone(.ketosis, palette: palette, height: 86)
            }
            HStack(spacing: 24) {
                FlameMascot.pilotLight(palette: palette, height: 68)
                FlameMascot(height: 46, body_: [palette.mutedFlame.color], tip: nil,
                            ink: palette.mutedFlameInk.color, expression: .fierce, bobDuration: nil)
                FlameMascot(height: 41, body_: [palette.mutedFlame.color], tip: nil,
                            ink: palette.mutedFlameInk.color, expression: .focused, bobDuration: nil)
                FlameMascot(height: 31, body_: [palette.mutedFlame.color], tip: nil,
                            ink: palette.mutedFlameInk.color, expression: .dozing, bobDuration: nil)
            }
            HStack(spacing: 16) {
                FlameMascot.lit(palette: palette, height: 34)
                FlameMascot.unlit(palette: palette, height: 34)
            }
        }
    }
}
