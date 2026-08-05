//
//  StatsView.swift
//  Fastino
//
//  The Stats screen (§4.3): streaks, current/longest fast, a 7-day strip,
//  30-day averages, and a link into full history. Everything is derived by the
//  pure engine — nothing here is stored.
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Refresh once a second so the live "current fast" ticks.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let summary = FastingEngine.summary(fasts.records, now: context.date, timeZone: .current)
                content(summary)
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ summary: StatsSummary) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    StatTile(title: "Current streak", value: "\(summary.currentStreak)", unit: "days", accent: summary.currentStreak > 0 ? Theme.mint : Theme.secondaryText)
                    StatTile(title: "Longest streak", value: "\(summary.longestStreak)", unit: "days", accent: Theme.amber)
                }
                HStack(spacing: 12) {
                    StatTile(
                        title: "Current fast",
                        value: summary.currentFastDuration.map { DurationFormat.hoursMinutes($0) } ?? "—",
                        unit: summary.currentFastDuration != nil ? "elapsed" : "idle",
                        accent: Theme.amber
                    )
                    StatTile(
                        title: "Longest fast",
                        value: summary.longestFast > 0 ? DurationFormat.hoursMinutes(summary.longestFast) : "—",
                        unit: "ever",
                        accent: Theme.amber
                    )
                }

                SevenDayStrip(days: summary.last7Days)

                HStack(spacing: 12) {
                    StatTile(
                        title: "Avg duration",
                        value: summary.averageDuration30d.map { DurationFormat.hoursMinutes($0) } ?? "—",
                        unit: "last 30 days",
                        accent: Theme.amber
                    )
                    StatTile(
                        title: "Goal rate",
                        value: summary.goalCompletionRate30d.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        unit: "last 30 days",
                        accent: Theme.mint
                    )
                }

                NavigationLink {
                    HistoryView()
                } label: {
                    HStack {
                        Text("History")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(Theme.primaryText)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: .rect(cornerRadius: 16))
                }
            }
            .padding()
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}

private struct SevenDayStrip: View {
    let days: [Bool] // oldest → today

    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST 7 DAYS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, met in
                    Circle()
                        .fill(met ? Theme.mint : Theme.ringTrack)
                        .frame(height: 26)
                        .overlay {
                            if met {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.background)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack { StatsView() }
        .modelContainer(AppContainer.inMemory())
}
