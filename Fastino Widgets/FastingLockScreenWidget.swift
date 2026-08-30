//
//  FastingLockScreenWidget.swift
//  Fastino Widgets
//
//  The Lock Screen accessory widget (§4.5): how far into the fast you are,
//  without unlocking the phone. Tapping opens the app on the timer.
//
//  Circular only, for now. The rectangular family and the Home Screen widget
//  are specified in §4.5 and still unbuilt — see IMPLEMENTATION.md.
//
//  There is almost nothing here on purpose: the entry, the store read, the
//  timeline instants and the circular view itself all live in `Shared/Widgets/`
//  and are the same ones the watch complication uses (§4.7).
//

import SwiftUI
import WidgetKit

struct FastingLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FastinoWidgetKind.lockScreen, provider: FastingProvider()) { entry in
            FastingCircularView(entry: entry)
                .widgetURL(FastinoURL.timer)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fast")
        .description("How far into your fast you are.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Previews

// The Lock Screen renders accessory widgets `.vibrant`, so that is the mode
// worth looking at first — a full-colour preview will not show you what most
// people see. StandBy and the Smart Stack get `.fullColor`.

#Preview("Fasting — vibrant", as: .accessoryCircular) {
    FastingLockScreenWidget()
} timeline: {
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-10 * 3600), end: nil, goalHours: 16))
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-13 * 3600), end: nil, goalHours: 16))
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-15 * 3600), end: nil, goalHours: 16))
}

#Preview("Ready — vibrant", as: .accessoryCircular) {
    FastingLockScreenWidget()
} timeline: {
    FastingEntry(date: .now, fast: nil)
}
