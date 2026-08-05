//
//  TimerView.swift
//  JustFast
//
//  The main screen (§4.1): one dominant progress ring with elapsed/goal time and
//  a single Start fast / End fast button. Celebration cues per §5.
//

import SwiftUI
import SwiftData
import UIKit

struct TimerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query private var settingsList: [AppSettings]

    @State private var showStartSheet = false
    @State private var showEndSheet = false
    @State private var recordBanner: String?
    @State private var errorMessage: String?

    private var store: FastStore { FastStore(context: modelContext) }
    private var openFast: Fast? { fasts.first(where: \.isOpen) }
    private var settings: AppSettings? { settingsList.first }

    private var activeProtocol: FastingProtocol {
        settings?.activeProtocol ?? .p168
    }

    /// The wall-clock time the user starts their fast — the anchor the eating
    /// window closes at (§4.1).
    private var startAnchor: DateComponents {
        settings?.startReminderComponents ?? DateComponents(hour: 20, minute: 0)
    }

    /// The eating window to show while idle (§4.1). Evaluated at body time; the
    /// live countdown inside `EatingWindowContent` drives its own clock.
    private var eatingWindow: EatingWindow? {
        FastingEngine.currentEatingWindow(
            fasts.records,
            anchor: startAnchor,
            now: Date(),
            timeZone: .current
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                if let banner = recordBanner {
                    RecordBanner(text: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                if let openFast {
                    ActiveFastContent(
                        fast: openFast,
                        reduceMotion: reduceMotion,
                        onEnd: { showEndSheet = true }
                    )
                } else if let eatingWindow {
                    EatingWindowContent(
                        window: eatingWindow,
                        onStart: { showStartSheet = true }
                    )
                } else {
                    // Never fasted, or the last fast is too old to frame an
                    // eating window — the plain "Ready" state (§4.1).
                    IdleContent(
                        activeProtocol: activeProtocol,
                        onStart: { showStartSheet = true }
                    )
                }

                Spacer(minLength: 0)
            }
            .padding()
            .animation(.spring(duration: 0.4), value: recordBanner)
        }
        .sheet(isPresented: $showStartSheet) {
            AdjustTimeSheet(
                title: "Start fast",
                actionLabel: "Start fast",
                accent: Theme.amber,
                date: Date()
            ) { date in
                // Ask for notification permission at the moment it's first useful
                // (so the goal alert can fire) rather than nagging on launch.
                Task {
                    await NotificationManager.shared.requestAuthorization()
                    perform { try store.startFast(at: date) }
                }
            }
        }
        .sheet(isPresented: $showEndSheet) {
            AdjustTimeSheet(
                title: "End fast",
                actionLabel: "End fast",
                accent: Theme.mint,
                earliest: openFast?.start,
                date: Date(),
                onConfirm: { date in perform { try store.endFast(at: date) } },
                destructive: openFast.map { fast in
                    (
                        label: "Delete fast",
                        confirmTitle: "Delete this fast? It won’t be recorded.",
                        action: { store.delete(fast) }
                    )
                }
            )
        }
        .alert("Couldn’t save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            _ = store.settings() // ensure the settings object exists
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-showStartSheet") {
                showStartSheet = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showEndSheet") {
                showEndSheet = true
            }
            #endif
        }
    }

    private func perform(_ action: () throws -> FastActionResult) {
        do {
            let result = try action()
            handle(result)
        } catch let error as FastValidationError {
            errorMessage = error.message
        } catch let error as AppError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ result: FastActionResult) {
        guard result.kind == .ended else { return }
        if result.isNewLongestFast {
            recordBanner = "New record — \(DurationFormat.hoursMinutes(result.fast.finalDuration ?? 0))"
        } else if result.isNewLongestStreak {
            recordBanner = "New record — \(result.currentStreak)-day streak"
        }
        if recordBanner != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                recordBanner = nil
            }
        }
    }
}

// MARK: - Active fast

private struct ActiveFastContent: View {
    let fast: Fast
    let reduceMotion: Bool
    let onEnd: () -> Void

    @State private var didCelebrateGoal = false

    var body: some View {
        TimelineView(.periodic(from: fast.start, by: 1)) { context in
            let now = context.date
            let record = fast.record
            let elapsed = record.duration(asOf: now)
            let progress = elapsed / record.goalInterval
            let reached = progress >= 1

            VStack(spacing: 24) {
                ZStack {
                    RingView(progress: progress)
                        .frame(width: 260, height: 260)

                    VStack(spacing: 6) {
                        Text("\(record.goalHours)h fast")
                            .font(.callout)
                            .foregroundStyle(Theme.secondaryText)
                        Text(DurationFormat.clock(elapsed))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                        // Once the goal is behind you its clock time is stale, so
                        // the celebration takes the slot rather than stacking.
                        if reached {
                            Text("Goal reached 🎉")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.mint)
                        } else {
                            Text("Ends \(TimeFormat.endLabel(record.goalReachedAt, now: now))")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                if elapsed > 48 * 3600 {
                    // §6: gentle prompt for a very long open fast.
                    Text("Still fasting? You can adjust the end time if you forgot to stop the timer.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 32)
                }

                Button(action: onEnd) {
                    Text("End fast")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.mint, in: .capsule)
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 40)
            }
            .onChange(of: reached) { _, isReached in
                if isReached && !didCelebrateGoal {
                    didCelebrateGoal = true
                    celebrateGoal()
                }
            }
        }
    }

    private func celebrateGoal() {
        guard !reduceMotion else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Eating window

/// Between fasts: the ring fills across the eating window so the user can see how
/// long is left before the next fast is due (§4.1). Copy stays neutral once the
/// window is over — running late is not a failure (§5).
private struct EatingWindowContent: View {
    let window: EatingWindow
    let onStart: () -> Void

    var body: some View {
        TimelineView(.periodic(from: window.start, by: 1)) { context in
            let now = context.date
            let isOver = window.isOver(asOf: now)
            let remaining = window.remaining(asOf: now)

            VStack(spacing: 24) {
                ZStack {
                    RingView(progress: window.progress(asOf: now), style: .eating)
                        .frame(width: 260, height: 260)

                    VStack(spacing: 6) {
                        // The heading carries the count's direction: unlike the
                        // fast's always-rising elapsed time, this counts *down* to
                        // the window's close and *up* again afterwards. No "8h"
                        // prefix — the window is whatever the anchor leaves, not a
                        // fixed length the user is owed.
                        Text(isOver ? "Window closed" : "Eating window")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.secondaryText)
                        Text(DurationFormat.clock(abs(remaining)))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                        if isOver {
                            Text("Ready when you are")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.amber)
                        } else {
                            Text("Next fast at \(TimeFormat.endLabel(window.end, now: now))")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Button(action: onStart) {
                    Text("Start fast")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.amber, in: .capsule)
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - Idle

private struct IdleContent: View {
    let activeProtocol: FastingProtocol
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RingView(progress: 0)
                    .frame(width: 260, height: 260)
                VStack(spacing: 6) {
                    Text("Ready")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    Text(activeProtocol.displayName)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Button(action: onStart) {
                Text("Start fast")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Theme.amber, in: .capsule)
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Record banner (§5)

private struct RecordBanner: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.mint, in: .capsule)
    }
}
