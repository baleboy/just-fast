//
//  TimerView.swift
//  Fastino
//
//  The main screen (§4.1): the flame mascot inside the zone ring, the zone beads
//  that double as the ring's legend, and a single Start fast / End fast button.
//  Motion and celebration cues per §5.
//

import SwiftUI
import SwiftData
import UIKit

struct TimerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]

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

    /// The most recently closed fast — the eating window's recap card.
    private var lastClosedFast: FastRecord? {
        fasts.records
            .filter { $0.end != nil && $0.end! <= Date() }
            .max { ($0.end ?? .distantPast) < ($1.end ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Text("fastino")
                    .font(.flame(20, .extraBold, relativeTo: .title3))
                    .foregroundStyle(Theme.brand)

                if let openFast {
                    ActiveFastContent(
                        fast: openFast,
                        reduceMotion: reduceMotion,
                        onEnd: { showEndSheet = true }
                    )
                } else {
                    RestingContent(
                        window: eatingWindow,
                        lastFast: lastClosedFast,
                        streak: FastingEngine.currentStreak(fasts.records, now: Date(), timeZone: .current),
                        activeProtocol: activeProtocol,
                        onStart: { showStartSheet = true }
                    )
                }
            }
            .padding(.horizontal, FlameLayout.timerHorizontalPadding)
            .padding(.top, FlameLayout.screenTopPadding)
            .flameTabBarClearance()

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
                accent: Theme.accentText,
                date: Date()
            ) { date, _ in
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
                accent: Theme.accentText,
                earliest: openFast?.start,
                date: Date(),
                collectsNote: true,
                note: openFast?.note ?? "",
                onConfirm: { date, note in perform { try store.endFast(at: date, note: note) } },
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

    @Environment(\.colorScheme) private var colorScheme

    /// The launch sweep: the ring fills 0 → current on appear (1.8s ease-out).
    @State private var fillScale: Double = 0
    /// 0 → 1 over the life of a flash; parked at 1, where it's invisible.
    @State private var flashProgress: Double = 1
    @State private var flashColor: Color = .clear
    @State private var celebrating = false
    @State private var didCelebrateGoal = false

    var body: some View {
        TimelineView(.periodic(from: fast.start, by: 1)) { context in
            let now = context.date
            let record = fast.record
            let elapsed = record.duration(asOf: now)
            let reached = elapsed >= record.goalInterval
            let zone = MetabolicZone.current(elapsed: elapsed)
            let palette = Theme.palette(for: colorScheme)

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let diameter = min(geometry.size.width, 310)
                    ZStack {
                        FlameRing(
                            content: .fast(goalHours: record.goalHours, elapsed: elapsed),
                            diameter: diameter,
                            fillScale: fillScale
                        )

                        RingFlash(color: flashColor, diameter: diameter, progress: flashProgress)

                        if celebrating {
                            EmberBurst(diameter: diameter, palette: palette)
                        }

                        VStack(spacing: 6) {
                            FlameMascot.inZone(zone, palette: palette, height: diameter * (86.0 / 310.0))
                                .padding(.bottom, 2)
                            Text(DurationFormat.clock(elapsed))
                                .font(.flameFixed(40, .extraBold))
                                .monospacedDigit()
                                .foregroundStyle(palette.ink.color)
                            Text("\(record.goalHours)h fast · ends \(TimeFormat.endLabel(record.goalReachedAt, now: now))")
                                .font(.flameFixed(14))
                                .foregroundStyle(palette.muted.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: diameter * 0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 310)
                .padding(.top, 40)

                ZoneBeads(goalHours: record.goalHours, elapsed: elapsed)
                    .padding(.top, 30)

                if elapsed > 48 * 3600 {
                    // §6: gentle prompt for a very long open fast.
                    Text("Still fasting? You can adjust the end time if you forgot to stop the timer.")
                        .font(.flame(12.5, .semibold, relativeTo: .caption))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.muted.color)
                        .padding(.top, 16)
                }

                Spacer(minLength: 20)

                // Past the goal the action stops being "stop early" and starts
                // being "bank the win", so it turns green and says so.
                FlamePrimaryButton(
                    title: reached ? "Log this fast" : "End fast",
                    celebrating: reached,
                    action: onEnd
                )
            }
            .onChange(of: zone) { _, newZone in
                crossZone(into: newZone, palette: palette)
            }
            .onChange(of: reached) { _, isReached in
                if isReached && !didCelebrateGoal {
                    didCelebrateGoal = true
                    celebrateGoal()
                }
            }
        }
        .onAppear(perform: startUp)
    }

    // MARK: Motion

    /// Two entrances: a fast that was *just* started ignites (an expanding ring
    /// flash), any other appearance sweeps the fill up from zero.
    private func startUp() {
        guard !reduceMotion else {
            fillScale = 1
            return
        }
        let justStarted = Date().timeIntervalSince(fast.start) < 2
        if justStarted {
            fillScale = 0
            withAnimation(.easeOut(duration: 0.9)) { fillScale = 1 }
            flash(Theme.palette(for: colorScheme).zones[0].to.color, duration: 0.9)
        } else {
            withAnimation(.easeOut(duration: 1.8)) { fillScale = 1 }
        }
    }

    private func crossZone(into zone: MetabolicZone, palette: FlamePalette) {
        guard !reduceMotion else { return }
        flash(palette.zones[zone.rawValue].to.color, duration: 0.6)
        Haptics.soft()
    }

    private func flash(_ color: Color, duration: Double) {
        flashColor = color
        flashProgress = 0
        withAnimation(.easeOut(duration: duration)) { flashProgress = 1 }
    }

    private func celebrateGoal() {
        Haptics.success()
        guard !reduceMotion else { return }
        flash(Theme.palette(for: colorScheme).success.color, duration: 1)
        celebrating = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            celebrating = false
        }
    }
}

