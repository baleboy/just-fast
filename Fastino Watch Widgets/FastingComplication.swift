//
//  FastingComplication.swift
//  FastinoWatchWidgets
//
//  The watch complication (§4.7): fasting state and progress at a glance, and
//  a tap opens the app.
//
//  Reads the shared store read-only through `AppContainer.readOnly()` — the
//  extension is a separate process, which is why the store lives in an app
//  group. Refreshes come from `FastStore.reloadWidgets()`, which already runs
//  on every mutation, so the complication updates the moment a fast starts or
//  ends on this device.
//
//  Between those reloads the timeline carries its own entries: a running fast
//  changes appearance at each metabolic-zone boundary and at the goal, and
//  those instants are known in advance, so they're scheduled rather than
//  polled. `Text(timerInterval:)` renders the elapsed time without waking us
//  at all.
//

import SwiftData
import SwiftUI
import WidgetKit

struct FastingEntry: TimelineEntry {
    let date: Date
    /// `nil` when no fast is running — the complication shows the ready state.
    let fast: FastRecord?

    var elapsed: TimeInterval? { fast?.duration(asOf: date) }
    var zone: MetabolicZone? { elapsed.map(MetabolicZone.current(elapsed:)) }
    /// Clamped: past the goal the ring stays full rather than wrapping around.
    var progress: Double {
        guard let fast, let elapsed else { return 0 }
        return min(elapsed / fast.goalInterval, 1)
    }
}

