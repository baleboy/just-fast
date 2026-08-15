//
//  WatchSettingsView.swift
//  Fastino Watch App
//
//  The settings page (§4.7). Deliberately a subset of the iOS screen: the plan,
//  the start reminder, and the two notification toggles. Everything here is
//  something a *standalone* watch would otherwise have no way to set.
//
//  What's missing is missing on purpose. Appearance is absent because
//  `Theme.dynamic` resolves statically to the dark palette on watchOS — there is
//  no light appearance to choose. Sync status, data export and the about screen
//  are phone-sized concerns.
//
//  Written as a plain `List` rather than the phone's card layout: watchOS's own
//  list chrome is what users expect here, and the Flame tokens still carry the
//  identity through the mascot, the type and the accent colour.
//

import SwiftData
import SwiftUI

struct WatchSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]

    var body: some View {
        NavigationStack {
            if let settings = settingsList.first {
                WatchSettingsForm(settings: settings)
            } else {
                // The store auto-creates a row on first read; until it lands
                // there is genuinely nothing to bind to.
                ProgressView()
                    .task { _ = FastStore(context: modelContext).settings() }
            }
        }
    }
}

private struct WatchSettingsForm: View {
    @Bindable var settings: AppSettings

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    /// Whether the system is currently refusing to present our alerts. Without
    /// it the toggles below look functional while nothing can ever fire (§4.4).
    @State private var alertsBlocked = false
    /// A plan tapped while a fast is running — held until the user confirms.
    @State private var pendingProtocol: FastingProtocol?

    private var isFasting: Bool { fasts.contains(where: \.isOpen) }

    var body: some View {
        List {
            planSection
            reminderSection
            alertsSection
        }
        .navigationTitle("Settings")
        // Plain, not the watch's default carousel: carousel gives every row a
        // full-width card, and five plans plus four controls turns into a long
        // scroll for a screen the user is meant to be in and out of.
        .listStyle(.plain)
        .onChange(of: settings.startReminderEnabled) { reschedule() }
        .onChange(of: settings.startReminderHour) { reschedule() }
        .onChange(of: settings.startReminderMinute) { reschedule() }
        .onChange(of: settings.goalNotificationEnabled) { syncFastNotifications() }
        .onChange(of: settings.milestoneNotificationsEnabled) { syncFastNotifications() }
        // These bind straight to the model with @Bindable, bypassing FastStore,
        // so stamp updatedAt here — it's what SettingsElection orders by when
        // sync leaves duplicate rows, and an unstamped edit would lose to the
        // phone's older one. The snapshot excludes updatedAt, so this can't
        // re-trigger itself.
        .onChange(of: settings.snapshot) {
            settings.touch()
            try? modelContext.save()
        }
        .task { await refreshAlertStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshAlertStatus() }
        }
        .confirmationDialog(
            "Change plan?",
            isPresented: .constant(pendingProtocol != nil),
            titleVisibility: .visible
        ) {
            Button("Change") {
                if let pending = pendingProtocol { settings.activeProtocol = pending }
                pendingProtocol = nil
            }
            Button("Cancel", role: .cancel) { pendingProtocol = nil }
        } message: {
            // goalHours is snapshotted at start, so the running fast keeps the
            // goal it began with however this resolves. Saying so is the whole
            // point of asking.
            Text("Your fast in progress keeps its current goal.")
        }
    }

    // MARK: Plan

    private var planSection: some View {
        Section("Plan") {
            ForEach(FastingProtocol.allCases) { option in
                Button {
                    select(option)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.displayName)
                                .font(.flameFixed(15, .extraBold))
                            Text(option.nickname)
                                .font(.flameFixed(11, .semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if option == settings.activeProtocol {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func select(_ option: FastingProtocol) {
        guard option != settings.activeProtocol else { return }
        if isFasting {
            pendingProtocol = option
        } else {
            settings.activeProtocol = option
        }
    }

    // MARK: Reminder

    /// The wall-clock anchor is stored as hour/minute Ints; DatePicker wants a
    /// Date, so this is the round trip. Only the two components are read back —
    /// the date part is meaningless here.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: settings.startReminderComponents) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.startReminderHour = parts.hour ?? settings.startReminderHour
                settings.startReminderMinute = parts.minute ?? settings.startReminderMinute
            }
        )
    }

    private var reminderSection: some View {
        Section("Start reminder") {
            Toggle("Remind me", isOn: $settings.startReminderEnabled)
                .font(.flameFixed(15, .semibold))
            if settings.startReminderEnabled {
                DatePicker(
                    "Time",
                    selection: reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .font(.flameFixed(15, .semibold))
            }
            // This instant is also when the eating window closes (§4.1), which
            // is not obvious from a row labelled "reminder".
            Text("Your eating window closes at this time.")
                .font(.flameFixed(11, .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Alerts

    private var alertsSection: some View {
        Section("Alerts") {
            Toggle("Goal reached", isOn: $settings.goalNotificationEnabled)
                .font(.flameFixed(15, .semibold))
            Toggle("Milestones", isOn: $settings.milestoneNotificationsEnabled)
                .font(.flameFixed(15, .semibold))
            if alertsBlocked {
                Text("Notifications are turned off in the Watch app.")
                    .font(.flameFixed(11, .semibold))
                    .foregroundStyle(Theme.muted)
            } else if !NotificationOwnership.schedulesLocally {
                // Not a fault: the phone owns scheduling and forwards its alerts
                // here. Without saying so, a user who turned watch notifications
                // off would be left wondering why alerts still arrive.
                Text("Your iPhone sends these.")
                    .font(.flameFixed(11, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Effects

    private func refreshAlertStatus() async {
        alertsBlocked = await NotificationManager.shared.alertsAreBlocked()
    }

    private func reschedule() {
        try? modelContext.save()
        FastStore(context: modelContext).reconcileNotifications()
    }

    private func syncFastNotifications() {
        try? modelContext.save()
        FastStore(context: modelContext).reconcileNotifications()
    }
}

#Preview {
    let container = AppContainer.inMemory()
    container.mainContext.insert(AppSettings())
    return WatchSettingsView().modelContainer(container)
}
