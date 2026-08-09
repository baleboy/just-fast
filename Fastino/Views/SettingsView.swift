//
//  SettingsView.swift
//  Fastino
//
//  Plan selection, reminders, appearance, export and the Back Tap setup tip
//  (§2, §4.4, §4.6) — laid out as Ember cards rather than a system Form.
//

import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    var body: some View {
        ZStack {
            EmberBackground()
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
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    /// Whether iOS is currently refusing to present our alerts. Without this the
    /// toggles below look fully functional while nothing can ever fire (§4.4).
    @State private var alertsBlocked = false
    /// A plan tapped while a fast is running — held until the user confirms that
    /// it won't touch the fast in progress.
    @State private var pendingProtocol: FastingProtocol?

    private var isFasting: Bool { fasts.contains(where: \.isOpen) }

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
                Text("SETTINGS")
                    .emberScreenTitle()

                GroupLabel("YOUR FAST PLAN")
                    .padding(.top, 24)
                planCards
                    .padding(.top, 10)

                // Shown unconditionally: this is the schedule anchor, not a
                // notification setting — turning reminders off must not hide it.
                startAnchorCard
                    .padding(.top, 10)

                GroupLabel("NOTIFICATIONS")
                    .padding(.top, 26)
                notificationCard
                    .padding(.top, 10)

                GroupLabel("GENERAL")
                    .padding(.top, 26)
                generalCard
                    .padding(.top, 10)

                GroupLabel("BACK TAP")
                    .padding(.top, 26)
                BackTapTip()
                    .padding(.top, 10)

                Text("Fastino 1.0")
                    .font(.ember(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
            }
            .padding(.horizontal, EmberLayout.screenHorizontalPadding)
            .padding(.top, EmberLayout.screenTopPadding)
            .emberTabBarClearance()
        }
        .confirmationDialog(
            "Change your plan?",
            isPresented: .constant(pendingProtocol != nil),
            titleVisibility: .visible
        ) {
            if let pendingProtocol {
                Button("Switch to \(pendingProtocol.displayName)") { apply(pendingProtocol) }
            }
            Button("Cancel", role: .cancel) { self.pendingProtocol = nil }
        } message: {
            Text("The fast you're running keeps the goal it started with. The new plan applies from your next fast.")
        }
        .onChange(of: settings.startReminderEnabled) { reschedule() }
        .onChange(of: settings.startReminderHour) { reschedule() }
        .onChange(of: settings.startReminderMinute) { reschedule() }
        .onChange(of: settings.goalNotificationEnabled) { syncFastNotifications() }
        .onChange(of: settings.milestoneNotificationsEnabled) { syncFastNotifications() }
        .onChange(of: settings.appearanceID) { try? modelContext.save() }
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
                HStack(spacing: 9) {
                    ForEach(FastingProtocol.allCases) { proto in
                        PlanCard(
                            proto: proto,
                            isSelected: proto == settings.activeProtocol
                        ) {
                            select(proto)
                        }
                        .frame(width: width)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .frame(height: 78)
    }

    private var startAnchorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                Text("Start fast at")
                    .font(.ember(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.primaryText)
            }
            Text("Your eating window closes at this time, so fasting longer than planned doesn’t push tomorrow’s start later.")
                .font(.ember(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .emberCard()
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
                    .toggleStyle(EmberToggleStyle())
            }
            SettingsRow(title: "Milestones", subtitle: "Fat burn, ketosis") {
                Toggle("", isOn: $settings.milestoneNotificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(EmberToggleStyle())
            }
            SettingsRow(title: "Time to start", subtitle: "Daily reminder, \(reminderTimeLabel)") {
                Toggle("", isOn: $settings.startReminderEnabled)
                    .labelsHidden()
                    .toggleStyle(EmberToggleStyle())
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
            .buttonStyle(EmberPressStyle())

            ShareLink(
                item: FastsCSVFile(text: FastExport.csv(fasts.records)),
                preview: SharePreview("Fastino fasts")
            ) {
                SettingsRow(title: "Export data", subtitle: "\(fasts.count) fasts as CSV") {
                    RowValue(text: "")
                }
            }
            .buttonStyle(EmberPressStyle())
            .disabled(fasts.isEmpty)
            .opacity(fasts.isEmpty ? 0.5 : 1)
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

    private func apply(_ proto: FastingProtocol) {
        pendingProtocol = nil
        withAnimation(.snappy(duration: 0.2)) {
            settings.activeProtocol = proto
        }
        try? modelContext.save()
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
        Text(text).emberSectionLabel()
    }
}

/// A card of rows separated by hairlines — the settings equivalent of a Form
/// section, in the Ember card treatment.
private struct CardGroup<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .emberCard()
        .clipShape(.rect(cornerRadius: Radius.card))
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ember(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.ember(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .overlay(alignment: .bottom) {
            // Hairline between rows; the last one is trimmed by the card's clip.
            Rectangle()
                .fill(Theme.cardSeparator)
                .frame(height: 1)
                .padding(.leading, 16)
                .offset(y: 1)
        }
    }
}

private struct RowValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if !text.isEmpty {
                Text(text)
                    .font(.ember(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.secondaryText)
            }
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let proto: FastingProtocol
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        Button(action: action) {
            VStack(spacing: 3) {
                ratio(palette)
                Text(isSelected ? "current" : proto.nickname)
                    .font(.emberFixed(11, isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? palette.accentText.color : palette.textSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .emberCard(
                radius: Radius.planCard,
                fill: isSelected ? palette.accent.alpha(colorScheme == .dark ? 0.14 : 0.1).color : nil,
                border: isSelected ? palette.accent.color : nil,
                glow: isSelected ? palette.accent.alpha(colorScheme == .dark ? 0.3 : 0.25).color : nil
            )
        }
        .buttonStyle(EmberPressStyle())
        .accessibilityLabel("\(proto.displayName), \(proto.nickname)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func ratio(_ palette: EmberPalette) -> some View {
        let text = Text(proto.rawValue)
            .font(.ember(24, .bold, relativeTo: .title2))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        if isSelected {
            text.foregroundStyle(Theme.heatGradient(colorScheme))
        } else {
            text.foregroundStyle(Theme.primaryText)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications are turned off", systemImage: "bell.slash")
                .font(.ember(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Theme.primaryText)
            Text("Nothing below can reach you until you allow notifications for Fastino in iOS Settings.")
                .font(.ember(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.secondaryText)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.ember(12, .semibold, relativeTo: .caption))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.accentChip)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.cardSeparator).frame(height: 1)
        }
    }
}

// MARK: - Back Tap tip card (§4.6)

private struct BackTapTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Toggle a fast with a double-tap", systemImage: "hand.tap")
                .font(.ember(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Theme.primaryText)
            Text("""
            1. In the Shortcuts app, make a shortcut with the single action “Toggle Fast” and name it Toggle Fast
            2. Open Settings → Accessibility → Touch → Back Tap
            3. Choose Double Tap
            4. Scroll to Shortcuts and pick “Toggle Fast”
            """)
            .font(.ember(12, .regular, relativeTo: .caption))
            .foregroundStyle(Theme.secondaryText)
            Text("You’ll be asked to confirm before each fast starts or ends, so an accidental tap can’t catch you out.")
                .font(.ember(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .emberCard()
    }
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}
