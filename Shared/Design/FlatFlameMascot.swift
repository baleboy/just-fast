//
//  FlatFlameMascot.swift
//  Fastino
//
//  The mascot at widget scale (§4.5, §4.7) — `BlobShape`'s silhouette with its
//  face punched *through* the body rather than drawn on it.
//
//  Two things make this a separate view from `FlameMascot` rather than a
//  smaller instance of it:
//
//  **The face is holes, not ink.** Accented and vibrant rendering — what watch
//  faces and the iPhone Lock Screen use — collapse the whole view to one tint,
//  so dark-on-flame becomes flame-on-flame and the face vanishes. Holes read in
//  every mode, because they show whatever is behind the widget.
//
//  **The features are deliberately chunkier.** `FlameMascot`'s proportions are
//  tuned for 40pt and up, where an eye is 0.122 of the width; at 30pt that
//  lands under a point and disappears.
//

import SwiftUI

struct FlatFlameMascot: View {
    /// The body fill. Callers pass the zone gradient in full colour and
    /// `AnyShapeStyle(.foreground)` in accented/vibrant, where asking for our
    /// own colour produces muddy or invisible results.
    let style: AnyShapeStyle

    init(style: AnyShapeStyle) {
        self.style = style
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                BlobShape.body.fill(style)

                Group {
                    Ellipse()
                        .frame(width: w * 0.17, height: h * 0.19)
                        .position(x: w * 0.33, y: h * 0.46)
                    Ellipse()
                        .frame(width: w * 0.17, height: h * 0.19)
                        .position(x: w * 0.67, y: h * 0.46)
                    FlatSmile()
                        .stroke(style: StrokeStyle(lineWidth: max(1, w * 0.085), lineCap: .round))
                        .frame(width: w * 0.34, height: h * 0.09)
                        .position(x: w * 0.5, y: h * 0.64)
                }
                .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .aspectRatio(74.0 / 86.0, contentMode: .fit)
    }
}

/// The same quad-curve smile `FlameMascot` draws. It stays a separate shape
/// because this one is stroked far heavier for its size; keep the control point
/// in step if that one ever changes.
private struct FlatSmile: Shape {
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
