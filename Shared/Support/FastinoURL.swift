//
//  FastinoURL.swift
//  Fastino
//
//  The app's own URL scheme, and the only thing that may construct one (§4.5).
//
//  It exists for the Lock Screen widget: an accessory widget with no
//  `widgetURL` opens the app wherever it was last left, which for a widget
//  about the *fast* means it can land on Settings. Naming the tab is one line
//  here and one line in `RootView`.
//
//  Deliberately knows nothing about `FlameTab` — that type is iOS-only, and
//  this has to compile into the widget extension, which builds the URL without
//  ever resolving it.
//

import Foundation

nonisolated enum FastinoURL {
    static let scheme = "fastino"

    /// Opens the app on the timer. `fastino://timer`.
    static let timer = URL(string: "\(scheme)://timer")!

    /// The tab name a URL asks for, or `nil` if this isn't one of ours.
    ///
    /// Returns the raw host rather than a tab so the caller owns the mapping;
    /// matching is case-insensitive, the same way `FlameTab.initial` matches
    /// the `-tab` launch argument.
    static func tabName(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let host = url.host(), !host.isEmpty else { return nil }
        return host.lowercased()
    }
}