// MARK: - Between fasts

/// Between fasts the flame is a pilot light and the ring is just waiting (§4.1).
/// Copy stays neutral once the window is over — running late is not a failure.
private struct RestingContent: View {
    let window: EatingWindow?
    let lastFast: FastRecord?
    let streak: Int
    let activeProtocol: FastingProtocol
    let onStart: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: window?.start ?? .now, by: 1)) { context in
            let now = context.date
            let isOver = window?.isOver(asOf: now) ?? true
            let palette = Theme.palette(for: colorScheme)

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let diameter = min(geometry.size.width, 310)
                    ZStack {
                        FlameRing(content: .waiting, diameter: diameter)

                        VStack(spacing: 6) {
                            FlameMascot.pilotLight(palette: palette, height: diameter * (68.0 / 310.0))
                                .padding(.bottom, 2)
                            Text(headline(isOver: isOver))
                                .font(.flameFixed(16, .extraBold))
                                .tracking(0.3)
                                .foregroundStyle(palette.muted.color)
                            Text(value(now: now))
                                .font(.flameFixed(40, .extraBold))
                                .monospacedDigit()
                                .foregroundStyle(palette.ink.color)
                            Text(caption(now: now, isOver: isOver))
                                .font(.flameFixed(14))
                                .foregroundStyle(palette.muted.color)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: diameter * 0.72)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 310)
                .padding(.top, 40)

                if let lastFast {
                    LastFastCard(fast: lastFast, streak: streak)
                        .padding(.top, 30)
                }

                Spacer(minLength: 20)

                FlamePrimaryButton(title: "Start fast", resting: true, action: onStart)
            }
        }
    }

    /// The heading carries the count's direction: unlike the fast's always-rising
    /// elapsed time, this counts *down* to the window's close and *up* again
    /// afterwards. No hour count — the window is whatever the anchor leaves, not
    /// a fixed length the user is owed.
    private func headline(isOver: Bool) -> String {
        guard window != nil else { return "READY" }
        return isOver ? "WINDOW CLOSED" : "EATING WINDOW"
    }

    private func value(now: Date) -> String {
        guard let window else { return "\(activeProtocol.goalHours)h fast" }
        return DurationFormat.hoursMinutes(abs(window.remaining(asOf: now)))
    }

    /// Every branch names the plan's length, so the fast you're about to start
    /// is stated wherever the ring is counting something else. The idle "READY"
    /// state carries it in `value` instead, where it's the only number there.
    private func caption(now: Date, isOver: Bool) -> String {
        guard let window else { return "start whenever you’re ready" }
        return isOver
            ? "\(activeProtocol.goalHours)h fast · ready when you are"
            : "until your \(activeProtocol.goalHours)h fast · \(TimeFormat.endLabel(window.end, now: now))"
    }
}

