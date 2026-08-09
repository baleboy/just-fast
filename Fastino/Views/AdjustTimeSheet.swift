//
//  AdjustTimeSheet.swift
//  Fastino
//
//  Inline start/end time adjustment (§4.1): starting or ending defaults to now
//  but the confirmation lets you nudge the time ("actually started at 21:30
//  yesterday") without leaving the flow.
//
//  Design: the common case is a small nudge on today's date, so we lead with
//  relative quick-adjust chips and keep an always-visible confirm button. A
//  `.compact` date+time picker handles the rare exact-time / different-day edit
//  by expanding into an overlay popover, so it never pushes the button offscreen.
//

import SwiftUI

struct AdjustTimeSheet: View {
    let title: String
    let actionLabel: String
    let accent: Color
    /// Lower bound for the picker (e.g. an end can't precede the start).
    var earliest: Date? = nil
    @State var date: Date
    let onConfirm: (Date) -> Void
    /// Optional escape hatch shown beneath the confirm button — used by the end-fast
    /// sheet to discard a fast that was started by mistake (§4.1).
    var destructive: (label: String, confirmTitle: String, action: () -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showDestructiveConfirm = false

    private let quickOffsets: [(label: String, seconds: TimeInterval)] = [
        ("−15m", 15 * 60),
        ("−30m", 30 * 60),
        ("−1h", 60 * 60),
        ("−2h", 2 * 60 * 60),
        ("−6h", 6 * 60 * 60),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                selectedTimeHeader

                quickChips

                DatePicker(
                    "Exact time",
                    selection: $date,
                    in: pickerRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(accent)
                .padding(.horizontal)

                Spacer(minLength: 0)

                Button {
                    onConfirm(date)
                    dismiss()
                } label: {
                    Text(actionLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .background(accent, in: .capsule)
                .foregroundStyle(Color.white)
                .padding(.horizontal)

                if let destructive {
                    Button(destructive.label, role: .destructive) {
                        showDestructiveConfirm = true
                    }
                    .font(.subheadline)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                destructive?.confirmTitle ?? "",
                isPresented: $showDestructiveConfirm,
                titleVisibility: .visible
            ) {
                if let destructive {
                    Button(destructive.label, role: .destructive) {
                        destructive.action()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var selectedTimeHeader: some View {
        VStack(spacing: 4) {
            Text(date, format: .dateTime.weekday(.wide).hour().minute())
                .font(.flame(30, .extraBold, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: date)
            Text(relativeDescription)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "Now", isActive: isNow) { set(Date()) }
                ForEach(quickOffsets, id: \.label) { offset in
                    chip(label: offset.label, isActive: false) {
                        set(Date().addingTimeInterval(-offset.seconds))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? accent.opacity(0.25) : Theme.card, in: .capsule)
                .foregroundStyle(isActive ? accent : Theme.ink)
                .overlay(
                    Capsule().stroke(isActive ? accent : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Logic

    private var upperBound: Date { Date().addingTimeInterval(60) } // slack for "now"

    private var pickerRange: ClosedRange<Date> {
        let lower = earliest ?? Date.distantPast
        return (lower < upperBound ? lower : upperBound.addingTimeInterval(-60))...upperBound
    }

    private var isNow: Bool { abs(date.timeIntervalSinceNow) < 60 }

    private func set(_ newValue: Date) {
        let clamped = min(max(newValue, earliest ?? .distantPast), upperBound)
        withAnimation(.snappy) { date = clamped }
    }

    private var relativeDescription: String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        return "\(DurationFormat.hoursMinutes(interval)) ago"
    }
}
