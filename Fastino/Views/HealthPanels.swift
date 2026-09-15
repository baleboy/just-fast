//
//  HealthPanels.swift
//  Fastino
//
//  The Apple Health section of the Stats screen (§4.8): the last thirty days of
//  fasting with sleep and weight from Health, as two panels — weight over the
//  week's fasting hours on a date axis, and one dot per night of when eating
//  stopped against how long the sleep after it was.
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
//  thing worth reading it against (weight, sleep).
//
//  The two panels reach that differently, and deliberately. Weight and hours
//  genuinely have no common unit, so `fastingWeightPanel` is dual-axis and the
//  contract on it is what keeps the two honest. `sleepScatterPanel` puts its
//  two facts on the two axes instead, one dot a night, because the thing it's
//  for — does stopping earlier go with sleeping longer — is a question about
//  quantities, and a timeline of the same two facts couldn't be read for it.
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

    /// The date domain the fasting/weight panel is drawn against. Taken from
    /// the fasting bars, which always span the full window, so the axis is the
    /// same even when Health returns nothing.
    ///
    /// **Snapped out to whole weeks.** The bars are weekly, and a week-wide bar
    /// hanging off a mid-week edge is drawn over the axis labels rather than
    /// clipped tidily. Snapping also puts every grid line on a real week
    /// boundary. The window is still thirty days of *data*; it just starts on
    /// the user's first day of the week.
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
            sleepScatterPanel
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
        Text("The top panel is by the week \u{2014} day to day, weight is mostly water, and one fast can't have moved a week's average. Below it, every night is one dot: across, when you stopped eating; up, how long you slept after. Patterns show what went together in your own data \u{2014} not what caused what. Sleep and weight come from Apple Health and stay on this device; Fastino never writes to Health.")
            .font(.flame(12.5, .semibold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    // MARK: Panels

    /// Fasting hours with weight laid over them — the sleep panel's pairing,
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


    /// The screen's centrepiece: one dot for each night — across, when eating
    /// stopped; up, how long the sleep that followed was.
    ///
    /// **A scatter, because the question is about quantity.** This panel was a
    /// timeline — a dot for the stop and a band for the night, on a shared
    /// clock axis over thirty dated columns — and it couldn't be read for the
    /// one thing it was drawn for: whether stopping earlier goes with sleeping
    /// more. Hours asleep only existed there as the length of a band, which
    /// the eye can't compare across thirty columns, so the user looked at a
    /// month of their own data and couldn't tell. Here the two facts are the
    /// two axes, so an earlier-stop-longer-sleep month is a cloud that slopes
    /// down to the right, and a month where it made no difference is a cloud
    /// with no slope — either of which is visible at a glance.
    ///
    /// **No fitted line, no headline, no number.** The scatter is the drawing
    /// the "show what happened, the user interprets" rule allows; what it
    /// forbids is a computed claim about one series explaining the other, and
    /// that's what was cut with the old Trends screen (IMPLEMENTATION.md). The
    /// dashed rule is the user's own planned stop time, so a dot to its right
    /// reads as late.
    ///
    /// The dot's height is the day's **total** asleep — naps and all, overlaps
    /// counted once — rather than the span of the main night: "how much did I
    /// sleep" is the question, and a 40-minute nap after a short night is part
    /// of the answer. Only nights with both a stop and a sleep are drawn; a day
    /// with one and not the other has nothing to plot against.
    private var sleepScatterPanel: some View {
        let stops = FastingEngine.eatingStops(
            fasts.records, now: .now, timeZone: .current, count: Self.dayCount
        )
        let nights = series.nights
        let nightsByDay = Dictionary(nights.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let paired: [(stop: EatingStop, night: SleepNight)] = stops.compactMap { stop in
            nightsByDay[stop.date].map { (stop: stop, night: $0) }
        }
        let points = paired.map { (stop: $0.stop.hoursFromMidnight, asleep: $0.night.hours) }
        let anchor = anchorHours(median: median(of: stops.map(\.hoursFromMidnight)))
        let scale = SleepScatterScale.scale(nights: points, anchor: anchor)
        // The one summary: the average night either side of the planned stop.
        // Two means read against the user's own line — not a fit, and never a
        // "because". Absent when either side is too thin to average.
        let split = SleepSplit.summary(nights: points, anchor: scale?.anchor)

        return Panel(
            title: "STOPPED EATING & SLEEP",
            caption: "one dot a night",
            // A missing series would otherwise just look like a screen with
            // fewer things on it.
            note: nights.isEmpty && !isLoading && !stops.isEmpty ? Self.noDataMessage("sleep") : nil,
            domain: nil,
            height: 132,
            showsDateAxis: false,
            content: {
            if let scale {
                Chart {
                    // The time they meant to stop, so a dot to its right reads
                    // as late. Drawn first, so it sits under the dots.
                    if let anchor = scale.anchor {
                        RuleMark(x: .value("Planned", anchor))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.accentText.opacity(0.5))
                            .accessibilityHidden(true)
                    }

                    // Each side's mean, as a level running the width of that
                    // side, so the comparison is a glance before it's a number.
                    if let split {
                        RuleMark(
                            xStart: .value("From", scale.xDomain.lowerBound),
                            xEnd: .value("To", split.threshold),
                            y: .value("Average asleep", split.earlier.meanHours)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(Theme.accentText.opacity(0.55))
                        .accessibilityHidden(true)
                        RuleMark(
                            xStart: .value("From", split.threshold),
                            xEnd: .value("To", scale.xDomain.upperBound),
                            y: .value("Average asleep", split.later.meanHours)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(Theme.accentText.opacity(0.55))
                        .accessibilityHidden(true)
                    }

                    ForEach(paired, id: \.stop.id) { pair in
                        PointMark(
                            x: .value("Stopped", pair.stop.hoursFromMidnight),
                            y: .value("Asleep", pair.night.hours)
                        )
                        .symbolSize(42)
                        // Not quite opaque, so two nights that landed on the
                        // same spot read as one darker dot rather than one.
                        .foregroundStyle(Theme.brand.opacity(0.85))
                        .accessibilityLabel(pair.stop.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(
                            "stopped eating \(TimeFormat.timeOfDay(hoursFromMidnight: pair.stop.hoursFromMidnight)), \(DurationFormat.hoursMinutes(pair.night.asleep)) asleep"
                        )
                    }
                }
                .chartXScale(domain: scale.xDomain)
                .chartYScale(domain: scale.yDomain)
                .chartXAxis { stopAxis(at: scale.xTicks) }
                .chartYAxis { hoursAxis(values: scale.yTicks) }
                // A stop that doesn't set the scale (`SleepScatterScale`'s ±8h
                // rule) can still fall outside it, and Swift Charts will
                // happily draw a `PointMark` outside the plot area — a dot
                // floating beside the card, which reads as a bug rather than as
                // data. Clipped, it stays in the accessibility tree and out of
                // the picture.
                .chartPlotStyle { $0.clipped() }
            } else {
                EmptyPanelMessage(isLoading ? "Reading from Health\u{2026}" : "Nothing to show yet.")
            }
        }, summary: {
            // The same two means as the levels on the chart, as a pair of
            // tiles: the numbers are the panel's answer, and a sentence in
            // the caption face was the least visible thing on the screen.
            if let split {
                let time = TimeFormat.timeOfDay(hoursFromMidnight: split.threshold)
                HStack(spacing: 10) {
                    SplitTile(
                        label: "STOPPED BY \(time)",
                        hours: split.earlier.meanHours,
                        nights: split.earlier.nights
                    )
                    SplitTile(
                        label: "AFTER \(time)",
                        hours: split.later.meanHours,
                        nights: split.later.nights
                    )
                }
                if !split.isAnchor {
                    Text("Split at your usual stop time.")
                        .font(.flame(12, .semibold, relativeTo: .caption2))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 6)
                }
            }
        })
    }

    /// One side of the split: the average night, and how many nights it's
    /// made of. The bento's label / number / caption stack, on the peach
    /// surface the goal-rate card uses, without a shadow — it sits inside the
    /// panel's card, not on the page.
    private struct SplitTile: View {
        let label: String
        let hours: Double
        let nights: Int

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let palette = Theme.palette(for: colorScheme)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .flameSectionLabel(palette.onAccentSurface.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(DurationFormat.hoursMinutes(hours * 3600))
                    .font(.flame(26, .extraBold, relativeTo: .title2))
                    .foregroundStyle(palette.accentText.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                Text("average over \(nights) nights")
                    .font(.flame(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(palette.onAccentSurface.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(palette.accentSurface.color, in: .rect(cornerRadius: Radius.smallCard))
            .accessibilityElement(children: .combine)
        }
    }

    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
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

    /// The left-hand axis of the weight panel: labels for the projected weight
    /// series, at positions already mapped onto the hours scale the chart is
    /// drawn in.
    ///
    /// The values are chosen in kilograms and projected, because `.automatic`
    /// on a borrowed scale lands on arbitrary fractions of it, and "79.34" is
    /// not a weight anyone recognises.
    ///
    /// No grid line: the lines across that panel belong to the hours axis the
    /// bars are measured against, and a second set at these ticks would invite
    /// reading a bar's top in the wrong units. The scatter has no such
    /// problem — it has one scale — and draws its own lines in `stopAxis`.
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

    /// An hours axis — the scale the weight panel's bars are grounded in, and
    /// the only one in that panel allowed to draw grid lines; and the scatter's
    /// y axis, where it's the only scale there is.
    ///
    /// The scatter passes its ticks, chosen on whole hours by
    /// `SleepScatterScale`; the weight panel leaves them to `.automatic`.
    @AxisContentBuilder
    private func hoursAxis(position: AxisMarkPosition = .leading, values: [Double]? = nil) -> some AxisContent {
        if let values {
            AxisMarks(position: position, values: values) { value in hoursMark(value) }
        } else {
            AxisMarks(position: position, values: .automatic(desiredCount: 3)) { value in hoursMark(value) }
        }
    }

    @AxisMarkBuilder
    private func hoursMark(_ value: AxisValue) -> some AxisMark {
        AxisGridLine().foregroundStyle(Theme.divider)
        AxisValueLabel {
            if let hours = value.as(Double.self) {
                Text("\(Int(hours))h")
                    .font(.flameFixed(10, .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// The scatter's x axis: the clock time eating stopped, labelled at whole
    /// hours. `TimeFormat.timeOfDay` wraps the signed values, so an evening
    /// stop measured as −4 is printed as 20.00.
    ///
    /// It draws grid lines where `overlayAxis` must not: that axis labels a
    /// series projected into someone else's scale, where a line would invite
    /// reading a bar top in the wrong units; this one *is* the chart's scale.
    private func stopAxis(at values: [Double]) -> some AxisContent {
        AxisMarks(position: .bottom, values: values) { value in
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

    /// One panel, one pairing. A panel with a `domain` is drawn over the
    /// shared 30-day date axis, week lines and labels included; one without it
    /// brings its own x axis.
    private struct Panel<Content: View, Summary: View>: View {
        let title: String
        let caption: String
        /// Series key, for the one panel carrying two of them.
        var legend: [LegendItem] = []
        /// Shown under the key when one of the panel's series has no data.
        var note: String?
        /// Shown under the chart: the panel's one summary of what it drew.
        let summary: Summary
        /// The shared 30-day window, for a panel drawn against dates. `nil`
        /// for one whose x axis is something else — it sets its own.
        let domain: ClosedRange<Date>?
        var height: CGFloat = 96
        let showsDateAxis: Bool
        let content: Content

        init(
            title: String,
            caption: String,
            legend: [LegendItem] = [],
            note: String? = nil,
            domain: ClosedRange<Date>?,
            height: CGFloat = 96,
            showsDateAxis: Bool,
            @ViewBuilder content: () -> Content,
            @ViewBuilder summary: () -> Summary
        ) {
            self.title = title
            self.caption = caption
            self.legend = legend
            self.note = note
            self.domain = domain
            self.height = height
            self.showsDateAxis = showsDateAxis
            self.content = content()
            self.summary = summary()
        }

        init(
            title: String,
            caption: String,
            legend: [LegendItem] = [],
            note: String? = nil,
            domain: ClosedRange<Date>?,
            height: CGFloat = 96,
            showsDateAxis: Bool,
            @ViewBuilder content: () -> Content
        ) where Summary == EmptyView {
            self.init(
                title: title, caption: caption, legend: legend, note: note,
                domain: domain, height: height, showsDateAxis: showsDateAxis,
                content: content, summary: { EmptyView() }
            )
        }

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
                dated(content)
                    .frame(height: height)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                summary
                    .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flameCard()
        }

        @ViewBuilder
        private func dated(_ content: Content) -> some View {
            if let domain {
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
            } else {
                content
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
