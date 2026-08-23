//
//  FormattersTests.swift
//  FastinoTests
//
//  Duration copy: a zero component is dropped, so nothing reads "16h 0m".
//

import Foundation
import Testing
@testable import Fastino

@Suite("Duration formatting")
struct DurationFormatTests {
    @Test func bothComponentsShown() {
        #expect(DurationFormat.hoursMinutes(16 * 3600 + 42 * 60) == "16h 42m")
    }

    @Test func wholeHoursDropTheMinutes() {
        #expect(DurationFormat.hoursMinutes(16 * 3600) == "16h")
        #expect(DurationFormat.hoursMinutes(3600) == "1h")
    }

    @Test func underAnHourShowsMinutesOnly() {
        #expect(DurationFormat.hoursMinutes(42 * 60) == "42m")
    }

    @Test func zeroStillReadsAsMinutes() {
        #expect(DurationFormat.hoursMinutes(0) == "0m")
    }

    /// Leftover seconds are dropped, not rounded up into the minute — so a
    /// part-minute short of the hour is still "15h 59m", never a premature "16h".
    @Test func leftoverSecondsAreTruncated() {
        #expect(DurationFormat.hoursMinutes(15 * 3600 + 59 * 60 + 40) == "15h 59m")
        #expect(DurationFormat.hoursMinutes(16 * 3600 + 30) == "16h")
    }
}
