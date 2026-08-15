//
//  WatchTimeEditView.swift
//  Fastino Watch App
//
//  One time, edited (§4.7). Used for both a fast's start and its end, because
//  the correction is the same shape either way: you tapped late (or early), and
//  the true instant is some round number of minutes from what got recorded.
//
//  Chips move in both directions, unlike the phone's start sheet, which only
//  offers "earlier". That sheet is used *while starting*, where now is the
//  upper bound by construction. Here the recorded time is already wrong in
//  whichever direction, so offering only one is a coin flip.
//
//  `earliest`/`latest` are the caller's business — an end can't precede its
//  start or land in the future, a start can't follow its end. Chips that would
//  leave the range disable rather than silently clamp, so the bound is visible
//  instead of being a surprise.
//

import SwiftUI

struct WatchTimeEditView: View {
    let title: String
    let earliest: Date?
    let latest: Date?
    /// Returns an error message to display, or nil on success.
    let onConfirm: (Date) -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var errorMessage: String?

    private static let offsets: [(label: String, seconds: TimeInterval)] = [
        ("−1h", -3600),
        ("−30m", -30 * 60),
        ("−15m", -15 * 60),
        ("+15m", 15 * 60),
        ("+30m", 30 * 60),
        ("+1h", 3600),
    ]

    init(
        title: String,
        initial: Date,
        earliest: Date? = nil,
        latest: Date? = nil,
        onConfirm: @escaping (Date) -> String?
    ) {
        self.title = title
        self.earliest = earliest
        self.latest = latest
        self.onConfirm = onConfirm
        _date = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                chips
                // No .font() — the digit wells are sized to the system font's
                // metrics and Baloo 2 clips inside them.
                picker
                Button("Confirm") { confirm() }
                    .font(.flameFixed(15, .extraBold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentText)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(title)
        .alert("Couldn’t save that", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
            .font(.flameFixed(20, .extraBold))
            .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var picker: some View {
        // The picker only edits hour and minute; the day comes from the chips.
        // A date wheel on a 41mm screen is a worse way to say "yesterday" than
        // "−6h" is, and the corrections this screen exists for are same-day.
        DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
            .frame(height: 44)
            .labelsHidden()
    }

    private var chips: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(Self.offsets, id: \.label) { offset in
                let target = date.addingTimeInterval(offset.seconds)
                let allowed = isInRange(target)
                Button {
                    date = target
                } label: {
                    Text(offset.label)
                        .font(.flameFixed(13, .extraBold))
                        .foregroundStyle(allowed ? Theme.accentText : Theme.muted)
                        // Height set by hand: .bordered ignores .controlSize on
                        // watchOS, and its minimum pushes Confirm off-screen.
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill((allowed ? Theme.accentText : Theme.muted).opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!allowed)
            }
        }
    }

    private func isInRange(_ candidate: Date) -> Bool {
        if let earliest, candidate < earliest { return false }
        if let latest, candidate > latest { return false }
        return true
    }

    private func confirm() {
        guard isInRange(date) else {
            // Reachable via the picker, which has no bounds of its own.
            if let latest, date > latest {
                errorMessage = "That’s later than it can be."
            } else {
                errorMessage = "That’s earlier than it can be."
            }
            return
        }
        if let message = onConfirm(date) {
            errorMessage = message
        } else {
            Haptics.success()
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        WatchTimeEditView(
            title: "Start",
            initial: Date().addingTimeInterval(-9 * 3600),
            latest: Date()
        ) { _ in nil }
    }
}
