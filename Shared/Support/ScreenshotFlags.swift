//
//  ScreenshotFlags.swift
//  Fastino
//
//  DEBUG-only launch flags that exist for the App Store screenshot pass
//  (docs/store/copy.md) rather than for development. In `Shared/` because the
//  watch listing needs its own screenshot set and hits the same problem.
//

import Foundation

enum ScreenshotFlags {
    /// Whether the "iCloud sync is off" row may appear.
    ///
    /// A simulator is never signed in to iCloud, so the row is always shown
    /// there and always wrong about the shipping app — and on the Settings
    /// screenshot it lands directly under a headline about your data being
    /// safe. `-noSyncWarning` suppresses the row for that capture and nothing
    /// else: sync itself, and every other code path, is untouched.
    static var showsSyncWarning: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-noSyncWarning")
        #else
        return true
        #endif
    }

    /// Whether the Stats screen draws its Health panels above the bento.
    ///
    /// The panels normally sit at the foot of the screen, below the bento and
    /// the week strip, and `simctl` can't scroll — so the capture that is
    /// *about* them can only see their top edge. `-healthPanelsFirst` reorders
    /// the screen for that one shot. This exists so the reorder is a launch
    /// argument rather than an edit someone has to remember to undo.
    static var healthPanelsFirst: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-healthPanelsFirst")
        #else
        return false
        #endif
    }
}
