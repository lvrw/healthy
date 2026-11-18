import Foundation
import HealthKit

/// 与 iOS 端 HealthKitService 对应的 watchOS 数据层。
/// 负责：读取最新/今日 HRV、近 28 天 HRV 基线、今日喝水与咖啡因总量，
/// 以及把用户的喝水/咖啡因打卡写回 HealthKit（不带特殊来源标记，
/// 因此 iOS 端会作为「外部数据」合并进当日总量，不会重复计数）。
actor WatchHealthStore {
    private let store = HKHealthStore()

    func isAvailable() -> Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAuthorization(toShare: WatchHealthTypes.writeTypes, read: WatchHealthTypes.readTypes) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
        } catch {
            return false
        }
    }

    func authorizationStatus() -> (canWriteWater: Bool, canWriteCaffeine: Bool) {
        guard HKHealthStore.isHealthDataAvailable() else { return (false, false) }
        return (
            store.authorizationStatus(for: WatchHealthTypes.dietaryWater) == .sharingAuthorized,
            store.authorizationStatus(for: WatchHealthTypes.dietaryCaffeine) == .sharingAuthorized
        )
    }

    func fetchDashboard(now: Date = .now, calendar: Calendar = .current) async throws -> DashboardSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else { throw WatchHealthError.unavailable }

        let start = calendar.startOfDay(for: now)
        guard let baselineStart = calendar.date(byAdding: .day, value: -27, to: start) else {
            throw WatchHealthError.unavailable
        }

        async let latest = latestHRV()
        async let daily = dailyHRVAverages(from: baselineStart, to: now, calendar: calendar)
        async let water = sumToday(WatchHealthTypes.dietaryWater, unit: WatchHealthTypes.milliliter, now: now, calendar: calendar)
        async let caffeine = sumToday(WatchHealthTypes.dietaryCaffeine, unit: WatchHealthTypes.milligram, now: now, calendar: calendar)
        let (latestVal, dailyVal, waterVal, caffeineVal) = try await (latest, daily, water, caffeine)

        let status = authorizationStatus()
        return DashboardSnapshot(
            latestHRVms: latestVal?.value,
            latestHRVAt: latestVal?.date,
            todayHRVms: dailyVal.last?.sdnn,
            dailyHRV: dailyVal,
            waterMlToday: waterVal,
            caffeineMgToday: caffeineVal,
            canWriteWater: status.canWriteWater,
            canWriteCaffeine: status.canWriteCaffeine
        )
    }

    private func latestHRV() async throws -> (value: Double, date: Date)? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: WatchHealthTypes.hrv,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: WatchHealthTypes.hrvUnit)
                continuation.resume(returning: (value, sample.endDate))
            }
            store.execute(query)
        }
    }

    private func dailyHRVAverages(from start: Date, to end: Date, calendar: Calendar) async throws -> [HRVDaily] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: WatchHealthTypes.hrv,
                quantitySamplePredicate: nil,
                options: .discreteAverage,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var result: [HRVDaily] = []
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    guard let q = stats.averageQuantity() else { return }
                    result.append(HRVDaily(date: stats.startDate, sdnn: q.doubleValue(for: WatchHealthTypes.hrvUnit)))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func sumToday(_ type: HKQuantityType, unit: HKUnit, now: Date, calendar: Calendar) async throws -> Double {
        let start = calendar.startOfDay(for: now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate]),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: 0)
                    return
                }
                var total: Double = 0
                collection.enumerateStatistics(from: start, to: now) { stats, _ in
                    if let q = stats.sumQuantity() {
                        total += q.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }

    func addWater(ml: Double, at date: Date = .now) async throws {
        try await saveSample(type: WatchHealthTypes.dietaryWater, unit: WatchHealthTypes.milliliter, amount: ml, date: date)
    }

    func addCaffeine(mg: Double, at date: Date = .now) async throws {
        try await saveSample(type: WatchHealthTypes.dietaryCaffeine, unit: WatchHealthTypes.milligram, amount: mg, date: date)
    }

    private func saveSample(type: HKQuantityType, unit: HKUnit, amount: Double, date: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw WatchHealthError.unavailable }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: max(0, amount)),
            start: date,
            end: date
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: WatchHealthError.saveFailed)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum WatchHealthError: LocalizedError {
    case unavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "此设备暂不支持健康数据，请在 Apple Watch 真机上运行。"
        case .saveFailed:
            return "写入健康数据失败，请确认已在健康 App 中允许写入。"
        }
    }
}

struct HRVDaily: Sendable, Identifiable {
    let date: Date
    let sdnn: Double
    var id: Date { date }
}

struct DashboardSnapshot: Sendable {
    let latestHRVms: Double?
    let latestHRVAt: Date?
    let todayHRVms: Double?
    let dailyHRV: [HRVDaily]
    let waterMlToday: Double
    let caffeineMgToday: Double
    let canWriteWater: Bool
    let canWriteCaffeine: Bool
}
