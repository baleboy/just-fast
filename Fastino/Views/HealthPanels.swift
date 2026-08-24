//
//  HealthPanels.swift
//  Fastino
//
//  The Apple Health section of the Stats screen (§4.8): the last thirty days of
//  fasting with sleep and weight from Health, as two panels over one shared
//  date axis.
//
//  It lives on Stats rather than behind a link of its own. A screen you have to
//  go looking for is a screen most people never see, and these two panels are
//  the payoff for logging fasts at all — they belong under the streak, not one
//  tap further away.
//
//  Separate panels rather than one plot of everything: hours and kilograms have
//  no common scale, and overlaying them invites reading a crossing as a
//  correlation. Each panel is instead one *pairing* the user can act on — a
//  thing they chose (how long they fasted, when they stopped eating) over the
//  thing worth reading it against (weight, sleep) — with an axis each and the
//  contract described on `fastingWeightPanel` keeping the two honest.
//
//  This is the one place in the app that uses Swift Charts. Aligned bars plus a
//  line with a real date axis is what it's for; the seven-day strip above it
//  stays hand-drawn, because it's a designed object rather than a chart.
//  Everything here is still styled from `Theme` tokens only.
//

import Charts
import SwiftData
import SwiftUI

struct HealthPanels: View {
    /// Injected so previews and the fixture can drive the screen without
    /// HealthKit. The app always gets the real one.
    var provider: HealthProvider = HealthKitProvider.shared

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]

    @State private var series: HealthSeries = .empty
    @State private var isLoading = true
    @State private var hasLoaded = false

    /// Stats is mounted from launch whether or not it's the selected tab, so
    /// the read waits until it's actually on screen — otherwise the Health
    /// permission sheet greets the user before they've seen the app (§4.8:
    /// asked the first time these panels are looked at, never at launch).
    @Environment(\.flameTabIsVisible) private var isVisible
    /// Health access is granted in the Health app, not here, so the only sign
    /// that it just changed is coming back to the foreground. Without this a
    /// user who turns Fastino's reads on after seeing "No sleep data" keeps
    /// seeing it until the app is relaunched.
    @Environment(\.scenePhase) private var scenePhase

    private static let dayCount = 30

    private var referenceGoalHours: Int {
        fasts.first(where: \.isOpen)?.goalHours
            ?? settingsList.first?.activeProtocol.goalHours
            ?? FastingProtocol.p168.goalHours
    }

    private var bars: [DayBar] {
        FastingEngine.lastDays(fasts.records, now: .now, timeZone: .current, count: Self.dayCount)
    }

    /// The domain both panels are drawn against. Taken from the fasting bars,
    /// which always span the full window, so the axes line up even when Health
    /// returns nothing.
    ///
    /// **Snapped out to whole weeks.** The top panel's bars are weekly, and a
    /// week-wide bar hanging off a mid-week edge is drawn over the axis labels
    /// rather than clipped tidily. Snapping also puts every grid line on a real
    /// week boundary in both panels, which is what makes the two agree. The
    /// window is still thirty days of *data*; it just starts on the user's
    /// first day of the week.
    private var domain: ClosedRange<Date> {
        let days = bars
        guard let first = days.first?.date, let last = days.last?.date else {
            return Date.now...Date.now.addingTimeInterval(1)
        }
        let start = FastingEngine.weekStart(of: first, timeZone: .current)
        let lastWeek = FastingEngine.weekStart(of: last, timeZone: .current)
        return start...lastWeek.addingTimeInterval(7 * 86_400)
    }

    var body: some View {
        VStack(spacing: 12) {
            fastingWeightPanel
            nightPanel
            footnote
        }
        .task(id: isVisible) {
            guard isVisible, !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isVisible, hasLoaded else { return }
            Task { await load() }
        }
    }

    private func load() async {
        guard provider.isAvailable else {
            isLoading = false
            return
        }
        // Asked here, the first time the screen is opened — the moment it is
        // first useful, never on launch (§4.4's rule, applied to Health).
        if await provider.hasBeenAsked() == false {
            await provider.requestAccess()
        }
        series = await provider.series(days: Self.dayCount, now: .now, timeZone: .current)
        isLoading = false
    }

    private var footnote: some View {
        Text("The top panel is by the week \u{2014} day to day, weight is mostly water, and one fast can't have moved a week's average. Below it, each column is the day a fast ended, so an evening's last meal sits with that night's sleep. Patterns show what went together in your own data \u{2014} not what caused what. Sleep and weight come from Apple Health and stay on this device; Fastino never writes to Health.")
            .font(.flame(12.5, .semibold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    // MARK: Panels

    /// Fasting hours with weight laid over them — the night panel's pairing,
    /// applied to the screen's other question.
    ///
    /// Same contract, same defence: the bars are **hours fasted**, grounded at
    /// zero and read against the **right axis**; the line is **weight**, read
    /// against the **left**. Neither series is ever read in the other's
    /// numbers, so a crossing means nothing — the chart is drawn in the hours
    /// scale and the weight series is projected into it, every label converted
    /// back. Only the hours axis draws grid lines.
    ///
    /// A caveat the panel can't state itself: weight answers over weeks, and
    /// day-by-day it is mostly water. This is the shape of the two series, not
    /// evidence — `weightPatternCard` is the one allowed to claim a
    /// relationship, and it pairs them weekly over 90 days for exactly this
    /// reason.
    private var fastingWeightPanel: some View {
        // One bar per calendar week, not per day: weight answers over weeks, so
        // both series are bucketed the same way — see `weeklyAverageHours`.
        let weeks = FastingEngine.weeklyAverageHours(bars, timeZone: .current)
        let goal = Double(referenceGoalHours)
        let peak = max(goal, weeks.map(\.hours).max() ?? goal)
        // Hours is the scale the chart is drawn in: the bars start at zero, so
        // it's the one that must not be shifted or padded at the foot.
        let hoursUpper = peak * 1.1

        let unit = series.massUnit
        // One point per week, in the bars' buckets — see
        // `WeightSeries.weeklyMean`. Two points is the least that can draw a
        // line, and a single week has no trend to show either way.
        let readings = series.weights.filter { $0.date >= domain.lowerBound }
        let trend = WeightSeries.weeklyMean(readings, timeZone: .current)
        let hasWeight = trend.count > 1
        let values = hasWeight ? trend.map { unit.value(fromKilograms: $0.kilograms) } : []
        // A flat month shouldn't render as a jagged line filling the frame.
        let pad = max(((values.max() ?? 1) - (values.min() ?? 0)) * 0.25, 0.5)
        let low = (values.min() ?? 0) - pad
        let high = (values.max() ?? 1) + pad
        let span = max(high - low, 0.1)

        /// Weight → the hours scale the chart is drawn in, and back again.
        func project(_ mass: Double) -> Double { (mass - low) / span * hoursUpper }
        func mass(at projected: Double) -> Double { low + projected / hoursUpper * span }

        // A month of weight often spans less than a unit, where a whole-number
        // step would print one label and leave the line unscaled. Chosen by how
        // many ticks actually land inside the range rather than by the span, so
        // a range straddling a single whole number still gets a scale.
        func tickCount(step: Double) -> Int {
            var value = (low / step).rounded(.up) * step
            var count = 0
            while value <= high {
                count += 1
                value += step
            }
            return count
        }
        let step = [0.2, 0.5, 1, 2, 5].first { (2...5).contains(tickCount(step: $0)) } ?? 1
        var ticks: [Double] = []
        var tick = (low / step).rounded(.up) * step
        while tick <= high {
            ticks.append(tick)
            tick += step
        }
        let decimals = step < 1 ? 1 : 0
        // Weekly bars are five wide blocks rather than thirty thin ones, so
        // they carry more ink at the same opacity — held back a little further
        // when the weight line has to be read over them.
        let barStrength: Double = hasWeight ? 0.65 : 0.9

        return Panel(
            title: "FASTING & WEIGHT",
            // One qualifier for both series, rather than repeating it in each
            // legend label.
            caption: hasWeight
                ? "\(unit.symbol) \u{00B7} hours fasted \u{00B7} weekly means"
                : "hours fasted \u{00B7} weekly mean",
            legend: hasWeight ? [
                LegendItem(color: Theme.accentText, label: "weight", isBar: false),
                LegendItem(color: Theme.accentBorder, label: "hours fasted", isBar: true)
            ] : [],
            note: hasWeight || isLoading || weeks.isEmpty ? nil
                : readings.isEmpty
                    ? Self.noDataMessage("weight")
                    // Not "no data" — there is data, it just can't be a trend
                    // yet, and saying otherwise sends the user to a Settings
                    // screen where nothing is wrong.
                    : "Weigh-ins from one week only. A trend line needs a couple more.",
            domain: domain,
            height: 118,
            // Weekly bars need the weeks named, or a bar is just a block in a
            // month — and both panels' grid lines fall on the same Mondays, so
            // the two axes agree.
            showsDateAxis: true
        ) {
            if weeks.isEmpty && !hasWeight {
                EmptyPanelMessage(isLoading ? "Reading from Health\u{2026}" : "No fasts logged in the last 30 days.")
            } else {
                Chart {
                    ForEach(weeks) { week in
                        BarMark(
                            // `.weekOfYear` makes the bar span its whole week,
                            // so a week reads as a week rather than as a spike
                            // on the Monday.
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Hours", week.hours),
                            // Half the week's band: five weekly bars at full
                            // width read as a wall of orange, and the weight
                            // line needs air to be followed across them.
                            width: .ratio(0.5)
                        )
                        .foregroundStyle(fastingGradient)
                        // Held back from full strength so the line stays
                        // legible over them. With no weight to carry, they go
                        // back to full.
                        .opacity(barStrength)
                        .accessibilityLabel(
                            "week of \(week.weekStart.formatted(.dateTime.month().day()))"
                        )
                        .accessibilityValue(
                            "\(DurationFormat.hoursMinutes(week.hours * 3600)) average fast"
                        )
                    }
                    if !weeks.isEmpty {
                        RuleMark(y: .value("Goal", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.accentText.opacity(0.5))
                            .accessibilityHidden(true)
                    }

                    ForEach(hasWeight ? trend : []) { point in
                        LineMark(
                            // Mid-week, so the mark sits over the middle of the
                            // bar it belongs to rather than on its left edge.
                            x: .value("Week", point.date.addingTimeInterval(3.5 * 86_400)),
                            y: .value(unit.symbol, project(unit.value(fromKilograms: point.kilograms)))
                        )
                        // Monotone rather than catmullRom: the series is
                        // already smooth, and an overshooting spline would put
                        // in dips the mean exists to take out.
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityLabel(
                            "week of \(point.date.formatted(.dateTime.month().day()))"
                        )
                        .accessibilityValue(
                            "\(Measurement(value: point.kilograms, unit: UnitMass.kilograms).converted(to: unit.unit).formatted(.measurement(width: .abbreviated))) average"
                        )

                        // Four or five points is few enough that the line alone
                        // reads as one long segment; the dots say how many
                        // weeks it was actually built from.
                        PointMark(
                            x: .value("Week", point.date.addingTimeInterval(3.5 * 86_400)),
                            y: .value(unit.symbol, project(unit.value(fromKilograms: point.kilograms)))
                        )
                        .symbolSize(20)
                        .foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                    }
                }
                .chartYScale(domain: 0...hoursUpper)
                .chartYAxis {
                    if !hasWeight {
                        hoursAxis()
                    } else {
                        overlayAxis(at: ticks.map(project)) {
                            mass(at: $0).formatted(.number.precision(.fractionLength(decimals)))
                        }
                        if !weeks.isEmpty {
                            hoursAxis(position: .trailing)
                        }
                    }
                }
            }
        }
    }


    /// The screen's centrepiece: how much sleep each night brought, with the
    /// time eating stopped laid over it.
    ///
    /// The one dual-axis plot in the app, and the one place it earns itself:
    /// the question this screen exists to ask is whether stopping earlier goes
    /// with a longer night, and that is read by following the dots down while
    /// the bars grow. **The left axis is clock time (the dots), the right is
    /// hours asleep (the bars)** — the two never share numbers, so a crossing
    /// means nothing and neither series is ever measured against the other's
    /// scale. The clock series is projected onto the sleep scale purely so it
    /// can be drawn; every label it carries is converted back.
    private var nightPanel: some View {
        let stops = FastingEngine.eatingStops(
            fasts.records, now: .now, timeZone: .current, count: Self.dayCount
        )
        let nights = series.nights
        let stopValues = stops.map(\.hoursFromMidnight)

        // Sleep is the scale the chart is actually drawn in: its bars start at
        // zero, so it's the one that must not be shifted or padded at the foot.
        // Rounded up to a whole tick so the axis reads 0h/2h/…/8h rather than
        // stopping at whatever the longest night happened to be.
        let sleepStep: Double = (nights.map(\.hours).max() ?? 8) > 9 ? 4 : 2
        let sleepUpper = max(((nights.map(\.hours).max() ?? 8) / sleepStep).rounded(.up) * sleepStep, sleepStep)

        // The clock scale only has to cover the dots, with a little air so one
        // never sits on the frame.
        let low = (stopValues.min() ?? -6) - 0.5
        let high = (stopValues.max() ?? 0) + 0.5
        // The dashed line is context, not data. Let it widen the scale a little
        // so "later than planned" is visible, but not so far that the dots
        // collapse into a band — a schedule nobody is keeping is exactly when
        // the actual times matter most.
        let anchor = anchorHours(median: median(of: stopValues))
            .filter { max(high, $0) - min(low, $0) <= (high - low) + 3 }
        let clockLow = min(low, anchor ?? low)
        let clockHigh = max(high, anchor ?? high)
        let clockSpan = max(clockHigh - clockLow, 0.5)

        /// Clock time → the sleep scale the chart is drawn in, and back again.
        func project(_ clock: Double) -> Double {
            (clock - clockLow) / clockSpan * sleepUpper
        }
        func clock(at projected: Double) -> Double {
            clockLow + projected / sleepUpper * clockSpan
        }

        // Ticks are picked on the clock scale and then projected, so they land
        // on whole hours instead of on whatever fractions `.automatic` would
        // choose out of a borrowed scale. A night plus an evening spans half a
        // day, where two-hour ticks would stack a dozen labels into the frame.
        let step: Double = clockSpan > 12 ? 4 : 2
        var ticks: [Double] = []
        var tick = (clockLow / step).rounded(.up) * step
        while tick <= clockHigh {
            ticks.append(tick)
            tick += step
        }
        let projectedTicks = ticks.map(project)

        return Panel(
            title: "STOPPED EATING & SLEEP",
            caption: nights.isEmpty ? "clock time" : "clock time \u{00B7} hours asleep",
            legend: nights.isEmpty ? [LegendItem(color: Theme.brand, label: "stopped eating", isBar: false)] : [
                LegendItem(color: Theme.brand, label: "stopped eating", isBar: false),
                LegendItem(color: Theme.mutedFlame.opacity(0.55), label: "hours asleep", isBar: true)
            ],
            // Merging the panels cost the sleep series its own empty state, so
            // it says so here instead — otherwise a missing series just looks
            // like a screen with fewer things on it.
            note: nights.isEmpty && !isLoading && !stops.isEmpty ? Self.noDataMessage("sleep") : nil,
            domain: domain,
            height: 132,
            showsDateAxis: true
        ) {
            if stops.isEmpty && nights.isEmpty {
                EmptyPanelMessage(isLoading ? "Reading from Health\u{2026}" : "Nothing to show yet.")
            } else {
                Chart {
                    ForEach(nights) { night in
                        BarMark(
                            x: .value("Day", night.date, unit: .day),
                            y: .value("Hours asleep", night.hours),
                            width: .ratio(0.62)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(Theme.mutedFlame.opacity(0.55))
                        .accessibilityLabel(night.date.formatted(.dateTime.month().day()))
                        // The bar is the total, naps included, with the
                        // night's main stretch — which the bar doesn't show —
                        // named here.
                        .accessibilityValue(
                            "\(DurationFormat.hoursMinutes(night.asleep)) asleep, mainly \(TimeFormat.timeOfDay(hoursFromMidnight: hours(of: night.mainSleepStart, from: night.date))) to \(TimeFormat.timeOfDay(hoursFromMidnight: hours(of: night.mainSleepEnd, from: night.date)))"
                        )
                    }

                    ForEach(stops) { stop in
                        LineMark(
                            x: .value("Day", stop.date),
                            y: .value("Stopped", project(stop.hoursFromMidnight))
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(Theme.brand.opacity(0.35))
                        .accessibilityHidden(true)

                        PointMark(
                            x: .value("Day", stop.date),
                            y: .value("Stopped", project(stop.hoursFromMidnight))
                        )
                        .symbolSize(42)
                        .foregroundStyle(Theme.brand)
                        .accessibilityLabel(stop.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(
                            "stopped eating \(TimeFormat.timeOfDay(hoursFromMidnight: stop.hoursFromMidnight))"
                        )
                    }

                    if let anchor {
                        RuleMark(y: .value("Planned", project(anchor)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.accentText.opacity(0.5))
                            .accessibilityHidden(true)
                    }
                }
                .chartYScale(domain: 0...sleepUpper)
                .chartYAxis {
                    if stops.isEmpty {
                        hoursAxis(every: sleepStep)
                    } else {
                        overlayAxis(at: projectedTicks) {
                            TimeFormat.timeOfDay(hoursFromMidnight: clock(at: $0))
                        }
                        if !nights.isEmpty {
                            hoursAxis(position: .trailing, every: sleepStep)
                        }
                    }
                }
            }
        }
    }


    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// Signed hours from a day's midnight — the shared scale, unwrapped so it
    /// stays continuous through midnight.
    private func hours(of instant: Date, from day: Date) -> Double {
        instant.timeIntervalSince(day) / 3600
    }

    /// The user's start-time anchor — when they *meant* to stop — as a dashed
    /// line to read the dots against.
    ///
    /// The anchor is a wall-clock time, which sits at either `h` or `h - 24` on
    /// this signed scale depending on whether it falls before or after the
    /// midnight each column is measured from. Rather than guess from the hour,
    /// pick whichever lands nearer the user's own median stop.
    private func anchorHours(median: Double?) -> Double? {
        guard let settings = settingsList.first, let median else { return nil }
        let raw = Double(settings.startReminderHour) + Double(settings.startReminderMinute) / 60
        return abs(raw - median) <= abs((raw - 24) - median) ? raw : raw - 24
    }

    /// Deliberately not "permission denied": HealthKit will not tell us whether
    /// reads were granted, so claiming either way would be a guess.
    private static func noDataMessage(_ what: String) -> String {
        "No \(what) data. If you keep it in Health, allow Fastino to read it — the Settings tab has the switch."
    }

    // MARK: Chart chrome

    private var fastingGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF8A5C)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The left-hand axis of a dual-axis panel: labels for the projected
    /// series, at positions already mapped onto the chart's own scale.
    ///
    /// The values are chosen in the series' own units and projected, because
    /// `.automatic` on a borrowed scale lands on arbitrary fractions of it —
    /// and "-3.5h" is not a time anyone recognises, nor "79.34" a weight.
    ///
    /// No grid line: the lines across these panels belong to the hours axis
    /// the bars are measured against, and a second set at these ticks would
    /// invite reading a bar's top in the wrong units.
    private func overlayAxis(at values: [Double], label: @escaping (Double) -> String) -> some AxisContent {
        AxisMarks(position: .leading, values: values) { value in
            AxisValueLabel {
                if let projected = value.as(Double.self) {
                    Text(label(projected))
                        .font(.flameFixed(10, .bold))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
        }
    }

    /// `every` pins the ticks to whole hours, which the night panel needs: its
    /// scale is sized to the longest night, and `.automatic` on that domain
    /// labels 0h and 5h and leaves the reader to guess where the bars end.
    private func hoursAxis(position: AxisMarkPosition = .leading, every: Double? = nil) -> some AxisContent {
        AxisMarks(position: position, values: every.map { .stride(by: $0) } ?? .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Theme.divider)
            AxisValueLabel {
                if let hours = value.as(Double.self) {
                    Text("\(Int(hours))h")
                        .font(.flameFixed(10, .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// One panel, one pairing. Both panels draw the date labels: the axis is
    /// shared, but the weekly bars are unreadable without their weeks named,
    /// and the labels land on the same week boundaries in both.
    private struct Panel<Content: View>: View {
        let title: String
        let caption: String
        /// Series key, for the one panel carrying two of them.
        var legend: [LegendItem] = []
        /// Shown under the key when one of the panel's series has no data.
        var note: String?
        /// Every panel is scaled to the same 30 days, so the plot areas line up
        /// column for column even when one series has fewer points.
        let domain: ClosedRange<Date>
        var height: CGFloat = 96
        let showsDateAxis: Bool
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).flameSectionLabel()
                    Spacer()
                    Text(caption)
                        .font(.flame(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                if !legend.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(legend) { item in
                            HStack(spacing: 5) {
                                // The swatch takes the shape of the mark it
                                // stands for — a dot for events, a bar for the
                                // stretch of time.
                                Group {
                                    if item.isBar {
                                        RoundedRectangle(cornerRadius: 2)
                                            .frame(width: 7, height: 14)
                                    } else {
                                        Circle().frame(width: 7, height: 7)
                                    }
                                }
                                .foregroundStyle(item.color)
                                Text(item.label)
                                    .font(.flame(11.5, .semibold, relativeTo: .caption2))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                if let note {
                    Text(note)
                        .font(.flame(12.5, .semibold, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                content
                    .chartXScale(domain: domain)
                    .chartXAxis {
                        // Real week boundaries rather than every seventh day
                        // from the window's edge, so the grid lines agree with
                        // the weekly bars — and with the user's own calendar.
                        AxisMarks(values: .stride(by: .weekOfYear)) { value in
                            AxisGridLine().foregroundStyle(Theme.divider)
                            if showsDateAxis {
                                AxisValueLabel {
                                    if let date = value.as(Date.self) {
                                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.flameFixed(10, .bold))
                                            .foregroundStyle(Theme.muted)
                                            // Without this the last label, sitting
                                            // near the plot's edge, truncates.
                                            .fixedSize()
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: height)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flameCard()
        }
    }


    private struct LegendItem: Identifiable {
        let color: Color
        let label: String
        let isBar: Bool

        var id: String { label }
    }

    private struct EmptyPanelMessage: View {
        let text: String
        init(_ text: String) { self.text = text }

        var body: some View {
            Text(text)
                .font(.flame(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// `simctl` can't tap, so a pushed screen is unreachable on a booted simulator —
// these previews are how this screen gets looked at, in both schemes.
#Preview("Health panels — light") {
    ScrollView { HealthPanels(provider: FixtureHealthProvider()).padding() }
        .background(FlameBackground(resting: true))
        .modelContainer(AppContainer.inMemory())
        .preferredColorScheme(.light)
}

#Preview("Health panels — dark") {
    ScrollView { HealthPanels(provider: FixtureHealthProvider()).padding() }
        .background(FlameBackground(resting: true))
        .modelContainer(AppContainer.inMemory())
        .preferredColorScheme(.dark)
}

#Preview("Health panels — no health data") {
    ScrollView { HealthPanels(provider: FixtureHealthProvider(series: .empty)).padding() }
        .background(FlameBackground(resting: true))
        .modelContainer(AppContainer.inMemory())
        .preferredColorScheme(.light)
}

private extension Optional {
    /// `Optional.filter` — keeps the value only when it passes.
    func filter(_ isIncluded: (Wrapped) -> Bool) -> Wrapped? {
        flatMap { isIncluded($0) ? $0 : nil }
    }
}
