//
//  RingView.swift
//  Fastino
//
//  The progress ring (§4.1, §5). Amber while fasting, blooms to mint once the
//  goal is reached, and keeps counting past 100% (goal exceeded is a positive
//  state) via a second overshoot arc.
//

import SwiftUI

enum RingStyle {
    /// Amber, blooms to mint at the goal and keeps counting past 100%.
    case fasting
    /// Lilac for the eating window. No bloom (mint is success-only, §5) and no
    /// overshoot arc — running past your eating window isn't an achievement.
    case eating
}

struct RingView: View {
    /// 0...∞ — may exceed 1 when the goal is surpassed.
    var progress: Double
    var style: RingStyle = .fasting
    var lineWidth: CGFloat = 18

    private var reachedGoal: Bool { style == .fasting && progress >= 1 }
    private var baseFraction: CGFloat { CGFloat(min(progress, 1)) }
    private var overshoot: CGFloat {
        guard style == .fasting else { return 0 }
        return CGFloat(min(max(progress - 1, 0), 1))
    }

    private var colors: [Color] {
        switch style {
        case .fasting: reachedGoal ? Theme.successGradient : Theme.ringGradient
        case .eating: Theme.eatingGradient
        }
    }

    /// The gradient spans the whole circle starting at the arc's own origin, so
    /// trimming reveals it gradually instead of wrapping partway round.
    ///
    /// Both angles are in the shape's un-rotated space, where 0° is 3 o'clock —
    /// the same place `trim(from: 0,...)` begins. The `-90°` rotation below turns
    /// the stroke *and* its gradient together, so the two stay aligned and the
    /// seam sits at the 12 o'clock start rather than 3/4 of the way round.
    ///
    /// The first colour is repeated at 360° so that a full ring closes on itself
    /// with no visible join — the ring sits at 100% for long stretches (goal
    /// reached, eating window over), so that seam would be on screen a lot.
    private var gradient: AngularGradient {
        AngularGradient(
            colors: colors + colors.prefix(1),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: baseFraction)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if overshoot > 0 {
                Circle()
                    .trim(from: 0, to: overshoot)
                    .stroke(
                        Theme.mint.opacity(0.5),
                        style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: reachedGoal)
    }
}

#Preview {
    VStack(spacing: 40) {
        RingView(progress: 0.6).frame(width: 160, height: 160)
        RingView(progress: 1.2).frame(width: 160, height: 160)
        RingView(progress: 0.45, style: .eating).frame(width: 160, height: 160)
    }
    .padding()
    .background(Theme.background)
}
