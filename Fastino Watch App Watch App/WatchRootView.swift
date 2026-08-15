//
//  WatchRootView.swift
//  Fastino Watch App
//
//  The watch shell (§4.7). Three horizontal pages, timer in the middle:
//
//      [ Progress ]  ←  [ Timer ]  →  [ Settings ]
//
//  A page TabView rather than a NavigationStack of pushes because the timer has
//  to stay one gesture away from anywhere. Pushing would put the app's whole
//  reason for existing behind a back button, and on a wrist that matters more
//  than it does on a phone.
//
//  Timer is the initial selection, so raising your wrist shows the fast and
//  nothing else. The other two pages exist for the *standalone* install — a
//  watch with no iPhone app has no other way to change the plan or fix a
//  forgotten end time — but they're equally reachable on a paired watch, where
//  they're simply a faster path than reaching for the phone.
//

import SwiftData
import SwiftUI

struct WatchRootView: View {
    private enum Page: Hashable {
        case progress, timer, settings
    }

    @State private var page: Page = .timer

    var body: some View {
        TabView(selection: $page) {
            WatchProgressView()
                .tag(Page.progress)
            WatchTimerView()
                .tag(Page.timer)
            WatchSettingsView()
                .tag(Page.settings)
        }
        .tabViewStyle(.page)
    }
}

#Preview {
    WatchRootView().modelContainer(AppContainer.inMemory())
}
