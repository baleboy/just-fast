//
//  FastingComplication.swift
//  FastinoWatchWidgets
//
//  The watch complication (§4.7): fasting state and progress at a glance, and
//  a tap opens the app.
//
//  Only the *views* live here. The entry, the store read and the timeline
//  instants are in `Shared/Widgets/` — the iPhone Lock Screen widget (§4.5)
//  shows the same fact from the same store, and one of those two surfaces
//  quietly disagreeing with the other is exactly what sharing them prevents.
//

import SwiftUI
import WidgetKit

// MARK: - Views

struct FastingComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: FastingEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            FastingCircularView(entry: entry)
        case .accessoryCorner:
            // The curved label carries the zone, not the hours — the gauge is
            // already showing those, and repeating them wastes the one extra
            // piece of information this family affords.
            FastingCircularView(entry: entry)
                .widgetLabel { Text(entry.zone?.name ?? "Ready") }
        case .accessoryInline:
            Text(inlineLabel)
        case .accessoryRectangular:
            rectangular
        default:
            FastingCircularView(entry: entry)
        }
    }

    private var rectangular: some View {
        let style = entry.style(renderingMode)
        return HStack(spacing: 6) {
            FlatFlameMascot(style: style.bodyStyle)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.fast == nil ? "Not fasting" : (entry.zone?.name ?? "Fasting"))
                    .font(.headline)
                    .foregroundStyle(style.usesColor ? AnyShapeStyle(style.to) : AnyShapeStyle(.primary))
                    .widgetAccentable()
                if let fast = entry.fast {
                    Text(timerInterval: fast.start...Date.distantFuture, countsDown: false)
                        .font(.body)
                    ProgressView(value: entry.progress)
                        .progressViewStyle(.linear)
                        .tint(style.tint)
                } else {
                    Text("Tap to start")
                        .font(.body)
                }
            }
        }
    }

    private var inlineLabel: String {
        guard let fast = entry.fast, let elapsed = entry.elapsed else { return "Not fasting" }
        return "Fasting \(Int(elapsed / 3600))h of \(fast.goalHours)h"
    }
}

// MARK: - Widget

struct FastingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FastinoWidgetKind.watchComplication, provider: FastingProvider()) { entry in
            FastingComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fast")
        .description("How far into your fast you are.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    FastingComplication()
} timeline: {
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-10 * 3600), end: nil, goalHours: 16))
    FastingEntry(date: .now, fast: nil)
}

#Preview("Circular — ready", as: .accessoryCircular) {
    FastingComplication()
} timeline: {
    FastingEntry(date: .now, fast: nil)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    FastingComplication()
} timeline: {
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-15 * 3600), end: nil, goalHours: 16))
    FastingEntry(date: .now, fast: nil)
}
