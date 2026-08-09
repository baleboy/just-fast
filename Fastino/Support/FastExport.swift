//
//  FastExport.swift
//  Fastino
//
//  "Export data" (Settings → General): the user's fasts as a CSV they can hand to
//  a spreadsheet. ISO-8601 timestamps so the file round-trips across time zones,
//  and derived columns (duration, goal met) so it's useful without a formula.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FastExport {
    static func csv(_ fasts: [FastRecord]) -> String {
        var lines = ["start,end,goal_hours,duration_hours,goal_met"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for fast in fasts.sorted(by: { $0.start < $1.start }) {
            let end = fast.end.map(formatter.string(from:)) ?? ""
            let duration = fast.finalDuration
                .map { String(format: "%.2f", $0 / 3600) } ?? ""
            lines.append([
                formatter.string(from: fast.start),
                end,
                "\(fast.goalHours)",
                duration,
                fast.end == nil ? "" : (fast.isGoalMet ? "yes" : "no"),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Wrapper so `ShareLink` hands over a named .csv file rather than a wall of text.
struct FastsCSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName("fastino-fasts.csv")
    }
}
