//
//  FlameRing.swift
//  Fastino
//
//  The ring the mascot sits inside (§4.1, §5). Its colour bands *are* the
//  metabolic zones: the colour ramps inside a band and jumps at a boundary, the
//  part you've burned through is saturated, and the part still ahead is that
//  zone's colour in a pale preview tint. A white dot rides the fill edge.
//
//  Between fasts it becomes the waiting ring: a dashed circle, no fill, no dot.
//
//  Motion (handoff turn 3): the fill sweeps 0 → current over 1.8s ease-out on
//  appear, and a ring flash expands on ignite and at each zone crossing.
//

import SwiftUI

struct FlameRing: View {
    enum Content: Equatable {
        /// A running (or finished) fast: full zone bands plus the progress dot.
        case fast(goalHours: Int, elapsed: TimeInterval)
        /// Between fasts, or never started — the dashed waiting ring.
        case waiting
    }

    let content: Content
    var diameter: CGFloat = 310
    /// Drives the launch sweep: the fill is multiplied by this. Held at 1 by
    /// callers that don't animate.
    var fillScale: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    /// The mock masks at 78%/79% of the ring's radius — a ~32pt stroke at 310.
    private var thickness: CGFloat { diameter * 0.5 * 0.215 }
    private var dotSize: CGFloat { diameter * (32.0 / 310.0) }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        ZStack {
            switch content {
            case let .fast(goalHours, elapsed):
                // Dark only: a blurred copy of the *burned* arc sitting behind
                // the ring, so the fire throws light onto the night background.
                if palette.glow.a > 0 {
                    band(stops: zoneStops(palette, goalHours: goalHours, elapsed: elapsed, glowOnly: true))
                        .blur(radius: diameter * (24.0 / 310.0))
                        .opacity(0.35)
                }
                band(stops: zoneStops(palette, goalHours: goalHours, elapsed: elapsed))
                progressDot(palette, goalHours: goalHours, elapsed: elapsed)
            case .waiting:
                Circle()
                    .strokeBorder(
                        palette.waitingRing.color,
                        style: StrokeStyle(lineWidth: 8, dash: [14, 12], dashPhase: 0)
                    )
                    .padding(6)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func band(stops: [Gradient.Stop]) -> some View {
        AngularGradient(gradient: Gradient(stops: stops), center: .center, angle: .degrees(-90))
            .mask {
                Circle()
                    .inset(by: thickness / 2)
                    .stroke(lineWidth: thickness)
            }
    }

    /// A white disc with a 4pt ring in the active zone's colour, centred on the
    /// track at the fill angle. It's the only hard edge on the screen, which is
    /// what makes it read as "you are here".
    @ViewBuilder
    private func progressDot(_ palette: FlamePalette, goalHours: Int, elapsed: TimeInterval) -> some View {
        let fraction = filled(goalHours: goalHours, elapsed: elapsed)
        let zone = MetabolicZone.current(elapsed: elapsed * fillScale)
        Circle()
            .fill(palette.dotFill.color)
            .frame(width: dotSize, height: dotSize)
            .overlay {
                Circle().strokeBorder(palette.zones[zone.rawValue].to.color, lineWidth: 4)
            }
            // In light it's a lifted white disc; in dark it's a dark disc with a
            // ring of fire around it, so the shadow becomes a glow.
            .shadow(
                color: palette.glow.a > 0 ? palette.glow.alpha(0.6).color : palette.cardShadow.alpha(0.3).color,
                radius: palette.glow.a > 0 ? 8 : 5,
                y: palette.glow.a > 0 ? 0 : 3
            )
            .offset(y: -(diameter - thickness) / 2)
            .rotationEffect(.degrees(fraction * 360))
    }

    // MARK: - Gradient construction

    /// Half of the ~4° soft transition either side of a zone boundary. Without it
    /// the hard colour jump aliases into a visible staircase.
    private static let boundarySoftening = 2.0 / 360.0

    /// How much of the circle is burned through, 0…1.
    private func filled(goalHours: Int, elapsed: TimeInterval) -> Double {
        let goal = max(Double(goalHours), 1)
        return min(max(elapsed / 3600 / goal, 0), 1) * min(max(fillScale, 0), 1)
    }

    /// `glowOnly` drops everything you haven't burned yet, leaving just the lit
    /// arc for the blurred halo layer.
    private func zoneStops(
        _ palette: FlamePalette,
        goalHours: Int,
        elapsed: TimeInterval,
        glowOnly: Bool = false
    ) -> [Gradient.Stop] {
        let goal = max(Double(goalHours), 1)
        let burned = filled(goalHours: goalHours, elapsed: elapsed) * goal
        let soft = Self.boundarySoftening

        var stops: [Gradient.Stop] = []
        let spans = MetabolicZone.allCases.compactMap { zone -> (MetabolicZone, ClosedRange<Double>)? in
            zone.span(forGoalHours: goalHours).map { (zone, $0) }
        }

        for (index, entry) in spans.enumerated() {
            let (zone, span) = entry
            let colors = palette.zones[zone.rawValue]
            let start = span.lowerBound / goal
            let end = span.upperBound / goal
            let lo = index == 0 ? start : start + soft
            let hi = index == spans.count - 1 ? end : end - soft

            if burned >= span.upperBound {
                stops.append(.init(color: colors.from.color, location: lo))
                stops.append(.init(color: colors.to.color, location: hi))
            } else if burned <= span.lowerBound {
                // Unreached: a flat pale preview of the zone, not a gradient —
                // the ramp is the reward for getting there.
                let unreached = glowOnly ? Color.clear : colors.dimmed.color
                stops.append(.init(color: unreached, location: lo))
                stops.append(.init(color: unreached, location: hi))
            } else {
                let t = (burned - span.lowerBound) / (span.upperBound - span.lowerBound)
                let split = min(max(start + (end - start) * t, lo), hi)
                let unreached = glowOnly ? Color.clear : colors.dimmed.color
                stops.append(.init(color: colors.from.color, location: lo))
                stops.append(.init(color: RGBA.mix(colors.from, colors.to, t).color, location: split))
                stops.append(.init(color: unreached, location: split))
                stops.append(.init(color: unreached, location: hi))
            }
        }
        return normalize(stops)
    }

    /// Clamp into 0…1 and keep locations non-decreasing — a short goal can push a
    /// softened boundary past the one after it, and `Gradient` renders garbage if
    /// the stops go backwards.
    private func normalize(_ stops: [Gradient.Stop]) -> [Gradient.Stop] {
        var last = 0.0
        return stops.map { stop in
            let location = min(max(stop.location, last), 1)
            last = location
            return Gradient.Stop(color: stop.color, location: location)
        }
    }
}

// MARK: - Ring flash

/// The expanding ring used for ignite (start of a fast) and for each zone
/// crossing: a stroked circle that grows past the ring and fades out.
struct RingFlash: View {
    let color: Color
    let diameter: CGFloat
    /// 0 → 1 over the life of the flash.
    let progress: Double

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 10 * (1 - progress) + 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(1 + progress * 0.22)
            .opacity(1 - progress)
            .allowsHitTesting(false)
    }
}

#Preview("Ring") {
    ZStack {
        FlameBackground()
        VStack(spacing: 30) {
            FlameRing(content: .fast(goalHours: 16, elapsed: 12.85 * 3600), diameter: 260)
            FlameRing(content: .waiting, diameter: 180)
        }
    }
}
