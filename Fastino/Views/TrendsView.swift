//
//  TrendsView.swift
//  Fastino
//
//  The Trends screen (§4.8): the last 30 days of fasting with sleep and weight
//  from Apple Health stacked underneath, sharing one date axis so the three
//  series can be read against each other.
//
//  Three separate panels rather than one dual-axis plot, on purpose: hours and
//  kilograms have nothing to do with each other, and overlaying two scales in
//  one frame invites reading a crossing as a correlation.
//
//  Pushed from the Stats tab, like History — §4.3 keeps the Stats screen itself
//  to essentials, and this is a screen you go looking for.
//
//  This is the one screen in the app that uses Swift Charts. Thirty aligned
//  bars plus a line with a real date axis is what it's for; the seven-day strip
//  on Stats stays hand-drawn, because it's a designed object rather than a
//  chart. Everything here is still styled from `Theme` tokens only.
//

import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    /// Injected so previews and the fixture can drive the screen without
    /// HealthKit. The app always gets the real one.
    var provider: HealthProvider = HealthKitProvider.shared

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]

    @State private var series: HealthSeries = .empty
    @State private var isLoading = true

    @Environment(\.colorScheme) private var colorScheme

    private static let dayCount = 30
    /// The weight correlation is weekly, so it needs months, not weeks —
    /// see `HealthCorrelation.weightVsFasting`.
    private static let weightDayCount = 90

    private var referenceGoalHours: Int {
        fasts.first(where: \.isOpen)?.goalHours
            ?? settingsList.first?.activeProtocol.goalHours
            ?? FastingProtocol.p168.goalHours
    }

    private var bars: [DayBar] {
        FastingEngine.lastDays(fasts.records, now: .now, timeZone: .current, count: Self.dayCount)
    }

    /// The domain every panel is drawn against. Taken from the fasting bars,
    /// which always span the full window, so the three axes line up even when
    /// Health returns nothing.
    private var domain: ClosedRange<Date> {
        let days = bars
        guard let first = days.first?.date, let last = days.last?.date else {
            return Date.now...Date.now.addingTimeInterval(1)
        }
        return first...last.addingTimeInterval(86_400)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                fastingPanel
                nightPanel
                weightPanel

                Text("PATTERNS")
                    .flameSectionLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .padding(.horizontal, 4)
                sleepPatternCard
                weightPatternCard

                footnote
            }
            .padding(.horizontal, FlameLayout.screenHorizontalPadding)
            .padding(.top, FlameLayout.screenTopPadding)
            .flameTabBarClearance()
        }
        .background(FlameBackground(resting: true))
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
        series = await provider.series(
            days: Self.dayCount,
            weightDays: Self.weightDayCount,
            now: .now,
            timeZone: .current
        )
        isLoading = false
    }

    // MARK: Header

    /// No big in-screen title: this is a pushed screen and the navigation bar
    /// already names it, same as History.
    private var header: some View {
        Text("Fasting, sleep and weight over the last 30 days.")
            .font(.flame(14, .semibold, relativeTo: .subheadline))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
    }

    private var footnote: some View {
        Text("Each column is the day a fast ended, so an evening's last meal sits with the night's sleep. Patterns show what went together in your own data \u{2014} not what caused what. Sleep and weight come from Apple Health and stay on this device; Fastino never writes to Health.")
            .font(.flame(12.5, .semibold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    // MARK: Panels

    private var fastingPanel: some View {
        let days = bars.filter { $0.duration > 0 }
        let goal = Double(referenceGoalHours)
        let peak = max(goal, days.map { $0.duration / 3600 }.max() ?? goal)

        return Panel(title: "FASTING", caption: "hours", domain: domain, showsDateAxis: false) {
            if days.isEmpty {
                EmptyPanelMessage("No fasts logged in the last 30 days.")
            } else {
                Chart {
                    ForEach(days) { bar in
                        BarMark(
                            x: .value("Day", bar.date, unit: .day),
                            y: .value("Hours", bar.duration / 3600)
                        )
                        .foregroundStyle(fastingGradient)
                        .opacity(bar.isInProgress && !bar.goalMet ? 0.5 : 1)
                        .accessibilityLabel(bar.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(DurationFormat.hoursMinutes(bar.duration))
                    }
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.accentText.opacity(0.5))
                        .accessibilityHidden(true)
                }
                .chartYScale(domain: 0...(peak * 1.1))
                .chartYAxis { hoursAxis }
            }
        }
    }


    /// The screen's centrepiece: when eating stopped and when sleep happened,
    /// on one clock axis.
    ///
    /// Sleep is drawn as *when* rather than *how much*, which is what lets the
    /// two series share an axis honestly — both are times of day, so there is no
    /// second scale and no crossing to misread. The gap between the dot and the
    /// bar above it is the thing worth looking at: how long after the last meal
    /// sleep actually came.
    private var nightPanel: some View {
        let stops = FastingEngine.eatingStops(
            fasts.records, now: .now, timeZone: .current, count: Self.dayCount
        )
        let nights = series.nights
        let stopValues = stops.map(\.hoursFromMidnight)

        let lows = stopValues + nights.map { hours(of: $0.mainSleepStart, from: $0.date) }
        let highs = nights.map { hours(of: $0.mainSleepEnd, from: $0.date) } + stopValues
        let low = (lows.min() ?? -6) - 1
        let high = (highs.max() ?? 9) + 1

        let planned = anchorHours(median: stopValues.sorted().dropFirst(stopValues.count / 2).first)
        // The dashed line is context, not data. Let it widen the scale a little
        // so "later than planned" is visible, but not so far that everything
        // collapses into a band — a schedule nobody is keeping is exactly when
        // the actual times matter most.
        let anchor = planned.filter { max(high, $0) - min(low, $0) <= (high - low) + 3 }
        let lower = min(low, anchor ?? low)
        let upper = max(high, anchor ?? high)

        return Panel(
            title: "STOPPED EATING & SLEEP",
            caption: "clock time",
            legend: nights.isEmpty ? [LegendItem(color: Theme.brand, label: "stopped eating", isBar: false)] : [
                LegendItem(color: Theme.brand, label: "stopped eating", isBar: false),
                LegendItem(color: Theme.mutedFlame.opacity(0.7), label: "asleep", isBar: true)
            ],
            // Merging the panels cost the sleep series its own empty state, so
            // it says so here instead — otherwise a missing series just looks
            // like a screen with fewer things on it.
            note: nights.isEmpty && !isLoading && !stops.isEmpty ? Self.noDataMessage("sleep") : nil,
            domain: domain,
            height: 132,
            showsDateAxis: false
        ) {
            if stops.isEmpty && nights.isEmpty {
                EmptyPanelMessage(isLoading ? "Reading from Health…" : "Nothing to show yet.")
            } else {
                Chart {
                    ForEach(nights) { night in
                        BarMark(
                            x: .value("Day", night.date, unit: .day),
                            yStart: .value("Asleep", hours(of: night.mainSleepStart, from: night.date)),
                            yEnd: .value("Awake", hours(of: night.mainSleepEnd, from: night.date)),
                            width: .ratio(0.62)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(Theme.mutedFlame.opacity(0.7))
                        .accessibilityLabel(night.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(
                            "asleep \(TimeFormat.timeOfDay(hoursFromMidnight: hours(of: night.mainSleepStart, from: night.date))) to \(TimeFormat.timeOfDay(hoursFromMidnight: hours(of: night.mainSleepEnd, from: night.date))), \(DurationFormat.hoursMinutes(night.asleep)) total"
                        )
                    }

                    ForEach(stops) { stop in
                        LineMark(
                            x: .value("Day", stop.date),
                            y: .value("Stopped", stop.hoursFromMidnight)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(Theme.brand.opacity(0.35))
                        .accessibilityHidden(true)

                        PointMark(
                            x: .value("Day", stop.date),
                            y: .value("Stopped", stop.hoursFromMidnight)
                        )
                        .symbolSize(42)
                        .foregroundStyle(Theme.brand)
                        .accessibilityLabel(stop.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(
                            "stopped eating \(TimeFormat.timeOfDay(hoursFromMidnight: stop.hoursFromMidnight))"
                        )
                    }

                    if let anchor {
                        RuleMark(y: .value("Planned", anchor))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.accentText.opacity(0.5))
                            .accessibilityHidden(true)
                    }
                }
                .chartYScale(domain: lower...upper)
                .chartYAxis {
                    // A night plus an evening spans half a day; two-hour ticks
                    // would stack a dozen labels into the frame.
                    clockAxis(every: upper - lower > 12 ? 4 : 2)
                }
            }
        }
    }


    // MARK: Patterns

    /// Does stopping earlier go with more sleep? One dot per night.
    private var sleepPatternCard: some View {
        let stops = FastingEngine.eatingStops(
            fasts.records, now: .now, timeZone: .current, count: Self.dayCount
        )
        let pairs = HealthCorrelation.sleepVsEatingStop(stops: stops, nights: series.nights)
        let threshold = anchorHours(median: median(of: pairs.map(\.x)))
        let summary = HealthCorrelation.sleepSummary(pairs, threshold: threshold)

        return ScatterCard(
            title: "STOPPING EARLIER & SLEEP",
            summary: summary,
            points: pairs,
            emptyMessage: isLoading ? "Reading from Health…" : "No nights with both a fast and sleep yet.",
            caption: "\(summary.n) \(summary.n == 1 ? "night" : "nights")",
            xTitle: "stopped eating",
            xLabel: { hours, _ in TimeFormat.timeOfDay(hoursFromMidnight: hours) },
            yLabel: { hours, decimals in
                "\(hours.formatted(.number.precision(.fractionLength(decimals))))h"
            },
            ruleX: threshold
        )
    }

    /// Do longer weeks go with weight moving? One dot per week — see
    /// `HealthCorrelation.weightVsFasting` for why this one isn't daily.
    private var weightPatternCard: some View {
        let bars = FastingEngine.lastDays(
            fasts.records, now: .now, timeZone: .current, count: Self.weightDayCount
        )
        let raw = HealthCorrelation.weightVsFasting(
            bars: bars, weights: series.weights, now: .now, timeZone: .current
        )
        // Plotted in the user's unit; the pairing itself stays in kilograms.
        let unit = series.massUnit
        let pairs = raw.map {
            Pairing(date: $0.date, x: $0.x, y: unit.value(fromKilograms: $0.y))
        }
        let summary = HealthCorrelation.weightSummary(raw, goalHours: referenceGoalHours, unit: unit)

        return ScatterCard(
            title: "FASTING & WEIGHT",
            summary: summary,
            points: pairs,
            emptyMessage: isLoading ? "Reading from Health…" : "No weeks with both fasts and weigh-ins yet.",
            caption: "\(summary.n) \(summary.n == 1 ? "week" : "weeks")",
            xTitle: "average fast",
            xLabel: { hours, decimals in
                "\(hours.formatted(.number.precision(.fractionLength(decimals))))h"
            },
            yLabel: { change, decimals in
                change.formatted(
                    .number
                        .precision(.fractionLength(max(decimals, 1)))
                        .sign(strategy: .always(includingZero: false))
                )
            },
            showsZeroLine: true
        )
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

    private var weightPanel: some View {
        let points = series.weights.filter { $0.date >= domain.lowerBound }
        let unit = series.massUnit
        let values = points.map { unit.value(fromKilograms: $0.kilograms) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        // A flat month shouldn't render as a jagged line filling the frame.
        let pad = max((high - low) * 0.25, 0.5)

        return Panel(title: "WEIGHT", caption: unit.symbol, domain: domain, showsDateAxis: true) {
            if isLoading {
                EmptyPanelMessage("Reading from Health…")
            } else if points.isEmpty {
                EmptyPanelMessage(Self.noDataMessage("weight"))
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value(unit.symbol, unit.value(fromKilograms: point.kilograms))
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.accentText)
                    .accessibilityLabel(point.date.formatted(.dateTime.month().day()))
                    .accessibilityValue(
                        Measurement(value: point.kilograms, unit: UnitMass.kilograms)
                            .converted(to: unit.unit)
                            .formatted(.measurement(width: .abbreviated))
                    )

                    PointMark(
                        x: .value("Day", point.date),
                        y: .value(unit.symbol, unit.value(fromKilograms: point.kilograms))
                    )
                    .symbolSize(18)
                    .foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
                }
                .chartYScale(domain: (low - pad)...(high + pad))
                .chartYAxis { valueAxis(decimals: (high - low) < 4 ? 1 : 0) }
            }
        }
    }

    /// Deliberately not "permission denied": HealthKit will not tell us whether
    /// reads were granted, so claiming either way would be a guess.
    private static func noDataMessage(_ what: String) -> String {
        "No \(what) data. If you keep it in Health, allow Fastino to read it in Settings → Privacy → Health."
    }

    // MARK: Chart chrome

    private var fastingGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF8A5C)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Two-hour ticks labelled as clock times. `.automatic` would land on
    /// arbitrary fractions, and "-3.5h" is not a time anyone recognises.
    private func clockAxis(every stride: Double) -> some AxisContent {
        AxisMarks(position: .leading, values: .stride(by: stride)) { value in
            AxisGridLine().foregroundStyle(Theme.divider)
            AxisValueLabel {
                if let hours = value.as(Double.self) {
                    Text(TimeFormat.timeOfDay(hoursFromMidnight: hours))
                        .font(.flameFixed(10, .bold))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
        }
    }

    private var hoursAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
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

    /// A month of weight often spans less than a unit, where whole numbers
    /// would print the same label three times.
    private func valueAxis(decimals: Int) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Theme.divider)
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(number.formatted(.number.precision(.fractionLength(decimals))))
                        .font(.flameFixed(10, .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// One card, one series. Only the bottom panel draws the date labels — the
    /// axis is shared, so repeating it three times would be noise.
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
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
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


    /// One correlation: a sentence, the dots it came from, and how many.
    ///
    /// The fit line is drawn exactly when `summary.fit` is present, which the
    /// pure layer only fills in once there are enough points *and* the
    /// relationship is strong enough to describe. A weak result therefore can
    /// never appear under a confident-looking line.
    private struct ScatterCard: View {
        let title: String
        let summary: PatternSummary
        let points: [Pairing]
        let emptyMessage: String
        let caption: String
        let xTitle: String
        let xLabel: (Double, Int) -> String
        let yLabel: (Double, Int) -> String
        var ruleX: Double?
        var showsZeroLine = false

        private var xDomain: ClosedRange<Double> {
            let values = points.map(\.x) + [ruleX].compactMap { $0 }
            guard let low = values.min(), let high = values.max(), high > low else {
                return (values.first ?? 0) - 1 ... (values.first ?? 0) + 1
            }
            let pad = (high - low) * 0.12
            return (low - pad)...(high + pad)
        }

        private var yDomain: ClosedRange<Double> {
            let values = points.map(\.y) + (showsZeroLine ? [0] : [])
            guard let low = values.min(), let high = values.max(), high > low else {
                return (values.first ?? 0) - 1 ... (values.first ?? 0) + 1
            }
            let pad = (high - low) * 0.15
            return (low - pad)...(high + pad)
        }

        /// A "nice" tick spacing for the y axis. `.automatic` collapses a range
        /// of ±0.3 kg to a single zero tick however many ticks it's asked for,
        /// which tells the reader nothing about the scale.
        private var yStride: Double {
            let span = yDomain.upperBound - yDomain.lowerBound
            guard span > 0 else { return 1 }
            let rough = span / 4
            let magnitude = pow(10, (log10(rough)).rounded(.down))
            let normalised = rough / magnitude
            let nice: Double = normalised < 1.5 ? 1 : normalised < 3 ? 2 : normalised < 7 ? 5 : 10
            return nice * magnitude
        }

        /// Whole numbers repeat themselves over a range this narrow — a month of
        /// weekly fast averages spans about an hour.
        private func decimals(for range: ClosedRange<Double>) -> Int {
            range.upperBound - range.lowerBound < 3 ? 1 : 0
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).flameSectionLabel()

                Text(summary.headline)
                    .font(.flame(15, .extraBold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                if points.isEmpty {
                    Text(emptyMessage)
                        .font(.flame(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 10)
                } else {
                    chart
                        .frame(height: 130)
                        .padding(.top, 12)
                        .padding(.trailing, 10)

                    HStack {
                        Text(xTitle)
                        Spacer()
                        Text(caption)
                    }
                    .font(.flame(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flameCard()
        }

        private var chart: some View {
            Chart {
                if showsZeroLine {
                    RuleMark(y: .value("No change", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Theme.divider)
                        .accessibilityHidden(true)
                }
                if let ruleX {
                    RuleMark(x: .value("Target", ruleX))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.accentText.opacity(0.5))
                        .accessibilityHidden(true)
                }
                if let fit = summary.fit {
                    ForEach([xDomain.lowerBound, xDomain.upperBound], id: \.self) { x in
                        LineMark(
                            x: .value("Fit", x),
                            y: .value("Fit", fit.y(at: x)),
                            series: .value("Series", "fit")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                    }
                }
                ForEach(points) { point in
                    PointMark(
                        x: .value(xTitle, point.x),
                        y: .value("Value", point.y)
                    )
                    .symbolSize(46)
                    .foregroundStyle(Theme.brand)
                    .accessibilityLabel(xLabel(point.x, decimals(for: xDomain)))
                    .accessibilityValue(yLabel(point.y, decimals(for: yDomain)))
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Theme.divider)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(xLabel(number, decimals(for: xDomain)))
                                .font(.flameFixed(10, .bold))
                                .foregroundStyle(Theme.muted)
                                .fixedSize()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: yStride)) { value in
                    AxisGridLine().foregroundStyle(Theme.divider)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(yLabel(number, decimals(for: yDomain)))
                                .font(.flameFixed(10, .bold))
                                .foregroundStyle(Theme.muted)
                                .fixedSize()
                        }
                    }
                }
            }
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
#Preview("Trends — light") {
    NavigationStack {
        TrendsView(provider: FixtureHealthProvider())
    }
    .modelContainer(AppContainer.inMemory())
    .preferredColorScheme(.light)
}

#Preview("Trends — dark") {
    NavigationStack {
        TrendsView(provider: FixtureHealthProvider())
    }
    .modelContainer(AppContainer.inMemory())
    .preferredColorScheme(.dark)
}

#Preview("Trends — no health data") {
    NavigationStack {
        TrendsView(provider: FixtureHealthProvider(series: .empty))
    }
    .modelContainer(AppContainer.inMemory())
    .preferredColorScheme(.light)
}

private extension Optional {
    /// `Optional.filter` — keeps the value only when it passes.
    func filter(_ isIncluded: (Wrapped) -> Bool) -> Wrapped? {
        flatMap { isIncluded($0) ? $0 : nil }
    }
}
