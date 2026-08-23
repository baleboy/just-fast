//
//  Formatters.swift
//  Fastino
//
//  Shared duration/time formatting.
//

import Foundation

nonisolated enum DurationFormat {
    /// "16h 42m" style, used in copy and stats.
    ///
    /// A zero component is dropped rather than written out: a fast logged on the
    /// hour reads "16h", not "16h 0m". Both being zero still reads "0m", since
    /// something has to be there.
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// "16:42:09" style for the live timer readout.
    ///
    /// See `TimeFormat` for wall-clock ("ends at") labels.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

nonisolated enum TimeFormat {
    /// Wall-clock time for an "ends at" label, in the user's 12/24h convention.
    ///
    /// Qualifies the day when the instant isn't today: a 16h fast started in the
    /// evening reaches its goal after midnight, so a bare "12:00" would be
    /// ambiguous exactly when it matters most.
    /// A bare clock time from signed hours-since-midnight, in the user's 12/24h
    /// convention — the axis labels on the "stopped eating" chart (§4.8), whose
    /// values run negative through the evening before.
    static func timeOfDay(hoursFromMidnight hours: Double, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let wrapped = (hours.truncatingRemainder(dividingBy: 24) + 24)
            .truncatingRemainder(dividingBy: 24)
        // Any midnight will do — only the time of day is rendered.
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        let instant = midnight.addingTimeInterval(wrapped * 3600)
        return instant.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute())
    }

    static func endLabel(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = date.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute())

        if calendar.isDate(date, inSameDayAs: now) { return time }
        // Derived from the passed-in `now`, not `Calendar.isDateInTomorrow`,
        // which would silently measure against the real clock instead.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if let tomorrow, calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(time) tomorrow"
        }
        let weekday = date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
        return "\(weekday) \(time)"
    }
}
