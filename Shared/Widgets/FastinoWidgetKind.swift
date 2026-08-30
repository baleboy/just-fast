//
//  FastinoWidgetKind.swift
//  Fastino
//
//  The kind strings WidgetKit identifies each surface by (§4.5, §4.7).
//
//  They live here because they are agreed between processes: the extension
//  declares a kind, and `FastStore.reloadWidgets()` — in the app, and in the
//  extension itself — asks for it by name. A typo doesn't error, it just means
//  the surface never refreshes, which is the hardest kind of bug to see.
//
//  These values are also stored by the system against every widget and control
//  the user has placed. **Changing one loses those placements**, so treat them
//  as fixed once shipped.
//

import Foundation

nonisolated enum FastinoWidgetKind {
    /// The Lock Screen accessory widget (§4.5), iOS.
    static let lockScreen = "FastingLockScreen"

    /// The Control Center toggle (§4.5), iOS. Controls are not timelines, so
    /// this one is reloaded through `ControlCenter`, never `WidgetCenter`.
    static let fastingControl = "com.baleware.fastino.control.fasting"

    /// The watch complication (§4.7). The string predates this file — it is the
    /// literal the widget shipped with, and must stay that way.
    static let watchComplication = "FastingComplication"
}
