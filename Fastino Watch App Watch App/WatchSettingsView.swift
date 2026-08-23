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
//  no light appearance to choose. Data export and the about screen are
//  phone-sized concerns.
//
//  Sync is the exception to that rule. There is no *status readout* here, but a
//  watch that isn't reaching iCloud says so, because the alternative is a watch
//  that looks perfectly healthy while everything it records stays on it — and
//  on a standalone install there is no phone screen to carry the warning.
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
    @Environment(CloudSyncStatus.self) private var syncStatus

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    /// Whether the system is currently refusing to present our alerts. Without
    /// it the toggles below look functional while nothing can ever fire (§4.4).
    @State private var alertsBlocked = false
    /// A plan tapped while a fast is running — held until the user says whether
    /// the fast in progress should take the new goal too.
    @State private var pendingProtocol: FastingProtocol?

    private var openFast: Fast? { fasts.first(where: \.isOpen) }

    var body: some View {
        List {
            syncSection
            planSection
            reminderSection
            alertsSection
        }
        .navigationTitle("Settings")
        // Plain, not the watch's default carousel: carousel scales and fades
        // rows as they pass the edges, which is motion this screen has no use
        // for. It does *not* make the list shorter — row height on watchOS is a
        // tap target and stays put whatever the style, so this list scrolls and
        // that's fine.
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
        // The same two outcomes the phone offers, and for the same reason:
        // switching plans mid-fast usually means *this* fast. Both buttons
        // change the plan and differ only in whether the running one comes
        // along, so each names its hours rather than leaving the user to infer
        // which is which. It matters more here than on the phone — a standalone
        // watch has no other screen to correct the goal from.
        .alert(
            "Change plan?",
            isPresented: $pendingProtocol.presented()
        ) {
            if let pending = pendingProtocol {
                Button("This fast too — \(pending.goalHours)h") { apply(pending, toFastInProgress: true) }
                Button("Keep this one at \(openFast?.goalHours ?? 0)h") { apply(pending, toFastInProgress: false) }
            }
            Button("Cancel", role: .cancel) { pendingProtocol = nil }
        } message: {
            if let openFast {
                Text("You're \(DurationFormat.hoursMinutes(openFast.record.duration(asOf: Date()))) into a \(openFast.goalHours)-hour fast.")
            }
        }
    }

    // MARK: Sync

    /// Shown only on a real failure, never while mirroring is still starting up
    /// (§3) — a warning that flashes past on every launch would train the user
    /// to ignore the one that matters.
    @ViewBuilder
    private var syncSection: some View {
        if case .unavailable(let reason) = syncStatus.health {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("iCloud sync is off")
                        .font(.flameFixed(15, .extraBold))
                    // The fix is in the Watch app on the phone or in iOS
                    // Settings, so there is nothing here to tap.
                    Text(reason)
                        .font(.flameFixed(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Plan

    private var planSection: some View {
        Section("Plan") {
            ForEach(FastingProtocol.allCases) { option in
                Button {
                    select(option)
                } label: {
                    HStack(spacing: 5) {
                        // One line, not two: five stacked two-line rows turn the
                        // plan into a scroll of its own, and the nickname is a
                        // gloss on the ratio rather than a second fact.
                        Text(option.displayName)
                            .font(.flameFixed(15, .extraBold))
                        Text(option.nickname)
                            .font(.flameFixed(11, .semibold))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
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
        if wouldRegoalFastInProgress(option) {
            pendingProtocol = option
        } else {
            apply(option)
        }
    }

    /// Whether the dialog has anything to ask about — see the iOS Settings
    /// screen, which carries the same rule. A running fast already on `option`
    /// would give both buttons the same hours, so the plan just changes.
    private func wouldRegoalFastInProgress(_ option: FastingProtocol) -> Bool {
        guard let openFast else { return false }
        return openFast.goalHours != option.goalHours || openFast.protocolID != option.rawValue
    }

    /// The plan change itself goes through `@Bindable`, so `onChange(of:
    /// settings.snapshot)` above stamps and saves it. Re-goaling the running
    /// fast is a `FastStore` write, because the notifications derived from the
    /// old goal have to be re-armed.
    private func apply(_ option: FastingProtocol, toFastInProgress: Bool = false) {
        pendingProtocol = nil
        settings.activeProtocol = option
        if toFastInProgress, let openFast {
            try? FastStore(context: modelContext).applyProtocol(option, to: openFast)
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
                // No .font(), for the same reason as WatchAdjustEndView's
                // picker: the digit wells are sized to the system font's
                // metrics and Baloo 2 clips inside them.
                DatePicker(
                    "Time",
                    selection: reminderTime,
                    displayedComponents: .hourAndMinute
                )
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
    return WatchSettingsView()
        .modelContainer(container)
        .environment(CloudSyncStatus())
}
