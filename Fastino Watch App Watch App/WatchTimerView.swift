//
//  WatchTimerView.swift
//  Fastino Watch App
//
//  The watch's home page (§4.7): ring, mascot, elapsed time, zone, one button.
//  It's the middle page of `WatchRootView` and the one the app opens on, so
//  everything here earns its place by being useful at a glance.
//
//  This was once the entire app, on the reasoning that the watch only ever
//  *reads* the plan and the phone owns every choice. Standalone installation
//  broke that: a watch with no iPhone app has no other way to pick a protocol
//  or fix a forgotten end time. Hence the Progress and Settings pages either
//  side — but the split still holds here, and this page writes nothing but the
//  fast itself.
//
//  Written fresh rather than adapted from TimerView, which is 580 lines of
//  sheets, eating-window card and tab chrome. What *is* reused is the part
//  worth reusing: FlameRing and FlameMascot both take a size, so the design
//  scales to a 41mm screen without a second implementation of the ring maths.
//

import SwiftData
import SwiftUI

struct WatchTimerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]

    /// Optional because previews inject no environment; a watch with no verdict
    /// yet is treated as one that might still be about to hear from the phone.
    @Environment(CloudSyncStatus.self) private var syncStatus: CloudSyncStatus?

    @State private var reconciler = SyncReconciler()
    @State private var errorMessage: String?
    /// Flipped by the `.task` below when the window's deadline passes. It is
    /// purely a re-render trigger — mutating `@State` invalidates the view, and
    /// `SyncLog.isAwaitingImport()` is the authority on what to show. A view
    /// that had to notice time passing on its own would need a per-second
    /// timeline, and the idle screen is not worth one.
    @State private var syncWaitElapsed = false

    /// Preview-only override: `nil` computes the state, `true`/`false` force it.
    ///
    /// It has to work in *both* directions. `simctl` never syncs, so forcing it
    /// on is the only way to look at the waiting state — and a preview process
    /// does open the real mirrored container, so `isCloudKitConfigured` is true
    /// there and the ready preview would otherwise sit on "Checking" for the
    /// whole timeout before settling.
    var checkingOverride: Bool?

    private var store: FastStore { FastStore(context: modelContext) }
    private var openFast: Fast? { fasts.first(where: \.isOpen) }
    private var goalHours: Int {
        openFast?.goalHours ?? settingsList.first?.activeProtocol.goalHours ?? 16
    }

    /// Whether this launch might still be waiting to hear about a fast running
    /// on the phone.
    ///
    /// The screen otherwise states "Ready" the instant it appears, because a
    /// store that hasn't imported yet and a store with genuinely no fast in it
    /// look identical from here — and on watchOS the first import routinely
    /// lands seconds after launch. Saying "Ready" and then contradicting it is
    /// what makes sync feel broken even on the occasions it works.
    ///
    /// A device that is signed out or offline skips the wait: it has nothing to
    /// wait *for*, and "Checking" that never resolves is a worse lie than the
    /// one this replaces.
    private var isCheckingSync: Bool {
        if let checkingOverride { return checkingOverride }
        guard openFast == nil else { return false }
        if case .unavailable = syncStatus?.health { return false }
        // Not gated on `syncWaitElapsed`: past the deadline the wait continues
        // while an import is actually running, and giving up on one that is
        // about to land is exactly the contradiction this state exists to stop.
        return SyncLog.shared.isAwaitingImport()
    }

    var body: some View {
        GeometryReader { proxy in
            // The ring wants to fill the width but leave room for the button
            // below it; 0.78 lands right on both 41mm and 49mm.
            let ringSize = min(proxy.size.width, proxy.size.height) * 0.78

            ZStack {
                FlameBackground(resting: openFast == nil)
                content(ringSize: ringSize)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Keyed on the window, so a resume that reopens one restarts the timer
        // rather than leaving `syncWaitElapsed` stuck true from launch — which
        // is the whole point: the app is far more often resumed than launched.
        .task(id: SyncLog.shared.awaitWindowStartedAt) {
            syncWaitElapsed = false
            // Ends the wait at the deadline. `importArrivedInWindow` is
            // observed, so an import landing first ends it without this.
            let log = SyncLog.shared
            let remaining = log.awaitWindowTimeout
                - Date().timeIntervalSince(log.awaitWindowStartedAt)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            syncWaitElapsed = true
        }
        .onChange(of: fasts.count(where: \.isOpen), initial: true) { _, count in
            reconciler.openFastCountChanged(to: count, context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            reconciler.openFastCountChanged(to: fasts.count(where: \.isOpen), context: modelContext)
        }
        .alert("Couldn’t do that", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(ringSize: CGFloat) -> some View {
        VStack(spacing: 6) {
            if let fast = openFast {
                activeRing(for: fast.record, size: ringSize)
            } else {
                idleRing(size: ringSize, checking: isCheckingSync)
            }
            actionButton
        }
        .padding(.horizontal, 6)
    }

    // MARK: Ring

    private func activeRing(for record: FastRecord, size: CGFloat) -> some View {
        // The digits come from Text(timerInterval:), which the system renders
        // without waking us — so it stays correct in Always-On, where a
        // per-second TimelineView would be both throttled and a battery cost.
        // The ring only needs the coarse timeline: at this diameter a minute of
        // progress is well under a pixel.
        TimelineView(.periodic(from: record.start, by: 60)) { context in
            let elapsed = record.duration(asOf: context.date)
            let zone = MetabolicZone.current(elapsed: elapsed)

            ZStack {
                FlameRing(content: .fast(goalHours: record.goalHours, elapsed: elapsed), diameter: size)
                VStack(spacing: 2) {
                    // No tip: `inZone` draws it *above* the declared height, so
                    // at this scale it crosses the ring band. The tip is a
                    // flourish for the 310pt phone ring, not load-bearing.
                    FlameMascot.inZone(
                        zone,
                        palette: Theme.palette(for: .dark),
                        height: size * 0.22,
                        showsTip: false,
                        bobDuration: reduceMotion ? nil : 3
                    )
                    Text(timerInterval: record.start...Date.distantFuture, countsDown: false)
                        .font(.flameFixed(19, .extraBold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.ink)
                    Text(zone.name)
                        .font(.flameFixed(11, .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.muted)
                }
                // Wide enough for the digits, which sit at the ring's widest
                // point; the inscribed square would be far too narrow here.
                .frame(width: FlameRing.innerDiameter(for: size) * 0.94)
            }
            .frame(width: size, height: size)
            .onChange(of: zone) { _, _ in Haptics.soft() }
        }
    }

    /// The same ring in both states — only the copy changes. Deliberately not a
    /// spinner: the difference between "no fast" and "don't know yet" is a
    /// caption, not a different screen, and the mascot is already the right
    /// mascot for waiting.
    private func idleRing(size: CGFloat, checking: Bool) -> some View {
        ZStack {
            FlameRing(content: .waiting, diameter: size)
            VStack(spacing: 2) {
                FlameMascot.pilotLight(palette: Theme.palette(for: .dark), height: size * 0.26)
                Text(checking ? "Checking" : "Ready")
                    .font(.flameFixed(17, .extraBold))
                    .foregroundStyle(Theme.ink)
                Text(checking ? "iCloud…" : "\(goalHours)h fast")
                    .font(.flameFixed(11, .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: FlameRing.innerDiameter(for: size) * 0.94)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: checking)
    }

    // MARK: Action

    /// Enabled throughout, including while `isCheckingSync` is true: a
    /// standalone watch must be able to begin a fast without waiting on a
    /// network. If that races an inbound import the result is two open fasts,
    /// which is exactly what `SyncReconciler` and `OpenFastMerge` exist for.
    private var actionButton: some View {
        Button {
            toggle()
        } label: {
            Text(openFast == nil ? "Start" : "End fast")
                .font(.flameFixed(15, .extraBold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentText)
    }

    private func toggle() {
        let wasIdle = openFast == nil
        do {
            // Stamped so History can show where a fast came from, and so the
            // phone can tell a watch-started fast apart from its own.
            let result = try store.toggle(createdVia: .watch)
            if wasIdle {
                // Ask at the moment it's first useful — so the goal alert can
                // fire — rather than nagging on launch (§4.4). Only when this
                // watch owns scheduling; awaiting the probe avoids prompting on
                // a paired watch whose session hasn't activated yet. The start
                // itself never waits on this.
                Task {
                    guard await CompanionProbe.shared.resolvedSchedulesLocally() else { return }
                    await NotificationManager.shared.requestAuthorization()
                    store.reconcileNotifications()
                }
            }
            if result.kind == .ended, result.goalMet {
                Haptics.success()
            } else {
                Haptics.soft()
            }
        } catch let error as AppError {
            errorMessage = error.message
        } catch let error as FastValidationError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

// simctl can't tap, so the active state is unreachable on a booted watch sim —
// these are how it gets looked at.

@MainActor
private func previewContainer(openFastHoursAgo: Double?) -> ModelContainer {
    let container = AppContainer.inMemory()
    let context = container.mainContext
    context.insert(AppSettings())
    if let hours = openFastHoursAgo {
        context.insert(Fast(
            start: Date().addingTimeInterval(-hours * 3600),
            goalHours: 16,
            protocolID: FastingProtocol.p168.rawValue,
            createdVia: .watch
        ))
    }
    return container
}

#Preview("Fasting — ketosis") {
    WatchTimerView().modelContainer(previewContainer(openFastHoursAgo: 15))
}

#Preview("Fasting — burning") {
    WatchTimerView().modelContainer(previewContainer(openFastHoursAgo: 3))
}

#Preview("Ready") {
    WatchTimerView(checkingOverride: false)
        .modelContainer(previewContainer(openFastHoursAgo: nil))
}

/// 10h into a 16:8 fast — the state the iPhone hero screenshot shows, so the
/// two devices in the store panel are looking at the same fast
/// (docs/store/copy.md). Appended last so the earlier previews keep their
/// indices.
#Preview("Fasting — 10h, store hero") {
    WatchTimerView().modelContainer(previewContainer(openFastHoursAgo: 10))
}

/// The state a watch shows for the first few seconds after launch while it is
/// still waiting to hear whether the phone has a fast running. Unreachable from
/// `simctl`, which never syncs.
#Preview("Checking iCloud") {
    WatchTimerView(checkingOverride: true)
        .modelContainer(previewContainer(openFastHoursAgo: nil))
}
