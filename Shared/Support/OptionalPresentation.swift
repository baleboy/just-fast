//
//  OptionalPresentation.swift
//  Fastino
//
//  Presenting a dialog off an optional piece of state.
//
//  `.constant(value != nil)` is the obvious spelling and it is a trap: the
//  binding is write-only-to-nowhere, so *every* dismissal SwiftUI attempts is
//  silently dropped. The sheet cannot be closed by tapping outside, by swiping
//  down, or by a `.cancel` button — which iOS 26 doesn't draw at all in the
//  card presentation, leaving the user with no way out but to commit to one of
//  the choices. Verified on the simulator: with a constant binding the plan
//  dialog survived an outside tap and a downward swipe.
//
//  This gives back a real binding whose `false` clears the optional, which is
//  what the dismissal machinery needs.
//

import SwiftUI

extension Binding {
    /// A `Bool` binding that is `true` while the optional is non-`nil`, and
    /// clears it when set to `false`.
    ///
    /// Setting it to `true` is meaningless — there is no value to invent — and
    /// is ignored; presenting is done by assigning the optional itself.
    func presented<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
