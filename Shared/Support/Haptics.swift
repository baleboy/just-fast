//
//  Haptics.swift
//  Fastino
//
//  The two taps the app uses, per platform (§5: "success haptic — .success on
//  iPhone, .notification(.success) on watch").
//
//  Worth knowing when writing celebration code: on watchOS haptics only play
//  when the app is frontmost and the watch is on the wrist, so a zone-crossing
//  tap with the wrist down is simply lost. Never make a cue the user needs
//  depend on the haptic having landed — it's an accent on a visible change,
//  not a substitute for one.
//

import Foundation

#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
enum Haptics {
    /// A light accent — crossing a metabolic zone.
    static func soft() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    /// Reaching the goal.
    static func success() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #elseif canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
