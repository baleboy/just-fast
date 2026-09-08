//
//  WatchProgressView.swift
//  Fastino Watch App
//
//  The progress page (§4.7): current streak, the seven-day strip, and the
//  recent fasts — each tappable to fix an end time that got away.
//
//  This is the *whole* reason the page exists. A forgotten end time is the one
//  mistake a fasting tracker can't shrug off: it corrupts the streak, the
//  averages and the longest fast all at once, and on a standalone watch there is
//  no phone to go and fix it on. Streak and strip are here because they're what
//  makes the correction worth making.
//
//  Everything shown is derived by `FastingEngine` from `[FastRecord]`, exactly
//  as on the phone, so the two can't disagree about what a streak is.
//

import SwiftData
import SwiftUI

struct WatchProgressView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    /// Optional because previews inject no environment — see `WatchTimerView`.
    @Environment(CloudSyncStatus.self) private var syncStatus: CloudSyncStatus?

    @State private var editing: Fast?
    @State private var syncWaitElapsed = false

    private var records: [FastRecord] { fasts.records }

    /// The same wait the timer page shows, for the same reason: an empty list is
    /// indistinguishable from a list that hasn't imported yet, and "No fasts
    /// yet" is a strong claim to make about someone's history three seconds
    /// after launch.
    private var isCheckingSync: Bool {
        guard fasts.isEmpty else { return false }
        if case .unavailable = syncStatus?.health { return false }
        return SyncLog.shared.isAwaitingImport()
    }

    var body: some View {
        NavigationStack {
            // The strip and the streak both move as an open fast runs, but only
            // ever by a bar's-width per hour — a minute is plenty fresh, and it
            // costs no wakeups the ring isn't already paying for.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List {
                    streakSection(now: context.date)
                    stripSection(now: context.date)
                    recentSection
                }
                .listStyle(.plain)
            }
            .navigationTitle("Progress")
        }
        .task(id: SyncLog.shared.awaitWindowStartedAt) {
            syncWaitElapsed = false
            let log = SyncLog.shared
            let remaining = log.awaitWindowTimeout
                - Date().timeIntervalSince(log.awaitWindowStartedAt)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            syncWaitElapsed = true
        }
        .sheet(item: $editing) { fast in
            WatchFastDetailView(fast: fast)
        }
    }

    // MARK: Streak

    private func streakSection(now: Date) -> some View {
        let streak = FastingEngine.currentStreak(records, now: now, timeZone: .current)
        return Section {
            HStack(spacing: 8) {
                // Lit while the streak is alive, dozing at zero — the streak is
                // the flame you're keeping going, so the mascot has to be the
                // one thing on this page that can go out. A zone colour would
                // be borrowed from a fast that may not even be running.
                Group {
                    if streak > 0 {
                        FlameMascot.lit(palette: Theme.palette(for: .dark), height: 34)
                    } else {
                        FlameMascot.pilotLight(palette: Theme.palette(for: .dark), height: 34)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(streak)")
                        .font(.flameFixed(26, .extraBold))
                        .foregroundStyle(Theme.ink)
                    Text("day streak")
                        .font(.flameFixed(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
        }
    }

    // MARK: Week strip

    /// A bar histogram, not a row of mascots: height carries a quantity, which
    /// is the distinction the design settled on. Same rule as the phone's.
    private func stripSection(now: Date) -> some View {
        let bars = FastingEngine.lastDays(records, now: now, timeZone: .current)
        let goalHours = fasts.first(where: \.isOpen)?.goalHours ?? 16
        let goal = TimeInterval(goalHours) * 3600

        return Section("Last 7 days") {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(bars) { bar in
                    VStack(spacing: 3) {
                        // Clamped so an unusually long fast can't stretch the
                        // row and squash every other bar into the baseline.
                        let fraction = min(bar.duration / goal, 1)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bar.goalMet ? Theme.accentText : Theme.muted.opacity(0.4))
                            .frame(height: max(2, 26 * fraction))
                        Text(bar.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.flameFixed(9, .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 42, alignment: .bottom)
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        // The open fast is listed too, and first. Its *start* is the time most
        // worth correcting — tap Start twenty minutes late and every zone
        // boundary and the goal alert are wrong from then on — and the timer
        // page has no way in. Ending it stays the timer page's job.
        let open = fasts.first(where: \.isOpen)
        let closed = fasts.filter { !$0.isOpen }.prefix(10)
        let listed = (open.map { [$0] } ?? []) + Array(closed)

        return Section("Recent") {
            if listed.isEmpty {
                Text(isCheckingSync ? "Checking iCloud…" : "No fasts yet.")
                    .font(.flameFixed(12, .semibold))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(listed) { fast in
                    Button {
                        editing = fast
                    } label: {
                        recentRow(fast)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recentRow(_ fast: Fast) -> some View {
        let record = fast.record
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.start.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.flameFixed(14, .extraBold))
                    .foregroundStyle(Theme.ink)
                Text(durationLabel(record))
                    .font(.flameFixed(11, .semibold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if record.isOpen {
                Text("now")
                    .font(.flameFixed(11, .extraBold))
                    .foregroundStyle(Theme.accentText)
            } else if record.isGoalMet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            }
        }
    }

    private func durationLabel(_ record: FastRecord) -> String {
        // The open fast has no finalDuration; show it running instead of "—".
        let duration = record.finalDuration ?? record.duration(asOf: Date())
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m of \(record.goalHours)h"
    }
}

#Preview {
    let container = AppContainer.inMemory()
    let context = container.mainContext
    context.insert(AppSettings())
    // 21 days, matching the streak `DemoSeeder` builds on the phone — the two
    // devices appear side by side in the store panels (docs/store/copy.md) and
    // shouldn't disagree about how long the streak is.
    for day in 1...21 {
        let start = Date().addingTimeInterval(-Double(day) * 86_400)
        context.insert(Fast(
            start: start,
            end: start.addingTimeInterval(17 * 3600),
            goalHours: 16,
            protocolID: FastingProtocol.p168.rawValue
        ))
    }
    return WatchProgressView().modelContainer(container)
}
