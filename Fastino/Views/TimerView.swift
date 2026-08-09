//
//  TimerView.swift
//  Fastino
//
//  The main screen (§4.1): the Ember ring with elapsed/goal time, the three zone
//  cards that double as the ring's legend, and a single Start fast / End fast
//  button. Celebration cues per §5.
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
    /// live countdown inside `RestingContent` drives its own clock.
    private var eatingWindow: EatingWindow? {
        FastingEngine.currentEatingWindow(
            fasts.records,
            anchor: startAnchor,
            now: Date(),
            timeZone: .current
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            EmberBackground()

            VStack(spacing: 0) {
                Text("FASTINO")
                    .emberScreenTitle()

                if let openFast {
                    ActiveFastContent(
                        fast: openFast,
                        reduceMotion: reduceMotion,
                        onEnd: { showEndSheet = true }
                    )
                } else {
                    RestingContent(
                        window: eatingWindow,
                        activeProtocol: activeProtocol,
                        onStart: { showStartSheet = true }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, EmberLayout.screenTopPadding)
            .emberTabBarClearance()

            if let banner = recordBanner {
                RecordBanner(text: banner)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.spring(duration: 0.4), value: recordBanner)
        .sheet(isPresented: $showStartSheet) {
            AdjustTimeSheet(
                title: "Start fast",
                actionLabel: "Start fast",
                accent: Theme.accent,
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
                accent: Theme.accent,
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
            let reached = elapsed >= record.goalInterval
            let zone = MetabolicZone.current(elapsed: elapsed)

            VStack(spacing: 0) {
                RingStack(
                    content: .fast(goalHours: record.goalHours, elapsed: elapsed),
                    reduceMotion: reduceMotion
                ) {
                    Text("\(record.goalHours)H FAST")
                        .font(.emberFixed(13, .semibold))
                        .tracking(2.3)
                        .foregroundStyle(Theme.secondaryText)
                    Text(DurationFormat.clock(elapsed))
                        .font(.emberFixed(44, .bold))
                        .tracking(-0.9)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    // Once the goal is behind you its clock time is stale, so the
                    // celebration takes the slot rather than stacking.
                    if reached {
                        Text("Goal reached 🎉")
                            .font(.emberFixed(13, .semibold))
                            .foregroundStyle(Theme.success)
                    } else {
                        Text("ends \(TimeFormat.endLabel(record.goalReachedAt, now: now))")
                            .font(.emberFixed(13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                } chip: {
                    ZoneChip(zone: zone, reduceMotion: reduceMotion)
                }

                ZoneCards(goalHours: record.goalHours, elapsed: elapsed)
                    .padding(.top, 34)

                if elapsed > 48 * 3600 {
                    // §6: gentle prompt for a very long open fast.
                    Text("Still fasting? You can adjust the end time if you forgot to stop the timer.")
                        .font(.ember(12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 18)
                        .padding(.horizontal, 12)
                }

                Spacer(minLength: 24)

                EmberPrimaryButton(title: "End fast", action: onEnd)
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

// MARK: - Between fasts

/// Between fasts the fire is out: the ring goes cold and fills across the eating
/// window so you can see how long is left before the next fast is due (§4.1).
/// Copy stays neutral once the window is over — running late is not a failure.
private struct RestingContent: View {
    let window: EatingWindow?
    let activeProtocol: FastingProtocol
    let onStart: () -> Void

    var body: some View {
        TimelineView(.periodic(from: window?.start ?? .now, by: 1)) { context in
            let now = context.date
            let isOver = window?.isOver(asOf: now) ?? true

            VStack(spacing: 0) {
                RingStack(
                    content: .resting(progress: window?.progress(asOf: now) ?? 0),
                    reduceMotion: true
                ) {
                    Text(headline(isOver: isOver))
                        .font(.emberFixed(13, .semibold))
                        .tracking(2.3)
                        .foregroundStyle(Theme.secondaryText)
                    Text(value(now: now))
                        .font(.emberFixed(44, .bold))
                        .tracking(-0.9)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text(caption(now: now, isOver: isOver))
                        .font(.emberFixed(13))
                        .foregroundStyle(Theme.secondaryText)
                } chip: {
                    RestingChip(label: activeProtocol.rawValue + " plan")
                }

                ZoneCards(goalHours: activeProtocol.goalHours, elapsed: 0)
                    .padding(.top, 34)

                Spacer(minLength: 24)

                EmberPrimaryButton(title: "Start fast", action: onStart)
            }
        }
    }

    /// The heading carries the count's direction: unlike the fast's always-rising
    /// elapsed time, this counts *down* to the window's close and *up* again
    /// afterwards. No "8h" prefix — the window is whatever the anchor leaves, not
    /// a fixed length the user is owed.
    private func headline(isOver: Bool) -> String {
        guard window != nil else { return "READY" }
        return isOver ? "WINDOW CLOSED" : "EATING WINDOW"
    }

    private func value(now: Date) -> String {
        guard let window else { return "\(activeProtocol.goalHours):00:00" }
        return DurationFormat.clock(abs(window.remaining(asOf: now)))
    }

    private func caption(now: Date, isOver: Bool) -> String {
        guard let window else { return "whenever you’re ready" }
        return isOver
            ? "ready when you are"
            : "next fast at \(TimeFormat.endLabel(window.end, now: now))"
    }
}

// MARK: - Ring + centred stack

/// Ring with its centred text block and chip. The ring shrinks on narrow devices
/// but the type doesn't, so the centre block stays legible.
private struct RingStack<Center: View, Chip: View>: View {
    let content: EmberRing.Content
    let reduceMotion: Bool
    @ViewBuilder let center: Center
    @ViewBuilder let chip: Chip

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, 312)
            ZStack {
                EmberRing(content: content, diameter: diameter)
                VStack(spacing: 4) {
                    center
                    chip.padding(.top, 4)
                }
                .frame(maxWidth: diameter * 0.72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 312)
        .padding(.top, 48)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: reduceMotion)
    }
}

// MARK: - Zone chip

private struct ZoneChip: View {
    let zone: MetabolicZone
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var flickering = false

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 7) {
            Circle()
                .fill(palette.accent.color)
                .frame(width: 8, height: 8)
                .scaleEffect(flickering ? 1.06 : 1)
                .rotationEffect(.degrees(flickering ? 2 : -2))
            Text(zone.chipLabel)
                .font(.emberFixed(12.5, .semibold))
                .foregroundStyle(palette.accentText.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.accentChip.color, in: .capsule)
        .overlay { Capsule().strokeBorder(palette.accent.alpha(0.42).color, lineWidth: 1) }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                flickering = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Same shape as the zone chip but cold — nothing is burning between fasts.
private struct RestingChip: View {
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Text(label)
            .font(.emberFixed(12.5, .semibold))
            .foregroundStyle(palette.textSecondary.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(palette.mutedFill.color, in: .capsule)
            .overlay { Capsule().strokeBorder(palette.cardBorder.color, lineWidth: 1) }
    }
}

// MARK: - Zone cards (the ring's legend)

private struct ZoneCards: View {
    let goalHours: Int
    let elapsed: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let current = elapsed > 0 ? MetabolicZone.current(elapsed: elapsed) : nil
        HStack(spacing: 8) {
            ForEach(MetabolicZone.allCases) { zone in
                ZoneCard(
                    zone: zone,
                    state: state(of: zone, current: current)
                )
            }
        }
    }

    private func state(of zone: MetabolicZone, current: MetabolicZone?) -> ZoneCard.State {
        guard zone.isReachable(withGoalHours: goalHours) else { return .unreachable }
        guard let current else { return .ahead }
        if zone == current { return .active }
        return zone.rawValue < current.rawValue ? .done : .ahead
    }
}

private struct ZoneCard: View {
    enum State { case done, active, ahead, unreachable }

    let zone: MetabolicZone
    let state: State

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let zoneColor = palette.zones[zone.rawValue].label.color

        VStack(spacing: 3) {
            Text(zone.rangeLabel)
                .font(.emberFixed(11))
                .tracking(0.9)
                .foregroundStyle(state == .ahead || state == .unreachable
                                 ? palette.textTertiary.color
                                 : palette.textSecondary.color)
            Text(state == .done ? "\(zone.name) ✓" : zone.name)
                .font(.emberFixed(12.5, .bold))
                .foregroundStyle(titleColor(palette, zoneColor: zoneColor))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
        .emberCard(
            radius: Radius.smallCard,
            fill: state == .active ? palette.accent.alpha(colorScheme == .dark ? 0.12 : 0.08).color : nil,
            border: borderColor(palette, zoneColor: zoneColor),
            glow: state == .active ? palette.accent.alpha(0.25).color : nil
        )
        .opacity(state == .unreachable ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private func titleColor(_ palette: EmberPalette, zoneColor: Color) -> Color {
        switch state {
        case .done, .active: zoneColor
        case .ahead, .unreachable: palette.textSecondary.color
        }
    }

    private func borderColor(_ palette: EmberPalette, zoneColor: Color) -> Color? {
        switch state {
        case .active: palette.accent.color
        case .done: palette.zones[zone.rawValue].label.alpha(0.45).color
        case .ahead, .unreachable: nil
        }
    }
}

// MARK: - Record banner (§5)

private struct RecordBanner: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.ember(13, .bold, relativeTo: .footnote))
            .foregroundStyle(colorScheme == .dark ? Color(hex: 0x12241E) : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.success, in: .capsule)
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
