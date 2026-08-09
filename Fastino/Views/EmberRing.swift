//
//  EmberRing.swift
//  Fastino
//
//  The signature element (§4.1, §5): a donut whose colour bands *are* the
//  metabolic zones. Inside a band the colour ramps; at a band boundary it jumps.
//  The part of the ring you've already burned through is at full opacity and the
//  part still ahead of you is the same colours dimmed — the opacity edge is the
//  progress indicator, so there's no dot or cap to draw.
//
//  A blurred copy of the elapsed-only gradient sits behind it: that's the ember
//  glow, and it's why the ring reads as lit rather than printed.
//

import SwiftUI

struct EmberRing: View {
    enum Content: Equatable {
        /// A running (or finished) fast: full zone bands.
        case fast(goalHours: Int, elapsed: TimeInterval)
        /// Between fasts, or never started. The fire is out, so this is a single
        /// quiet arc over a cold track rather than the heat scale.
        case resting(progress: Double)
    }

    let content: Content
    var diameter: CGFloat = 312

    @Environment(\.colorScheme) private var colorScheme

    /// 10px at the design's 312px ring — the glow needs room to bleed.
    private var inset: CGFloat { diameter * (10.0 / 312.0) }
    private var outerDiameter: CGFloat { diameter - inset * 2 }
    /// Matches the mock's `radial-gradient(closest-side, transparent 74%, …)` mask.
    private var thickness: CGFloat { outerDiameter * 0.127 }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        ZStack {
            band(stops: glowStops(palette))
                .blur(radius: diameter * (26.0 / 312.0))
                .opacity(colorScheme == .dark ? 0.5 : 0.35)

            band(stops: stops(palette))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.5), value: colorScheme)
    }

    private func band(stops: [Gradient.Stop]) -> some View {
        AngularGradient(gradient: Gradient(stops: stops), center: .center, angle: .degrees(-90))
            .mask {
                Circle()
                    .inset(by: inset + thickness / 2)
                    .stroke(lineWidth: thickness)
            }
    }

    // MARK: - Gradient construction

    /// Half of the ~4° soft transition either side of a zone boundary, expressed
    /// as a fraction of the circle. Without it the hard colour jump aliases into
    /// a visible staircase.
    private static let boundarySoftening = 2.0 / 360.0

    private func stops(_ palette: EmberPalette) -> [Gradient.Stop] {
        switch content {
        case let .fast(goalHours, elapsed):
            return zoneStops(palette, goalHours: goalHours, elapsed: elapsed, glowOnly: false)
        case let .resting(progress):
            return restingStops(palette, progress: progress, glowOnly: false)
        }
    }

    /// The glow layer only carries the *burned* part of the ring — a halo around
    /// what's still ahead of you would defeat the point.
    private func glowStops(_ palette: EmberPalette) -> [Gradient.Stop] {
        switch content {
        case let .fast(goalHours, elapsed):
            return zoneStops(palette, goalHours: goalHours, elapsed: elapsed, glowOnly: true)
        case let .resting(progress):
            return restingStops(palette, progress: progress, glowOnly: true)
        }
    }

    private func zoneStops(
        _ palette: EmberPalette,
        goalHours: Int,
        elapsed: TimeInterval,
        glowOnly: Bool
    ) -> [Gradient.Stop] {
        let goal = max(Double(goalHours), 1)
        // Past the goal the whole ring is lit; it never wraps round a second time.
        let burned = min(max(elapsed / 3600, 0), goal)
        let clear = Color.clear
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

            let full = (from: colors.from, to: colors.to)
            let dim = (
                from: colors.from.alpha(palette.zoneDimAlpha.low),
                to: colors.to.alpha(palette.zoneDimAlpha.high)
            )

            func dimColor(_ rgba: RGBA) -> Color { glowOnly ? clear : rgba.color }

            if burned >= span.upperBound {
                stops.append(.init(color: full.from.color, location: lo))
                stops.append(.init(color: full.to.color, location: hi))
            } else if burned <= span.lowerBound {
                stops.append(.init(color: dimColor(dim.from), location: lo))
                stops.append(.init(color: dimColor(dim.to), location: hi))
            } else {
                let t = (burned - span.lowerBound) / (span.upperBound - span.lowerBound)
                let split = min(max(start + (end - start) * t, lo), hi)
                stops.append(.init(color: full.from.color, location: lo))
                stops.append(.init(color: RGBA.mix(full.from, full.to, t).color, location: split))
                stops.append(.init(color: glowOnly ? clear : RGBA.mix(dim.from, dim.to, t).color, location: split))
                stops.append(.init(color: dimColor(dim.to), location: hi))
            }
        }
        return normalize(stops)
    }

    private func restingStops(
        _ palette: EmberPalette,
        progress: Double,
        glowOnly: Bool
    ) -> [Gradient.Stop] {
        let filled = min(max(progress, 0), 1)
        let lit = palette.accentText.alpha(0.55).color
        let cold = glowOnly ? Color.clear : palette.mutedFill.color
        guard filled > 0 else {
            return [.init(color: cold, location: 0), .init(color: cold, location: 1)]
        }
        return normalize([
            .init(color: lit, location: 0),
            .init(color: lit, location: filled),
            .init(color: cold, location: filled),
            .init(color: cold, location: 1),
        ])
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

#Preview("Zones") {
    ZStack {
        EmberBackground()
        VStack(spacing: 24) {
            EmberRing(content: .fast(goalHours: 16, elapsed: 12.85 * 3600), diameter: 220)
            EmberRing(content: .fast(goalHours: 16, elapsed: 16 * 3600), diameter: 160)
            EmberRing(content: .resting(progress: 0.4), diameter: 160)
        }
    }
}
