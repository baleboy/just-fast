//
//  FastingControl.swift
//  Fastino Widgets
//
//  The Control Center toggle (§4.5): start or end a fast without unlocking the
//  phone, and without opening the app.
//
//  **No confirmation, by decision.** `ToggleFastIntent` (§4.6) confirms because
//  Back Tap fires by accident — that's the whole reason it's safe to bind to a
//  double-tap on the back of the phone. Reaching a labelled control in Control
//  Center is already a deliberate gesture, so a confirmation there is friction
//  that buys no safety and costs the thing a toggle is for. A mis-tap is undone
//  in History (§4.2).
//
//  A control's label is SF Symbols and text only, so the mascot can't come
//  here. The filled/outline flame is not a compromise though — it's the same
//  status-light vocabulary `FlameTab.symbol(fasting:)` uses in the tab bar, so
//  the control and the app say the same thing the same way.
//

import AppIntents
import SwiftUI
import WidgetKit

struct FastingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: FastinoWidgetKind.fastingControl,
            provider: FastingControlValueProvider()
        ) { isFasting in
            ControlWidgetToggle(
                "Fasting",
                isOn: isFasting,
                action: SetFastingIntent()
            ) { fasting in
                Label(
                    fasting ? "Fasting" : "Not fasting",
                    systemImage: fasting ? "flame.fill" : "flame"
                )
            }
            // Control Center chrome is dark in every appearance, so the dark
            // palette's first zone — the gold a fast starts in. A token, not a
            // literal, and not green: this is a state, not a success.
            .tint(FlamePalette.of(.dark).zones[MetabolicZone.burning.rawValue].to.color)
        }
        .displayName("Fasting")
        .description("Start or end your fast.")
    }
}

/// The control's value. Read-only — the toggle's *write* is `SetFastingIntent`.
///
/// Controls are not timelines, so nothing here is scheduled: the system polls
/// this, and `FastStore.reloadWidgets()` pushes via `ControlCenter` on every
/// mutation. Without that push, a fast started in the app would leave this
/// reading "off".
struct FastingControlValueProvider: ControlValueProvider {
    let previewValue = true

    func currentValue() async throws -> Bool {
        FastingSnapshot.openFast() != nil
    }
}
