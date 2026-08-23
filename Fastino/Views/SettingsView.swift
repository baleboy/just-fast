//
//  SettingsView.swift
//  Fastino
//
//  Plan selection, reminders, appearance, export and the Back Tap setup tip
//  (§2, §4.4, §4.6) — laid out as Flame Friend cards rather than a system Form.
//  Each plan is a flame that grows and hardens with the plan's intensity.
//

import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    // Sorted to agree with SettingsElection while duplicates exist — an
    // unsorted @Query has no defined order, so two views could read different
    // rows on the same launch.
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]

    var body: some View {
        Group {
            if let settings = settingsList.first {
                SettingsForm(settings: settings)
            } else {
                ProgressView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            _ = FastStore(context: modelContext).settings()
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    /// Whether iOS is currently refusing to present our alerts. Without this the
    /// toggles below look fully functional while nothing can ever fire (§4.4).
    @State private var alertsBlocked = false
    /// A plan tapped while a fast is running — held until the user says whether
    /// the fast in progress should take the new goal too.
    @State private var pendingProtocol: FastingProtocol?
    @Environment(CloudSyncStatus.self) private var syncStatus

    private var openFast: Fast? { fasts.first(where: \.isOpen) }
    private var isFasting: Bool { openFast != nil }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: settings.startReminderHour, minute: settings.startReminderMinute)
                ) ?? .now
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.startReminderHour = comps.hour ?? 20
                settings.startReminderMinute = comps.minute ?? 0
            }
        )
    }

    private var reminderTimeLabel: String {
        String(format: "%02d.%02d", settings.startReminderHour, settings.startReminderMinute)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .flameScreenTitle()

                // Above the fold, like the notifications warning: "your fasts
                // aren't reaching your other devices" isn't a footnote.
                syncStatusRow
                    .padding(.top, 16)

                GroupLabel("YOUR FAST PLAN")
                    .padding(.top, 20)
                planCards
                    .padding(.top, 10)

                // Shown unconditionally: this is the schedule anchor, not a
                // notification setting — turning reminders off must not hide it.
                startAnchorCard
                    .padding(.top, 12)

                GroupLabel("NOTIFICATIONS")
                    .padding(.top, 24)
                notificationCard
                    .padding(.top, 10)

                GroupLabel("GENERAL")
                    .padding(.top, 24)
                generalCard
                    .padding(.top, 10)

                GroupLabel("BACK TAP")
                    .padding(.top, 24)
                BackTapTip()
                    .padding(.top, 10)

                Text("Fastino 1.0")
                    .font(.flame(12, .semibold, relativeTo: .caption2))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
            }
            .padding(.horizontal, FlameLayout.screenHorizontalPadding)
            .padding(.top, FlameLayout.screenTopPadding)
            .flameTabBarClearance()
        }
        // Two outcomes, not one warning. The old dialog announced that the
        // running fast kept its old goal and gave the user no say — but someone
        // switching plans mid-fast usually means *this* fast, and the goal is
        // what the ring fills towards and the alert fires on. Both buttons
        // change the plan; they differ only in whether the fast in progress
        // comes along, and each names the hours so neither is the guess.
        .alert(
            "Change your plan?",
            isPresented: $pendingProtocol.presented()
        ) {
            if let pendingProtocol {
                Button("Change this fast to \(pendingProtocol.goalHours)h too") {
                    apply(pendingProtocol, toFastInProgress: true)
                }
                Button("Keep this fast at \(openFast?.goalHours ?? 0)h") {
                    apply(pendingProtocol, toFastInProgress: false)
                }
            }
            Button("Cancel", role: .cancel) { self.pendingProtocol = nil }
        } message: {
            if let openFast {
                Text("You're \(DurationFormat.hoursMinutes(openFast.record.duration(asOf: Date()))) into a \(openFast.goalHours)-hour fast.")
            }
        }
        .onChange(of: settings.startReminderEnabled) { reschedule() }
        .onChange(of: settings.startReminderHour) { reschedule() }
        .onChange(of: settings.startReminderMinute) { reschedule() }
        .onChange(of: settings.goalNotificationEnabled) { syncFastNotifications() }
        .onChange(of: settings.milestoneNotificationsEnabled) { syncFastNotifications() }
        .onChange(of: settings.appearanceID) { try? modelContext.save() }
        // These bind straight to the model with @Bindable, bypassing FastStore,
        // so stamp updatedAt here — it's what SettingsElection orders by when
        // sync leaves duplicate rows. The snapshot excludes updatedAt, so this
        // can't re-trigger itself.
        .onChange(of: settings.snapshot) {
            settings.touch()
            try? modelContext.save()
        }
        .task { await refreshAlertStatus() }
        // Re-check on return from iOS Settings, where the user may have just
        // flipped permission on or off.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshAlertStatus() }
        }
    }

    // MARK: Plan

    /// Five protocols in a row of four-wide cards: the row scrolls rather than
    /// squeezing every card past legibility, and the fifth peeking at the edge is
    /// the affordance that says so.
    private var planCards: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - 27) / 4
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(FastingProtocol.allCases) { proto in
                        PlanCard(proto: proto, isSelected: proto == settings.activeProtocol) {
                            select(proto)
                        }
                        .frame(width: width)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .frame(height: 116)
    }

    private var startAnchorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                Text("Start fast at")
                    .font(.flame(16, .extraBold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
            }
            Text("Your eating window closes at this time, so fasting longer than planned doesn’t push tomorrow’s start later.")
                .font(.flame(12.5, .semibold, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .flameCard()
    }

    // MARK: Notifications

    private var notificationCard: some View {
        CardGroup {
            if alertsBlocked {
                NotificationsBlockedRow()
            }
            SettingsRow(title: "Fast complete", subtitle: "When you hit your goal") {
                Toggle("", isOn: $settings.goalNotificationEnabled)
                    .labelsHidden()
                    .toggleStyle(FlameToggleStyle())
            }
            SettingsRow(title: "Milestones", subtitle: "Fat burn, ketosis") {
                Toggle("", isOn: $settings.milestoneNotificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(FlameToggleStyle())
            }
            SettingsRow(
                title: "Time to start",
                subtitle: "Daily reminder, \(reminderTimeLabel)",
                isLast: true
            ) {
                Toggle("", isOn: $settings.startReminderEnabled)
                    .labelsHidden()
                    .toggleStyle(FlameToggleStyle())
            }
        }
    }

    // MARK: General

    private var generalCard: some View {
        CardGroup {
            Button {
                cycleAppearance()
            } label: {
                SettingsRow(title: "Appearance") {
                    RowValue(text: settings.appearance.displayName)
                }
            }
            .buttonStyle(FlamePressStyle())

            ShareLink(
                item: FastsCSVFile(text: FastExport.csv(fasts.records)),
                preview: SharePreview("Fastino fasts")
            ) {
                SettingsRow(title: "Export data", subtitle: "\(fasts.count) fasts as CSV", isLast: true) {
                    RowValue(text: "")
                }
            }
            .buttonStyle(FlamePressStyle())
            .disabled(fasts.isEmpty)
            .opacity(fasts.isEmpty ? 0.5 : 1)
        }
    }

    /// Shown only once sync has actually been observed failing, so the app never
    /// implies data is reaching the user's other devices when it isn't — and
    /// never cries wolf while mirroring is still starting up (§3).
    @ViewBuilder
    private var syncStatusRow: some View {
        if case .unavailable(let reason) = syncStatus.health {
            CardGroup {
                // No trailing chevron: there's nothing here to tap, and the fix
                // is in iOS Settings rather than anywhere Fastino can send you.
                SettingsRow(title: "iCloud sync is off", subtitle: reason, isLast: true) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: Actions

    private func select(_ proto: FastingProtocol) {
        guard proto != settings.activeProtocol else { return }
        if isFasting {
            pendingProtocol = proto
        } else {
            apply(proto)
        }
    }

    /// `toFastInProgress` is only ever `true` by way of the dialog above; the
    /// no-fast path can't reach it, because there is nothing to re-goal.
    private func apply(_ proto: FastingProtocol, toFastInProgress: Bool = false) {
        pendingProtocol = nil
        withAnimation(.snappy(duration: 0.25)) {
            settings.activeProtocol = proto
        }
        try? modelContext.save()
        if toFastInProgress, let openFast {
            try? FastStore(context: modelContext).applyProtocol(proto, to: openFast)
        }
    }

    private func cycleAppearance() {
        let all = Appearance.allCases
        let next = all[(all.firstIndex(of: settings.appearance).map { $0 + 1 } ?? 0) % all.count]
        withAnimation(.easeInOut(duration: 0.25)) {
            settings.appearance = next
        }
        try? modelContext.save()
    }

    private func refreshAlertStatus() async {
        alertsBlocked = await NotificationManager.shared.alertsAreBlocked()
    }

    private func reschedule() {
        try? modelContext.save()
        let store = FastStore(context: modelContext)
        let enabled = settings.startReminderEnabled
        Task {
            if enabled { await NotificationManager.shared.requestAuthorization() }
            store.reconcileNotifications()
        }
    }

    private func syncFastNotifications() {
        try? modelContext.save()
        let enabled = settings.goalNotificationEnabled || settings.milestoneNotificationsEnabled
        Task {
            if enabled { await NotificationManager.shared.requestAuthorization() }
            FastStore(context: modelContext).reconcileNotifications()
        }
    }
}

// MARK: - Building blocks

private struct GroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.flame(13, .extraBold, relativeTo: .caption))
            .tracking(0.8)
            .foregroundStyle(Theme.muted)
    }
}

/// A card of rows split by the dashed dividers this direction uses instead of
/// hairlines — the settings equivalent of a Form section.
private struct CardGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .flameCard()
        .clipShape(.rect(cornerRadius: Radius.card))
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// The last row in a group draws no divider under it.
    var isLast: Bool = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.flame(16, .extraBold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.flame(12.5, .semibold, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .overlay(alignment: .bottom) {
            if !isLast {
                DashedDivider()
            }
        }
    }
}

/// 2pt dashed rule in the warm divider tint — this direction's separator.
private struct DashedDivider: View {
    var body: some View {
        DividerLine()
            .stroke(Theme.divider, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .frame(height: 2)
    }
}

private struct DividerLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct RowValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if !text.isEmpty {
                Text(text)
                    .font(.flame(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
            }
            Text("→")
                .font(.flame(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Plan card

/// The plan picker: each option is a flame that grows and hardens with the
/// plan's intensity, so the row reads as a difficulty scale before you've read
/// a single ratio.
private struct PlanCard: View {
    let proto: FastingProtocol
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Button(action: action) {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                flame(palette)
                Text(proto.rawValue)
                    .font(.flame(19, .extraBold, relativeTo: .title3))
                    .foregroundStyle(isSelected ? palette.accentText.color : palette.ink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isSelected ? "current" : proto.nickname)
                    .font(.flameFixed(11, isSelected ? .extraBold : .bold))
                    .foregroundStyle(isSelected ? palette.accentText.color : palette.muted.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.horizontal, 6)
            .flameCard(
                radius: Radius.smallCard,
                fill: isSelected ? palette.accentSurface.color : nil,
                border: isSelected ? palette.accentBorder.color : nil
            )
        }
        .buttonStyle(FlamePressStyle())
        .accessibilityLabel("\(proto.displayName), \(proto.nickname)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func flame(_ palette: FlamePalette) -> some View {
        if isSelected {
            FlameMascot(
                height: proto.flameHeight,
                body_: [Color(hex: 0xFFB36B), Color(hex: 0xFF8A5C)],
                tip: nil,
                ink: palette.flameInk.color,
                expression: proto.flameExpression,
                bobDuration: 3,
                glow: palette.glow.a > 0 ? palette.glow.alpha(0.6).color : nil,
                glowRadius: proto.flameHeight * 0.24
            )
        } else {
            FlameMascot(
                height: proto.flameHeight,
                body_: [palette.mutedFlame.color],
                tip: nil,
                ink: palette.mutedFlameInk.color,
                expression: proto.flameExpression,
                bobDuration: nil
            )
        }
    }
}

private extension FastingProtocol {
    /// The flame grows with the plan — 31 through 50pt across the five options.
    var flameHeight: CGFloat {
        switch self {
        case .p1410: 31
        case .p168: 36
        case .p186: 41
        case .p204: 46
        case .omad: 50
        }
    }

    /// …and its face hardens to match.
    var flameExpression: FlameExpression {
        switch self {
        case .p1410: .sleepy
        case .p168: .happy
        case .p186: .focused
        case .p204, .omad: .fierce
        }
    }
}

// MARK: - Notifications blocked (§4.4)

/// Shown when permission was denied or alerts are off for the app in iOS
/// Settings — the one state the app can't fix itself, and previously couldn't
/// even tell you about.
private struct NotificationsBlockedRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications are turned off", systemImage: "bell.slash")
                .font(.flame(15, .extraBold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink.color)
            Text("Nothing below can reach you until you allow notifications for Fastino in iOS Settings.")
                .font(.flame(12.5, .semibold, relativeTo: .caption))
                .foregroundStyle(palette.muted.color)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.flame(13, .extraBold, relativeTo: .caption))
            .buttonStyle(.plain)
            .foregroundStyle(palette.accentText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(palette.accentSurface.color)
        .overlay(alignment: .bottom) { DashedDivider() }
    }
}

// MARK: - Back Tap tip card (§4.6)

private struct BackTapTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Toggle a fast with a double-tap", systemImage: "hand.tap")
                .font(.flame(15, .extraBold, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink)
            Text("""
            1. In the Shortcuts app, make a shortcut with the single action “Toggle Fast” and name it Toggle Fast
            2. Open Settings → Accessibility → Touch → Back Tap
            3. Choose Double Tap
            4. Scroll to Shortcuts and pick “Toggle Fast”
            """)
            .font(.flame(12.5, .semibold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            Text("You’ll be asked to confirm before each fast starts or ends, so an accidental tap can’t catch you out.")
                .font(.flame(12.5, .semibold, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flameCard()
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
