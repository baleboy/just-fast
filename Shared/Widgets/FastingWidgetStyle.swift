//
//  FastingWidgetStyle.swift
//  Fastino
//
//  How a widget surface colours itself (§4.5, §4.7).
//
//  The one rule worth stating once rather than twice: **colour depends on the
//  rendering mode.** Watch faces render complications `.accented` or `.vibrant`
//  and the iPhone Lock Screen renders `.vibrant`; all of them discard colour and
//  tint the view themselves, so asking for our own there produces muddy or
//  invisible results. Smart Stack and StandBy get `.fullColor`, which is where
//  the zone palette actually shows — so rather than designing for the
//  monochrome floor everywhere, both surfaces branch.
//

import SwiftUI
import WidgetKit

nonisolated struct FastingWidgetStyle {
    let zone: MetabolicZone
    let renderingMode: WidgetRenderingMode

    /// Widget chrome is dark in every context these surfaces appear in.
    /// `.zones[zone.rawValue]`, never a literal.
    private var colors: ZonePalette { FlamePalette.of(.dark).zones[zone.rawValue] }

    var usesColor: Bool { renderingMode == .fullColor }

    var from: Color { colors.from.color }
    /// The single flat colour for a gauge or a bar — the band's far end, which
    /// is what reads at this size.
    var to: Color { colors.to.color }

    /// `nil` hands tinting back to the system, which is what accented and
    /// vibrant modes want.
    var tint: Color? { usesColor ? to : nil }

    /// The mascot's body fill.
    var bodyStyle: AnyShapeStyle {
        usesColor
            ? AnyShapeStyle(LinearGradient(colors: [from, to], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(.foreground)
    }
}

extension FastingEntry {
    /// The style for this entry — the current zone's, or the gold of the first
    /// zone when nothing is running.
    func style(_ renderingMode: WidgetRenderingMode) -> FastingWidgetStyle {
        FastingWidgetStyle(zone: zone ?? .burning, renderingMode: renderingMode)
    }

    /// Hours only. These surfaces are read in a glance, and minutes on a fast
    /// measured in hours are noise.
    var shortLabel: String {
        guard let elapsed else { return "—" }
        return "\(Int(elapsed / 3600))h"
    }
}
