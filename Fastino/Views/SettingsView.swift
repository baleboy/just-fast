//
//  SettingsView.swift
//  Fastino
//
//  Protocol selection, reminders, and the Back Tap setup tip (§2, §4.4, §4.6).
//

import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Group {
            if let settings = settingsList.first {
                SettingsForm(settings: settings)
            } else {
                ProgressView()
            }
        }
        .task {
            _ = FastStore(context: modelContext).settings()
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// Whether iOS is currently refusing to present our alerts. Without this the
    /// toggles below look fully functional while nothing can ever fire (§4.4).
    @State private var alertsBlocked = false

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

    var body: some View {
        Form {
            Section("Plan") {
                Picker("Active protocol", selection: $settings.activeProtocolID) {
                    ForEach(FastingProtocol.allCases) { proto in
                        Text(proto.displayName).tag(proto.rawValue)
                    }
                }
                Text("Applies to fasts started from now on — never retroactively.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                // Shown unconditionally: this is the schedule anchor, not a
                // notification setting — turning reminders off must not hide it.
                DatePicker("Start fast at", selection: reminderTime, displayedComponents: .hourAndMinute)
                Text("Your eating window closes at this time, so fasting longer than planned doesn’t push tomorrow’s start later.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Notifications") {
                if alertsBlocked {
                    NotificationsBlockedRow()
                }
                Toggle("Goal reached alert", isOn: $settings.goalNotificationEnabled)
                Toggle("Daily start reminder", isOn: $settings.startReminderEnabled)
                Text("Nudges you at your start time.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Back Tap") {
                BackTapTip()
            }

            Section {
                LabeledContent("Version", value: "1.0")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.startReminderEnabled) { reschedule() }
        .onChange(of: settings.startReminderHour) { reschedule() }
        .onChange(of: settings.startReminderMinute) { reschedule() }
        .onChange(of: settings.goalNotificationEnabled) { syncGoal() }
        .task { await refreshAlertStatus() }
        // Re-check on return from iOS Settings, where the user may have just
        // flipped permission on or off.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshAlertStatus() }
        }
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

    private func syncGoal() {
        try? modelContext.save()
        let enabled = settings.goalNotificationEnabled
        Task {
            if enabled { await NotificationManager.shared.requestAuthorization() }
            FastStore(context: modelContext).reconcileNotifications()
        }
    }
}

// MARK: - Notifications blocked (§4.4)

/// Shown when permission was denied or alerts are off for the app in iOS
/// Settings — the one state the app can't fix itself, and previously couldn't
/// even tell you about.
private struct NotificationsBlockedRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications are turned off", systemImage: "bell.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Nothing below can reach you until you allow notifications for Fastino in iOS Settings.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.amber)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Back Tap tip card (§4.6)

private struct BackTapTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Toggle a fast with a double-tap", systemImage: "hand.tap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("""
            1. In the Shortcuts app, make a shortcut with the single action “Toggle Fast” and name it Toggle Fast
            2. Open Settings → Accessibility → Touch → Back Tap
            3. Choose Double Tap
            4. Scroll to Shortcuts and pick “Toggle Fast”
            """)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            Text("You’ll be asked to confirm before each fast starts or ends, so an accidental tap can’t catch you out.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(AppContainer.inMemory())
        // RootView tints the whole TabView; without this the preview's controls
        // render in the system accent rather than the app's amber (§5).
        .tint(Theme.amber)
}
