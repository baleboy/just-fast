//
//  WatchTimerView.swift
//  Fastino Watch App
//
//  The whole watch app (§4.7): ring, mascot, elapsed time, zone, one button.
//  No stats and no settings — the watch reads the plan the phone chose and
//  never writes it, so there's nothing here that can drift out of sync.
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

    @State private var reconciler = SyncReconciler()
    @State private var errorMessage: String?

    private var store: FastStore { FastStore(context: modelContext) }
    private var openFast: Fast? { fasts.first(where: \.isOpen) }
    private var goalHours: Int {
        openFast?.goalHours ?? settingsList.first?.activeProtocol.goalHours ?? 16
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
                idleRing(size: ringSize)
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
                    FlameMascot.inZone(
                        zone,
                        palette: Theme.palette(for: .dark),
                        height: size * 0.26,
                        bobDuration: reduceMotion ? nil : 3
                    )
                    Text(timerInterval: record.start...Date.distantFuture, countsDown: false)
                        .font(.flameFixed(19, .extraBold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(zone.name)
                        .font(.flameFixed(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: size, height: size)
            .onChange(of: zone) { _, _ in Haptics.soft() }
        }
    }

    private func idleRing(size: CGFloat) -> some View {
        ZStack {
            FlameRing(content: .waiting, diameter: size)
            VStack(spacing: 2) {
                FlameMascot.pilotLight(palette: Theme.palette(for: .dark), height: size * 0.26)
                Text("Ready")
                    .font(.flameFixed(17, .extraBold))
                    .foregroundStyle(Theme.ink)
                Text("\(goalHours)h fast")
                    .font(.flameFixed(11, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Action

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
        do {
            // Stamped so History can show where a fast came from, and so the
            // phone can tell a watch-started fast apart from its own.
            let result = try store.toggle(createdVia: .watch)
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
