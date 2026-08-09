//
//  HistoryView.swift
//  Fastino
//
//  Reverse-chronological history grouped by month (§4.3). Tap a row to edit;
//  the + adds a missed fast retroactively (§4.2).
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
            if fasts.isEmpty {
                ContentUnavailableView(
                    "No fasts yet",
                    systemImage: "timer",
                    description: Text("Your logged fasts will appear here.")
                )
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
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingManual = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { fast in
            EditFastView(mode: .edit(fast))
        }
        .sheet(isPresented: $addingManual) {
            EditFastView(mode: .add)
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
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(durationText)
                    .font(.flame(16, .extraBold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                badge
            }
        }
        .contentShape(.rect)
    }

    private var durationText: String {
        if let d = fast.record.finalDuration {
            return DurationFormat.hoursMinutes(d)
        }
        return "—"
    }

    @ViewBuilder private var badge: some View {
        if fast.isOpen {
            Label("Open", systemImage: "circle.dashed")
                .font(.caption2)
                .foregroundStyle(Theme.accentText)
        } else if fast.record.isGoalMet {
            Label("Goal met", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.success)
        } else {
            Label("Under goal", systemImage: "circle")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
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
