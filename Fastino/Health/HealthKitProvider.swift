//
//  HealthKitProvider.swift
//  Fastino
//
//  The only file in the app that imports HealthKit (§4.8). Everything it
//  returns is a pure value type, so the trends screen, the aggregators and the
//  tests never see an `HKSample`.
//
//  iOS-only by placement: this lives in `Fastino/`, not `Shared/`, so the watch
//  target doesn't compile it. The watch shows no health data by design.
//
//  Nothing here is ever written to the SwiftData store. HealthKit data may not
//  be synced to iCloud and `AppContainer` mirrors to CloudKit, so these samples
//  are fetched on demand and held in memory only.
//

import Foundation
import HealthKit
import OSLog

nonisolated final class HealthKitProvider: HealthProvider {
    static let shared = HealthKitProvider()

    private let store = HKHealthStore()
    private let log = Logger(subsystem: "com.baleware.fastino", category: "health")

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let massType = HKQuantityType(.bodyMass)

    private var readTypes: Set<HKObjectType> { [sleepType, massType] }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Authorization

    /// HealthKit will not report whether *reads* were granted, but it will tell
    /// us whether asking again would show a sheet — which is exactly "have we
    /// asked yet". That is the only authorization state we can act on.
    func hasBeenAsked() async -> Bool {
        guard isAvailable else { return false }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            return status == .unnecessary
        } catch {
            log.error("Authorization status check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Asked lazily, the first time the trends screen is opened — never on
    /// launch, matching how notification permission is handled (§4.4).
    @discardableResult
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Reading

    func series(days: Int, now: Date, timeZone: TimeZone) async -> HealthSeries {
        guard isAvailable else { return .empty }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: now) ?? now)
        // Sleep for "today" began last night, so the window opens a day early;
        // the aggregator credits each stretch to the day it ended on anyway.
        let sleepStart = cal.date(byAdding: .day, value: -1, to: start) ?? start
        async let spans = sleepSpans(from: sleepStart, to: now)
        async let points = weightPoints(from: start, to: now)
        async let unit = preferredMassUnit()

        return await HealthSeries(
            nights: SleepAggregator.nights(from: spans, timeZone: timeZone)
                .filter { $0.date >= start },
            weights: WeightSeries.daily(points, timeZone: timeZone),
            massUnit: unit
        )
    }

    private func sleepSpans(from start: Date, to end: Date) async -> [SleepSpan] {
        let samples = await samples(of: sleepType, from: start, to: end)
        return samples.compactMap { sample in
            guard let category = sample as? HKCategorySample else { return nil }
            return SleepSpan(start: category.startDate, end: category.endDate, stage: stage(of: category))
        }
    }

    private func stage(of sample: HKCategorySample) -> SleepStage {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return .asleep
        case .awake:
            return .awake
        default:
            // `inBed`, and anything a future OS adds — counted as not-asleep so
            // a new value can never silently inflate the totals.
            return .inBed
        }
    }

    private func weightPoints(from start: Date, to end: Date) async -> [WeightPoint] {
        let samples = await samples(of: massType, from: start, to: end)
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return WeightPoint(
                date: quantity.startDate,
                kilograms: quantity.quantity.doubleValue(for: .gramUnit(with: .kilo))
            )
        }
    }

    /// One query, wrapped once. A denied read surfaces here as an error or an
    /// empty result — indistinguishable, and treated the same: no data.
    private func samples(of type: HKSampleType, from start: Date, to end: Date) async -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { [log] _, samples, error in
                if let error {
                    log.error("Query for \(type.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private func preferredMassUnit() async -> MassUnit {
        do {
            let units = try await store.preferredUnits(for: [massType])
            return units[massType] == .pound() ? .pounds : .kilograms
        } catch {
            log.error("Preferred unit lookup failed: \(error.localizedDescription, privacy: .public)")
            return .kilograms
        }
    }
}