struct FastingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry {
        FastingEntry(
            date: Date(),
            fast: FastRecord(
                id: UUID(),
                start: Date().addingTimeInterval(-10 * 3600),
                end: nil,
                goalHours: 16
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(currentEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let now = Date()
        // Fetched once and reused for every entry: they all describe the same
        // fast at different instants, so re-reading the store per entry would
        // be ~50 fetches for one timeline.
        let openFast = Self.openFast()
        let entry = FastingEntry(date: now, fast: openFast)

        guard let fast = openFast else {
            // Nothing running: nothing changes until the app tells us it has.
            completion(Timeline(entries: [entry], policy: .never))
            return
        }

        // Every instant the display changes, all of them known in advance:
        //
        //  • each hour mark, because the label is a whole-hour count. Omitting
        //    these was a bug — the timeline would sit on "9h" for hours.
        //  • the zone boundaries, which change the rectangular family's title.
        //  • the goal, where the ring fills.
        //
        // Capped at 48h: a fast that long is already past anything the app
        // considers valid, and WidgetKit won't thank us for a huge timeline.
        let hourMarks = (1...48).map { fast.start.addingTimeInterval(Double($0) * 3600) }
        let zoneMarks = MetabolicZone.allCases.map {
            fast.start.addingTimeInterval($0.startHours * 3600)
        }

        let dates = Set(hourMarks + zoneMarks + [fast.goalReachedAt])
            .filter { $0 > now }
            .sorted()

        let entries = [entry] + dates.map { FastingEntry(date: $0, fast: fast) }
        // The fast ending is not predictable, so there's no useful refresh date
        // to ask for — FastStore.reloadWidgets() drives that instead.
        completion(Timeline(entries: entries, policy: .never))
    }

    private func currentEntry(at date: Date) -> FastingEntry {
        FastingEntry(date: date, fast: Self.openFast())
    }

    /// Fetched fresh each call: the extension is short-lived and holding a
    /// container across invocations would just serve stale data.
    private static func openFast() -> FastRecord? {
        guard let container = AppContainer.readOnly() else { return nil }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Fast>(
            predicate: #Predicate { $0.end == nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.record
    }
}

// MARK: - Views

struct FastingComplicationView: View {
    @Environment(\.widgetFamily) private var family
    /// Watch *faces* render complications `.accented` or `.vibrant`, which
    /// discard colour — but Smart Stack widgets get `.fullColor`. So rather
    /// than designing for the monochrome worst case everywhere, the zone
    /// colours come through wherever the system will actually show them.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: FastingEntry

    /// The zone's flame colours, or the gold of the first zone when idle.
    private var zoneColors: (from: Color, to: Color) {
        let palette = FlamePalette.of(.dark)
        let zone = entry.zone ?? .burning
        let colors = palette.zones[zone.rawValue]
        return (colors.from.color, colors.to.color)
    }

    /// In accented/vibrant the system tints everything itself, and asking for
    /// our own colour there produces muddy or invisible results.
    private var usesColor: Bool { renderingMode == .fullColor }

    private var bodyStyle: AnyShapeStyle {
        usesColor
            ? AnyShapeStyle(LinearGradient(
                colors: [zoneColors.from, zoneColors.to],
                startPoint: .top,
                endPoint: .bottom
            ))
            : AnyShapeStyle(.foreground)
    }

    /// The mascot: the app's `BlobShape` silhouette with its face punched
    /// *through* the body rather than drawn on it.
    ///
    /// Drawing the face in ink would work in full colour and vanish everywhere
    /// else — accented and vibrant rendering collapse the whole view to one
    /// tint, so dark-on-flame becomes flame-on-flame. Holes read in every mode,
    /// because they show whatever is behind the complication.
    ///
    /// The features are deliberately chunkier than `FlameMascot`'s. Its
    /// proportions are tuned for 40pt and up, where an eye is 0.122 of the
    /// width; at complication scale that lands under a point and disappears.
    private var mascot: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                BlobShape.body.fill(bodyStyle)

                Group {
                    Ellipse()
                        .frame(width: w * 0.17, height: h * 0.19)
                        .position(x: w * 0.33, y: h * 0.46)
                    Ellipse()
                        .frame(width: w * 0.17, height: h * 0.19)
                        .position(x: w * 0.67, y: h * 0.46)
                    ComplicationSmile()
                        .stroke(style: StrokeStyle(lineWidth: max(1, w * 0.085), lineCap: .round))
                        .frame(width: w * 0.34, height: h * 0.09)
                        .position(x: w * 0.5, y: h * 0.64)
                }
                .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .aspectRatio(74.0 / 86.0, contentMode: .fit)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            // The curved label carries the zone, not the hours — the gauge is
            // already showing those, and repeating them wastes the one extra
            // piece of information this family affords.
            circular.widgetLabel { Text(entry.zone?.name ?? "Ready") }
        case .accessoryInline:
            Text(inlineLabel)
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    /// The headline family: a progress ring carrying the zone's colour.
    ///
    /// Deliberately not FlameRing — that draws the full gold→orange→pink scale
    /// with a glow across one ring, which turns to mud at 30pt and is thrown
    /// away entirely in accented and vibrant rendering. A single flat Gauge in
    /// the *current* zone's colour keeps the palette's meaning at this size.
    private var circular: some View {
        Gauge(value: entry.progress) {
            mascot
        } currentValueLabel: {
            if entry.fast == nil {
                // An empty ring plus a dash reads as "broken"; the mascot reads
                // as "nothing running, tap to start".
                mascot.padding(1)
            } else {
                Text(shortLabel)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(usesColor ? zoneColors.to : nil)
        .widgetAccentable()
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            mascot
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.fast == nil ? "Not fasting" : (entry.zone?.name ?? "Fasting"))
                    .font(.headline)
                    .foregroundStyle(usesColor ? zoneColors.to : .primary)
                    .widgetAccentable()
                if let fast = entry.fast {
                    Text(timerInterval: fast.start...Date.distantFuture, countsDown: false)
                        .font(.body)
                    ProgressView(value: entry.progress)
                        .progressViewStyle(.linear)
                        .tint(usesColor ? zoneColors.to : nil)
                } else {
                    Text("Tap to start")
                        .font(.body)
                }
            }
        }
    }

    /// Hours only. A complication is read in a glance, and minutes on a fast
    /// measured in hours are noise.
    private var shortLabel: String {
        guard let elapsed = entry.elapsed else { return "—" }
        return "\(Int(elapsed / 3600))h"
    }

    private var inlineLabel: String {
        guard let fast = entry.fast, let elapsed = entry.elapsed else { return "Not fasting" }
        return "Fasting \(Int(elapsed / 3600))h of \(fast.goalHours)h"
    }
}

/// The same quad-curve smile `FlameMascot` draws, duplicated because the app's
/// version is file-private to `FlameMascot.swift`. Keep the control point in
/// step if that one ever changes.
private struct ComplicationSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
        )
        return path
    }
}

// MARK: - Widget

struct FastingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FastingComplication", provider: FastingProvider()) { entry in
            FastingComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fast")
        .description("How far into your fast you are.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    FastingComplication()
} timeline: {
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-10 * 3600), end: nil, goalHours: 16))
    FastingEntry(date: .now, fast: nil)
}

#Preview("Circular — ready", as: .accessoryCircular) {
    FastingComplication()
} timeline: {
    FastingEntry(date: .now, fast: nil)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    FastingComplication()
} timeline: {
    FastingEntry(date: .now, fast: FastRecord(id: UUID(), start: .now.addingTimeInterval(-15 * 3600), end: nil, goalHours: 16))
    FastingEntry(date: .now, fast: nil)
}
