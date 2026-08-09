//
//  StatsView.swift
//  Fastino
//
//  The Stats screen (§4.3): a glowing bento of streaks and records, the week as
//  ember bars, and a link into full history. Everything is derived by the pure
//  engine — nothing here is stored.
//

import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query private var settingsList: [AppSettings]

    /// The goal the bars are measured against: the running fast's snapshotted
    /// goal while one is open, otherwise the plan currently selected.
    private var referenceGoalHours: Int {
        fasts.first(where: \.isOpen)?.goalHours
            ?? settingsList.first?.activeProtocol.goalHours
            ?? FastingProtocol.p168.goalHours
    }

    var body: some View {
        ZStack {
            EmberBackground()
            // Refresh once a second so the live "current fast" ticks.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let summary = FastingEngine.summary(fasts.records, now: context.date, timeZone: .current)
                content(summary)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ summary: StatsSummary) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("STATS")
                    .emberScreenTitle()
                    .padding(.bottom, 12)

                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        currentFastCard(summary)
                        BentoCard(label: "LONGEST FAST", caption: "personal best") {
                            BentoValue(text: summary.longestFast > 0
                                       ? DurationFormat.hoursMinutes(summary.longestFast)
                                       : "—")
                        }
                    }
                    GridRow {
                        streakCard(summary)
                        goalRateCard(summary)
                    }
                }

                WeekStrip(bars: summary.last7DayBars, goalHours: referenceGoalHours)

                NavigationLink { HistoryView() } label: {
                    HStack {
                        Text("History")
                            .font(.ember(15, .bold, relativeTo: .subheadline))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .emberCard(radius: Radius.planCard)
                }
                .buttonStyle(EmberPressStyle())
            }
            .padding(.horizontal, EmberLayout.screenHorizontalPadding)
            .padding(.top, EmberLayout.screenTopPadding)
            .emberTabBarClearance()
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
                caption: "\(percent)% of \(referenceGoalHours)h",
                highlighted: true
            ) {
                BentoValue(text: DurationFormat.hoursMinutes(elapsed), style: .gradient)
            }
        } else {
            BentoCard(label: "CURRENT FAST", caption: "no fast running") {
                BentoValue(text: "—")
            }
        }
    }

    private func streakCard(_ summary: StatsSummary) -> some View {
        BentoCard(
            label: "STREAK",
            caption: summary.currentStreak > 0 ? "keep it burning" : "finish today to relight"
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BentoValue(text: "\(summary.currentStreak)")
                Text("best \(summary.longestStreak)")
                    .font(.ember(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func goalRateCard(_ summary: StatsSummary) -> some View {
        BentoCard(
            label: "GOAL RATE",
            caption: summary.averageDuration30d.map { "avg \(DurationFormat.hoursMinutes($0)) · 30 days" }
                ?? "last 30 days"
        ) {
            BentoValue(
                text: summary.goalCompletionRate30d.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                style: summary.goalCompletionRate30d == nil ? .plain : .success
            )
        }
    }
}

// MARK: - Bento pieces

private struct BentoCard<Value: View>: View {
    let label: String
    let caption: String
    var highlighted: Bool = false
    @ViewBuilder let value: Value

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .emberSectionLabel()
            value
                .padding(.top, 6)
            Text(caption)
                .font(.ember(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .emberCard(
            fill: highlighted ? palette.accent.alpha(colorScheme == .dark ? 0.1 : 0.08).color : nil,
            border: highlighted ? palette.accent.alpha(colorScheme == .dark ? 0.45 : 0.6).color : nil,
            glow: highlighted ? palette.accent.alpha(0.18).color : nil
        )
        .accessibilityElement(children: .combine)
    }
}

private struct BentoValue: View {
    enum Style { case plain, gradient, success }

    let text: String
    var style: Style = .plain

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let value = Text(text)
            .font(.ember(30, .bold, relativeTo: .title))
            .tracking(-0.6)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)

        switch style {
        case .plain:
            value.foregroundStyle(Theme.primaryText)
        case .success:
            value.foregroundStyle(Theme.success)
        case .gradient:
            // The heat gradient as the numeral's own fill — the one place a value
            // is painted rather than coloured.
            value.foregroundStyle(Theme.heatGradient(colorScheme))
        }
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    let bars: [DayBar]
    let goalHours: Int

    @Environment(\.colorScheme) private var colorScheme

    private var showsFootnote: Bool { bars.contains { $0.isInProgress && !$0.goalMet } }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LAST 7 DAYS")
                    .emberSectionLabel()
                Spacer()
                Text("goal \(goalHours)h")
                    .font(.ember(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.tertiaryText)
            }

            HStack(alignment: .bottom, spacing: 9) {
                ForEach(bars) { bar in
                    DayColumn(bar: bar, goalHours: goalHours)
                }
            }
            .frame(height: 74 + 6 + 14, alignment: .bottom)
            .padding(.top, 14)

            if showsFootnote {
                Text("Dashed bar = today, still burning")
                    .font(.ember(11.5, .regular, relativeTo: .caption2))
                    .foregroundStyle(palette.textSecondary.alpha(0.8).color)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emberCard()
    }
}

private struct DayColumn: View {
    let bar: DayBar
    let goalHours: Int

    @Environment(\.colorScheme) private var colorScheme

    /// Height as a fraction of the 74pt track. Floored so a day with nothing
    /// logged still leaves an ember rather than vanishing.
    private var fraction: Double {
        let goal = TimeInterval(goalHours) * 3600
        guard goal > 0 else { return 0.1 }
        return min(max(bar.duration / goal, 0.1), 1)
    }

    /// Lit = a completed goal day, or today's fast still going.
    private var isLit: Bool { bar.goalMet || bar.isInProgress }
    private var isDashed: Bool { bar.isInProgress && !bar.goalMet }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Capsule()
                .fill(fill(palette))
                .frame(height: 74 * fraction)
                .overlay {
                    if isDashed {
                        Capsule().strokeBorder(
                            palette.accentText.alpha(0.8).color,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    }
                }
                .shadow(
                    color: isLit && !isDashed ? palette.accent.alpha(0.45).color : .clear,
                    radius: 7,
                    y: colorScheme == .dark ? 0 : 4
                )
            Text(bar.date.formatted(.dateTime.weekday(.narrow)))
                .font(.emberFixed(10.5, isLit ? .bold : .regular))
                .foregroundStyle(isLit ? palette.accentText.color : palette.textTertiary.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func fill(_ palette: EmberPalette) -> AnyShapeStyle {
        guard isLit else { return AnyShapeStyle(palette.mutedFill.color) }
        let colors = palette.heatGradient.map { isDashed ? $0.alpha(0.5).color : $0.color }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
    }

    private var accessibilityLabel: String {
        let day = bar.date.formatted(.dateTime.weekday(.wide))
        if bar.duration <= 0 { return "\(day), no fast" }
        let length = DurationFormat.hoursMinutes(bar.duration)
        if bar.isInProgress && !bar.goalMet { return "\(day), \(length) so far" }
        return "\(day), \(length)\(bar.goalMet ? ", goal met" : "")"
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
