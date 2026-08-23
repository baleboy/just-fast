//
//  HistoryView.swift
//  Fastino
//
//  Reverse-chronological history grouped by month (§4.3), its own tab. Tap a
//  row to edit; the + adds a missed fast retroactively (§4.2).
//
//  It draws its own title and + rather than using a navigation bar: it sits
//  beside three other chrome-less tabs, and a system bar here would be the one
//  screen with a different silhouette.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    @State private var editing: Fast?
    @State private var addingManual = false

    private var sections: [(title: String, fasts: [Fast])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: fasts) { fast in
            calendar.dateComponents([.year, .month], from: fast.start)
        }
        return groups
            .sorted { lhs, rhs in
                (lhs.key.year ?? 0, lhs.key.month ?? 0) > (rhs.key.year ?? 0, rhs.key.month ?? 0)
            }
            .map { key, value in
                let date = calendar.date(from: key) ?? .now
                let title = date.formatted(.dateTime.month(.wide).year())
                return (title, value.sorted { $0.start > $1.start })
            }
    }

    var body: some View {
        ZStack {
            FlameBackground(resting: true)
            VStack(spacing: 0) {
                header
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { fast in
            EditFastView(mode: .edit(fast))
        }
        .sheet(isPresented: $addingManual) {
            EditFastView(mode: .add)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("History").flameScreenTitle()
            Button {
                addingManual = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: .circle)
            }
            .buttonStyle(FlamePressStyle())
            .accessibilityLabel("Add a fast")
        }
        .padding(.horizontal, FlameLayout.screenHorizontalPadding)
        .padding(.top, FlameLayout.screenTopPadding)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if fasts.isEmpty {
            ContentUnavailableView(
                "No fasts yet",
                systemImage: "timer",
                description: Text("Your logged fasts will appear here.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.fasts) { fast in
                            Button {
                                editing = fast
                            } label: {
                                HistoryRow(fast: fast)
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            // A List can't pad its own content the way the other screens pad
            // the stack inside their ScrollView, so the room for the floating
            // bar goes on as safe area — the last row still scrolls clear of
            // it, rather than the list stopping short.
            .flameTabBarSafeArea()
        }
    }
}

private struct HistoryRow: View {
    let fast: Fast

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fast.start.formatted(.dateTime.month().day().hour().minute()))
                    .font(.flame(16, .extraBold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                if let end = fast.end {
                    Text("→ \(end.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("In progress")
                        .font(.caption)
                        .foregroundStyle(Theme.accentText)
                }
                if let noteLine {
                    Text(noteLine)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .italic()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            // The duration and badge keep their width; a long note truncates
            // rather than pushing them off the row.
            VStack(alignment: .trailing, spacing: 4) {
                Text(durationText)
                    .font(.flame(16, .extraBold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                badge
            }
            .layoutPriority(1)
        }
        .contentShape(.rect)
    }

    /// The note's first line, for the row — the whole note belongs to the edit
    /// sheet, and a row that grew with it would break the month list's rhythm.
    ///
    /// First line with something *on* it rather than literally the first: a note
    /// that opens with a blank line would otherwise reserve the space and show
    /// nothing. Truncation is left to `lineLimit(1)`, which elides at whatever
    /// width the row actually has instead of at a character count guessed here.
    private var noteLine: String? {
        guard let note = fast.note else { return nil }
        return note
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    private var durationText: String {
        if let d = fast.record.finalDuration {
            return DurationFormat.hoursMinutes(d)
        }
        return "—"
    }

    /// Marker *after* the label, not before it.
    ///
    /// The row is trailing-aligned and the three labels are three different
    /// widths, so a leading icon lands at a different x on every row and the
    /// column of markers reads as ragged. Trailing, they line up under the
    /// duration's right edge — and the fixed width keeps them there whichever
    /// symbol is drawn. The text carries the meaning, so the symbol is hidden
    /// from VoiceOver rather than announced twice.
    private var badge: some View {
        let (title, symbol, tint): (String, String, Color) =
            if fast.isOpen {
                ("Open", "circle.dashed", Theme.accentText)
            } else if fast.record.isGoalMet {
                ("Goal met", "checkmark.circle.fill", Theme.success)
            } else {
                ("Under goal", "circle", Theme.muted)
            }

        return HStack(spacing: 5) {
            Text(title)
            Image(systemName: symbol)
                .frame(width: 12)
                .accessibilityHidden(true)
        }
        .font(.caption2)
        .foregroundStyle(tint)
    }
}

#Preview {
    let container = AppContainer.inMemory()
    let now = Date()
    for daysAgo in 1...5 {
        let end = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        let goal = 16
        container.mainContext.insert(
            Fast(
                start: end.addingTimeInterval(-Double(goal) * 3600 - Double(daysAgo) * 600),
                end: end,
                goalHours: goal,
                protocolID: "16:8",
                createdVia: .app
            )
        )
    }
    return NavigationStack { HistoryView() }
        .modelContainer(container)
        .tint(Theme.accentText)
}
