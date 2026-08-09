//
//  StatsView.swift
//  Fastino
//
//  The Stats screen (§4.3): a soft bento of streaks and records, the week as a
//  row of little flames, and a link into full history. Everything is derived by
//  the pure engine — nothing here is stored.
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query private var settingsList: [AppSettings]

    /// The goal the flames are measured against: the running fast's snapshotted
    /// goal while one is open, otherwise the plan currently selected.
    private var referenceGoalHours: Int {
        fasts.first(where: \.isOpen)?.goalHours
            ?? settingsList.first?.activeProtocol.goalHours
            ?? FastingProtocol.p168.goalHours
    }

    var body: some View {
        // Refresh once a second so the live "current fast" ticks.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let summary = FastingEngine.summary(fasts.records, now: context.date, timeZone: .current)
            content(summary)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ summary: StatsSummary) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("Your journey")
                        .flameScreenTitle()
                    Text("Last 30 days")
                        .font(.flame(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 6)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        currentFastCard(summary)
                        longestFastCard(summary)
                    }
                    GridRow {
                        streakCard(summary)
                        goalRateCard(summary)
                    }
                }

                WeekFlames(bars: summary.last7DayBars)

                NavigationLink { HistoryView() } label: {
                    HStack {
                        Text("History")
                            .font(.flame(16, .extraBold, relativeTo: .headline))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("→")
                            .font(.flame(16, .extraBold, relativeTo: .headline))
                            .foregroundStyle(Theme.accentText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .flameCard(radius: Radius.row)
                }
                .buttonStyle(FlamePressStyle())
            }
            .padding(.horizontal, FlameLayout.screenHorizontalPadding)
            .padding(.top, FlameLayout.screenTopPadding)
            .flameTabBarClearance()
        }
    }

    // MARK: Bento cards

    @ViewBuilder
    private func currentFastCard(_ summary: StatsSummary) -> some View {
        let goalInterval = TimeInterval(referenceGoalHours) * 3600
        if let elapsed = summary.currentFastDuration {
            let percent = Int((min(elapsed / goalInterval, 1) * 100).rounded())
            BentoCard(
                label: "CURRENT FAST",
                value: DurationFormat.hoursMinutes(elapsed),
                valueColor: Theme.accentText,
                caption: "elapsed · \(percent)% of \(referenceGoalHours)h"
            )
        } else {
            BentoCard(label: "CURRENT FAST", value: "—", caption: "no fast running")
        }
    }

    private func longestFastCard(_ summary: StatsSummary) -> some View {
        BentoCard(
            label: "LONGEST FAST",
            value: summary.longestFast > 0 ? DurationFormat.hoursMinutes(summary.longestFast) : "—",
            caption: "your record",
            // The flame turns up to admire your best — the one bit of mascot
            // presence outside the timer.
            showsMascot: summary.longestFast > 0
        )
    }

    private func streakCard(_ summary: StatsSummary) -> some View {
        BentoCard(
            label: "STREAK",
            value: "\(summary.currentStreak)",
            caption: summary.currentStreak > 0 ? "keep it lit" : "finish today to relight",
            trailingValue: "best \(summary.longestStreak)"
        )
    }

    private func goalRateCard(_ summary: StatsSummary) -> some View {
        BentoCard(
            label: "GOAL RATE",
            value: summary.goalCompletionRate30d.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
            caption: summary.averageDuration30d.map { "avg \(DurationFormat.hoursMinutes($0)) · 30 days" }
                ?? "last 30 days",
            onAccentSurface: true
        )
    }
}

// MARK: - Bento card

private struct BentoCard: View {
    let label: String
    let value: String
    var valueColor: Color?
    let caption: String
    /// The small "best 2" sitting next to the streak number.
    var trailingValue: String?
    var showsMascot: Bool = false
    /// The goal-rate card sits on peach instead of white.
    var onAccentSurface: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        let secondary = onAccentSurface ? palette.onAccentSurface.color : palette.muted.color

        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .flameSectionLabel(secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.flame(32, .extraBold, relativeTo: .title))
                    .foregroundStyle(valueColor ?? (onAccentSurface ? palette.accentText.color : palette.ink.color))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let trailingValue {
                    Text(trailingValue)
                        .font(.flame(13, .bold, relativeTo: .caption))
                        .foregroundStyle(secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)
            Text(caption)
                .font(.flame(12.5, .semibold, relativeTo: .caption))
                .foregroundStyle(secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .overlay(alignment: .topTrailing) {
            if showsMascot {
                FlameMascot.lit(palette: palette, height: 30)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
            }
        }
        .flameCard(fill: onAccentSurface ? palette.accentSurface.color : nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Week flames

private struct WeekFlames: View {
    let bars: [DayBar]

    private var showsFootnote: Bool { bars.contains { $0.isInProgress && !$0.goalMet } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LAST 7 DAYS")
                .flameSectionLabel()

            HStack(spacing: 0) {
                ForEach(bars) { bar in
                    DayFlame(bar: bar)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 12)

            if showsFootnote {
                Text("Dashed flame = today, in progress")
                    .font(.flame(12.5, .semibold, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flameCard()
    }
}

private struct DayFlame: View {
    let bar: DayBar

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flickering = false

    /// Today, still going: the flame is outlined rather than solid, and flickers.
    private var isToday: Bool { bar.isInProgress && !bar.goalMet }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(spacing: 5) {
            Group {
                if isToday {
                    BlobShape.body
                        .fill(LinearGradient(
                            colors: [palette.zones[0].from.color, palette.zones[0].to.color],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .overlay {
                            BlobShape.body.strokeBorder(
                                palette.accentText.color,
                                style: StrokeStyle(lineWidth: 2, dash: [3.5, 3])
                            )
                        }
                        .frame(width: 30, height: 34)
                        .scaleEffect(flickering ? 1.06 : 1)
                        .rotationEffect(.degrees(flickering ? 2 : -2))
                } else if bar.goalMet {
                    FlameMascot.lit(palette: palette, height: 34)
                } else {
                    FlameMascot.unlit(palette: palette, height: 34)
                        .opacity(0.3)
                }
            }
            .frame(height: 34)

            Text(bar.date.formatted(.dateTime.weekday(.narrow)))
                .font(.flameFixed(11, bar.goalMet || isToday ? .extraBold : .bold))
                .foregroundStyle(bar.goalMet || isToday ? palette.accentText.color : palette.muted.color)
        }
        .onAppear {
            guard isToday, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                flickering = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let day = bar.date.formatted(.dateTime.weekday(.wide))
        if bar.duration <= 0 { return "\(day), no fast" }
        let length = DurationFormat.hoursMinutes(bar.duration)
        if isToday { return "\(day), \(length) so far" }
        return "\(day), \(length)\(bar.goalMet ? ", goal met" : "")"
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
