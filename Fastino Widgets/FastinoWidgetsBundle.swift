//
//  FastinoWidgetsBundle.swift
//  Fastino Widgets
//
//  The iOS widget extension (§4.5): the Lock Screen accessory and the Control
//  Center toggle. Sibling of `Fastino Watch Widgets`, which carries the
//  complication (§4.7).
//

import SwiftUI
import WidgetKit

@main
struct FastinoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FastingLockScreenWidget()
        FastingControl()
    }
}
