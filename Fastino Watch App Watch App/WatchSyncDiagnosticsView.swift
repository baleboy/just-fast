//
//  WatchSyncDiagnosticsView.swift
//  Fastino Watch App
//
//  DEBUG-only. The watch half of the sync diagnostics (§3), read side by side
//  with the phone's `SyncDiagnosticsView`.
//
//  Watch settings are otherwise deliberately a subset of the phone's, and this
//  breaks that rule on purpose: the watch is the device that appears to be
//  wrong, so it is the device the evidence has to be readable on. Under
//  `#if DEBUG`, so no shipping build grows a screen about export durations.
//
//  Kept to the same facts in the same order as the phone screen, because the
//  whole technique is holding the two up next to each other.
//

#if DEBUG
import SwiftData
import SwiftUI

struct WatchSyncDiagnosticsView: View {
    @Environment(CloudSyncStatus.self) private var syncStatus

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    private var log: SyncLog { SyncLog.shared }
    private var openFast: Fast? { fasts.first(where: \.isOpen) }

    var body: some View {
        List {
            Section("This device") {
                row("Mirroring", AppContainer.isCloudKitConfigured ? "requested" : "off")
                row("Status", healthLabel)
                row("Open fast", openFastLabel)
            }
            Section("Timings") {
                row("Waiting since", Self.stamp(log.awaitWindowStartedAt), detail: windowKindLabel)
                row("To first import", firstImportLabel)
                row("Last import", Self.stamp(log.lastSuccessfulImport?.ended))
                row("Last export", Self.stamp(log.lastSuccessfulExport?.ended))
                row("Last local write", Self.stamp(log.lastLocalWrite?.ended))
            }
            Section("Events") {
                if log.buffer.events.isEmpty {
                    Text("Nothing recorded yet.")
                        .font(.flameFixed(11, .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(log.buffer.events) { event in
                        row(event.summary, Self.stamp(event.ended ?? event.started), detail: event.detail)
                    }
                }
            }
            Section {
                Button("Clear log") { log.clear() }
                    .font(.flameFixed(13, .extraBold))
            }
        }
        .listStyle(.plain)
        .navigationTitle("Sync")
    }

    private func row(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.flameFixed(13, .extraBold))
                .foregroundStyle(Theme.ink)
            Text(value)
                .font(.flameFixed(11, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.flameFixed(10, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 1)
    }

    private var healthLabel: String {
        switch syncStatus.health {
        case .unknown: "no verdict yet"
        case .healthy: "healthy"
        case .unavailable(let reason): reason
        }
    }

    private var openFastLabel: String {
        guard let openFast else { return "none" }
        let id = openFast.id.uuidString.prefix(8)
        return "\(id) · \(openFast.start.formatted(date: .abbreviated, time: .shortened))"
    }

    private var firstImportLabel: String {
        guard let seconds = log.secondsToFirstImport else {
            if log.isImportInFlight() { return "import running" }
            return log.isAwaitingImport() ? "still waiting" : "none in this window"
        }
        return String(format: "%.1fs", seconds)
    }

    /// Whether the current window came from a launch or a resume — the
    /// distinction the background case turns on.
    private var windowKindLabel: String {
        let kind = log.awaitWindowTimeout == SyncTiming.launchImportTimeout ? "launch" : "resume"
        return "\(kind) · \(Int(log.awaitWindowTimeout))s window"
    }

    private static func stamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }
}

#Preview {
    NavigationStack {
        WatchSyncDiagnosticsView()
            .environment(CloudSyncStatus())
            .modelContainer(AppContainer.inMemory())
    }
}
#endif