/// The recap under the waiting ring: what you just did, and what it was worth.
private struct LastFastCard: View {
    let fast: FastRecord
    let streak: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST FAST")
                    .flameSectionLabel()
                Text(summary)
                    .font(.flame(18, .extraBold, relativeTo: .headline))
                    .foregroundStyle(palette.ink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 10)
            if streak > 0 {
                SuccessChip(text: "Streak ×\(streak)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .flameCard()
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let length = DurationFormat.hoursMinutes(fast.finalDuration ?? 0)
        return fast.isGoalMet ? "\(length) · goal met" : "\(length) · logged"
    }
}

// MARK: - Zone beads (the ring's legend)

private struct ZoneBeads: View {
    let goalHours: Int
    let elapsed: TimeInterval

    var body: some View {
        let current = MetabolicZone.current(elapsed: elapsed)
        HStack(spacing: 10) {
            ForEach(MetabolicZone.allCases) { zone in
                ZoneBead(zone: zone, state: state(of: zone, current: current))
            }
        }
    }

    private func state(of zone: MetabolicZone, current: MetabolicZone) -> ZoneBead.State {
        guard zone.isReachable(withGoalHours: goalHours) else { return .unreachable }
        if zone == current { return .active }
        return zone.rawValue < current.rawValue ? .done : .upcoming
    }
}

private struct ZoneBead: View {
    enum State { case done, active, upcoming, unreachable }

    let zone: MetabolicZone
    let state: State

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor(palette))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.flame(12.5, state == .active ? .extraBold : .bold, relativeTo: .caption))
                .foregroundStyle(state == .active ? palette.accentText.color : palette.beadLabel.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if state == .active {
                Capsule().fill(palette.accentSurface.color)
                    .overlay { Capsule().strokeBorder(palette.accentBorder.color, lineWidth: 2) }
            } else {
                Capsule().fill(palette.elevated.color)
                    .shadow(color: palette.cardShadow.color, radius: 5, y: 3)
            }
        }
        .opacity(state == .active || state == .done ? 1 : 0.55)
        .animation(.snappy(duration: 0.3), value: state)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch state {
        case .done: "\(zone.name) ✓"
        case .active: "\(zone.name)!"
        case .upcoming, .unreachable: zone.name
        }
    }

    private func dotColor(_ palette: FlamePalette) -> Color {
        switch state {
        case .done, .active: palette.zones[zone.rawValue].dot.color
        case .upcoming, .unreachable: palette.idleDot.color
        }
    }
}

// MARK: - Completion celebration (§5)

/// Rising embers, staggered, ~2s. Purely decorative and skipped under Reduce
/// Motion by the caller.
private struct EmberBurst: View {
    let diameter: CGFloat
    let palette: FlamePalette

    private let count = 10

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Ember(
                    index: index,
                    count: count,
                    diameter: diameter,
                    color: palette.zones[index % palette.zones.count].to.color
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Ember: View {
    let index: Int
    let count: Int
    let diameter: CGFloat
    let color: Color

    @State private var risen = false

    /// Spread across the ring's width, each one a slightly different size and
    /// delay so the burst doesn't read as a single row.
    private var offsetX: CGFloat {
        let spread = diameter * 0.42
        return spread * (CGFloat(index) / CGFloat(count - 1) - 0.5) * 2
    }
    private var size: CGFloat { diameter * (index.isMultiple(of: 3) ? 0.05 : 0.035) }
    private var delay: Double { Double(index) * 0.09 }

    var body: some View {
        BlobShape.body
            .fill(color)
            .frame(width: size * 0.86, height: size)
            .offset(x: offsetX, y: risen ? -diameter * 0.55 : diameter * 0.2)
            .opacity(risen ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).delay(delay)) { risen = true }
            }
    }
}

// MARK: - Record banner (§5)

private struct RecordBanner: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Text(text)
            .font(.flame(14, .extraBold, relativeTo: .footnote))
            .foregroundStyle(palette.success.color)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(palette.successSurface.color, in: .capsule)
            .shadow(color: palette.cardShadow.color, radius: 8, y: 4)
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
