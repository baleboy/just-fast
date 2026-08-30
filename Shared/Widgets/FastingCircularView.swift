//
//  FastingCircularView.swift
//  Fastino
//
//  The circular accessory, shared by the iPhone Lock Screen widget (§4.5) and
//  the watch complication (§4.7) — the same fact at the same size, so the same
//  view.
//
//  Deliberately **not** `FlameRing`. That draws the full gold→orange→pink scale
//  with a glow across one ring, which turns to mud at 30pt and is thrown away
//  entirely in accented and vibrant rendering. A single flat `Gauge` in the
//  *current* zone's colour keeps the palette's meaning at this size.
//

import SwiftUI
import WidgetKit

struct FastingCircularView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: FastingEntry

    var body: some View {
        let style = entry.style(renderingMode)
        return Gauge(value: entry.progress) {
            FlatFlameMascot(style: style.bodyStyle)
        } currentValueLabel: {
            if entry.fast == nil {
                // An empty ring plus a dash reads as "broken"; the mascot reads
                // as "nothing running, tap to start".
                FlatFlameMascot(style: style.bodyStyle).padding(1)
            } else {
                Text(entry.shortLabel)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(style.tint)
        .widgetAccentable()
    }
}
