//
//  WatchAdjustEndView.swift
//  Fastino Watch App
//
//  Fixing an end time that got away (§4.7) — the one edit the watch allows.
//
//  The shape of the mistake decides the shape of the UI: you almost always
//  notice *late*, and the true end is a round-ish amount of time *ago*. So the
//  chips only move the end earlier, and they're the primary control; the picker
//  is there for the case where you know the actual clock time. Nothing here can
//  move an end later than now, which would be a fast that hasn't finished.
//
//  Start times are deliberately not editable here. Correcting a start is rarer,
//  needs a date as well as a time, and gets a full screen on the phone —
//  cramming it onto a 41mm sheet would make both edits worse.
//

import SwiftData
import SwiftUI

struct WatchAdjustEndView: View {
    let fast: Fast

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Seeded from the stored end, so opening and confirming without touching
    /// anything is a no-op rather than a silent edit.
    @State private var end: Date
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false

    /// Earlier-only, and stopping at 6h: past that the fast is better rebuilt on
    /// the phone than nudged on a watch.
    private static let offsets: [(label: String, seconds: TimeInterval)] = [
        ("−15m", -15 * 60),
        ("−30m", -30 * 60),
        ("−1h", -3600),
        ("−2h", -2 * 3600),
        ("−6h", -6 * 3600),
    ]

    init(fast: Fast) {
        self.fast = fast
        _end = State(initialValue: fast.end ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    summary
                    chips
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                        .font(.flameFixed(14, .semibold))
                    Button("Confirm") { save() }
                        .font(.flameFixed(15, .extraBold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentText)
                    Button("Discard fast", role: .destructive) { confirmingDiscard = true }
                        .font(.flameFixed(14, .semibold))
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Fix end time")
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
            Text("This can't be undone, and it may end your streak.")
        }
        .alert("Couldn’t save that", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summary: some View {
        let duration = max(0, end.timeIntervalSince(fast.start))
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return VStack(spacing: 1) {
            Text("\(hours)h \(minutes)m")
                .font(.flameFixed(22, .extraBold))
                .foregroundStyle(Theme.ink)
            Text("started \(fast.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                .font(.flameFixed(10, .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private var chips: some View {
        // Two rows of flexible columns: five chips don't fit across a 41mm
        // screen, and a horizontal scroller would hide the larger offsets.
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(Self.offsets, id: \.label) { offset in
                Button {
                    end = end.addingTimeInterval(offset.seconds)
                } label: {
                    Text(offset.label)
                        .font(.flameFixed(13, .extraBold))
                        .foregroundStyle(Theme.accentText)
                        // The height is set here rather than left to the button
                        // style: `.bordered` keeps its own generous minimum on
                        // watchOS and ignores `.controlSize`, and two rows of it
                        // push Confirm off the screen entirely — hiding the
                        // primary action behind a scroll. 30pt still clears the
                        // 44pt-equivalent tap target, which is the row pitch
                        // here, not the visible cap.
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.accentText.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        do {
            // Goes through FastStore like every other write, so validation,
            // notification reconciliation and the widget reload all still
            // happen — the reason no view ever touches a Fast directly.
            try FastStore(context: modelContext).update(
                fast,
                start: fast.start,
                end: end,
                note: fast.note
            )
            Haptics.success()
            dismiss()
        } catch let error as FastValidationError {
            errorMessage = error.message
        } catch let error as AppError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard() {
        FastStore(context: modelContext).delete(fast)
        Haptics.soft()
        dismiss()
    }
}

#Preview {
    let container = AppContainer.inMemory()
    let start = Date().addingTimeInterval(-20 * 3600)
    let fast = Fast(
        start: start,
        end: start.addingTimeInterval(18 * 3600),
        goalHours: 16,
        protocolID: FastingProtocol.p168.rawValue
    )
    container.mainContext.insert(fast)
    return WatchAdjustEndView(fast: fast).modelContainer(container)
}
