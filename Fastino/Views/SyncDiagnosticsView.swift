//
//  SyncDiagnosticsView.swift
//  Fastino
//
//  DEBUG-only. What CloudKit mirroring actually did on this device (§3).
//
//  This exists to answer one question that the shipping UI deliberately can't:
//  when the watch doesn't show the fast the phone is running, *which half*
//  failed. Open this on both devices at once and the answer is usually visible
//  in the first three rows — the phone exported at 14.02.11 and the watch's last
//  import is from yesterday, or both agree and the watch is simply holding a
//  different record.
//
//  Not a product surface, and it must not become one. The shipping answer to
//  "is sync working" is the one row in Settings that says it isn't; a user has
//  no use for export durations.
//

#if DEBUG
import SwiftData
import SwiftUI

struct SyncDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSyncStatus.self) private var syncStatus

    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    private var log: SyncLog { SyncLog.shared }
    private var openFast: Fast? { fasts.first(where: \.isOpen) }

    var body: some View {
        ZStack {
            FlameBackground(resting: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sync")
                        .flameScreenTitle()

                    GroupLabel("THIS DEVICE")
                        .padding(.top, 18)
                    CardGroup {
                        DiagnosticRow(title: "Mirroring requested", value: AppContainer.isCloudKitConfigured ? "Yes" : "No")
                        DiagnosticRow(title: "Status", value: healthLabel)
                        // The identity of the open fast, not just whether there
                        // is one: two devices can each hold *a* fast and still
                        // disagree about which.
                        DiagnosticRow(title: "Open fast", value: openFastLabel, isLast: true)
                    }
                    .padding(.top, 10)

                    GroupLabel("TIMINGS")
                        .padding(.top, 22)
                    CardGroup {
                        DiagnosticRow(title: "Waiting since", subtitle: windowKindLabel, value: Self.stamp(log.awaitWindowStartedAt))
                        DiagnosticRow(title: "To first import", value: firstImportLabel)
                        DiagnosticRow(title: "Last import", value: Self.stamp(log.lastSuccessfulImport?.ended))
                        DiagnosticRow(title: "Last export", value: Self.stamp(log.lastSuccessfulExport?.ended))
                        DiagnosticRow(title: "Last local write", value: Self.stamp(log.lastLocalWrite?.ended), isLast: true)
                    }
                    .padding(.top, 10)

                    GroupLabel("EVENTS")
                        .padding(.top, 22)
                    eventsCard
                        .padding(.top, 10)

                    FlamePrimaryButton(title: "Done", resting: true) { dismiss() }
                        .padding(.top, 22)
                    Button("Clear log") { log.clear() }
                        .buttonStyle(FlamePressStyle())
                        .font(.flame(15, .extraBold, relativeTo: .headline))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .padding(.horizontal, FlameLayout.screenHorizontalPadding)
                .padding(.top, FlameLayout.screenTopPadding)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var eventsCard: some View {
        if log.buffer.events.isEmpty {
            CardGroup {
                DiagnosticRow(title: "Nothing recorded yet", value: "", isLast: true)
            }
        } else {
            CardGroup {
                ForEach(Array(log.buffer.events.enumerated()), id: \.element.id) { index, event in
                    DiagnosticRow(
                        title: event.summary,
                        subtitle: event.succeeded ? event.detail : (event.detail ?? "unknown error"),
                        value: Self.stamp(event.ended ?? event.started),
                        isLast: index == log.buffer.events.count - 1
                    )
                }
            }
        }
    }

    private var healthLabel: String {
        switch syncStatus.health {
        case .unknown: "No verdict yet"
        case .healthy: "Healthy"
        case .unavailable(let reason): reason
        }
    }

    private var openFastLabel: String {
        guard let openFast else { return "None" }
        // Enough of the id to compare across two screens by eye, and the start
        // to the minute, which is what actually differs when they disagree.
        let id = openFast.id.uuidString.prefix(8)
        return "\(id) · \(openFast.start.formatted(date: .abbreviated, time: .shortened))"
    }

    private var firstImportLabel: String {
        guard let seconds = log.secondsToFirstImport else {
            if log.isImportInFlight() { return "Import running" }
            return log.isAwaitingImport() ? "Still waiting" : "None in this window"
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

private struct DiagnosticRow: View {
    let title: String
    var subtitle: String?
    let value: String
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.flame(14, .extraBold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.flame(11.5, .semibold, relativeTo: .caption2))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.flame(13, .bold, relativeTo: .caption))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
            }
        }
    }
}

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

#Preview {
    SyncDiagnosticsView()
        .environment(CloudSyncStatus())
        .modelContainer(AppContainer.inMemory())
}
#endif
