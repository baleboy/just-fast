//
//  WatchFastDetailView.swift
//  Fastino Watch App
//
//  One fast, with both of its times editable (§4.7), plus the escape hatch for
//  a fast that shouldn't exist at all.
//
//  This screen exists because a standalone watch has no phone to fall back on.
//  On iPhone the same repairs live in History → EditFastView, which edits start
//  and end together on a full-size screen; that doesn't fit here, so each time
//  gets its own focused editor and this is the hub.
//
//  A fast **in progress** is editable too, and the case that matters most: you
//  tap Start twenty minutes after you actually stopped eating, and every zone
//  boundary and the goal alert are wrong from then on. Correcting the start
//  goes through `FastStore.update`, which re-arms the notifications.
//

import SwiftData
import SwiftUI

struct WatchFastDetailView: View {
    let fast: Fast

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDiscard = false

    private var store: FastStore { FastStore(context: modelContext) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    summary
                    timeRow(
                        label: "Start",
                        value: fast.start,
                        destination: startEditor
                    )
                    if let end = fast.end {
                        timeRow(label: "End", value: end) { endEditor(currentEnd: end) }
                    } else {
                        // No end to fix yet. Ending the fast is the timer page's
                        // job — offering it here as well would put a second,
                        // less obvious End button in the app.
                        Text("In progress")
                            .font(.flameFixed(12, .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    Button("Discard fast", role: .destructive) { confirmingDiscard = true }
                        .font(.flameFixed(14, .semibold))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(fast.isOpen ? "Current fast" : "Fast")
        }
        .confirmationDialog(
            "Discard this fast?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { discard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Streaks are derived, so deleting one fast can silently cost a
            // streak several days long. Better said out loud than discovered.
            Text("This can’t be undone, and it may end your streak.")
        }
    }

    // MARK: Rows

    private var summary: some View {
        VStack(spacing: 1) {
            Text(durationLabel)
                .font(.flameFixed(22, .extraBold))
                .foregroundStyle(Theme.ink)
            Text("goal \(fast.goalHours)h")
                .font(.flameFixed(10, .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private var durationLabel: String {
        let duration = fast.record.duration(asOf: Date())
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func timeRow<Destination: View>(
        label: String,
        value: Date,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(label)
                    .font(.flameFixed(14, .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(value.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.flameFixed(14, .extraBold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: Editors

    private func startEditor() -> some View {
        WatchTimeEditView(
            title: "Start",
            initial: fast.start,
            // An open fast can't have started in the future; a closed one can't
            // have started after it ended. Overlap with the previous fast is
            // left to FastValidation, which knows about the other records.
            latest: fast.end ?? Date()
        ) { newStart in
            save(start: newStart, end: fast.end)
        }
    }

    private func endEditor(currentEnd: Date) -> some View {
        WatchTimeEditView(
            title: "End",
            initial: currentEnd,
            earliest: fast.start,
            latest: Date()
        ) { newEnd in
            save(start: fast.start, end: newEnd)
        }
    }

    /// - Returns: an error message for the editor to show, or nil on success.
    private func save(start: Date, end: Date?) -> String? {
        do {
            // Through FastStore like every other write, so validation,
            // notification reconciliation and the widget reload all happen.
            try store.update(fast, start: start, end: end, note: fast.note)
            return nil
        } catch let error as FastValidationError {
            return error.message
        } catch let error as AppError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    private func discard() {
        store.delete(fast)
        Haptics.soft()
        dismiss()
    }
}

#Preview("In progress") {
    let container = AppContainer.inMemory()
    let fast = Fast(
        start: Date().addingTimeInterval(-9 * 3600),
        goalHours: 16,
        protocolID: FastingProtocol.p168.rawValue
    )
    container.mainContext.insert(fast)
    return WatchFastDetailView(fast: fast).modelContainer(container)
}

#Preview("Finished") {
    let container = AppContainer.inMemory()
    let start = Date().addingTimeInterval(-30 * 3600)
    let fast = Fast(
        start: start,
        end: start.addingTimeInterval(17 * 3600),
        goalHours: 16,
        protocolID: FastingProtocol.p168.rawValue
    )
    container.mainContext.insert(fast)
    return WatchFastDetailView(fast: fast).modelContainer(container)
}
