import Foundation
import HealthKit

/// 步数对账：对同一天同时用三种口径读 HealthKit，找出 App 与健康 App 数值差异的来源。
///
/// - A 口径：App 实际使用的 `HKStatisticsCollectionQuery` + `.cumulativeSum`
///   + `predicateForSamples(options: [.strictStartDate])`。
/// - B 口径：同样的统计查询，但谓词不带 `.strictStartDate`（跨天样本会按比例分摊）。
/// - C 口径：`HKSampleQuery` 直接遍历当天样本求和，附带每条样本的来源与时间。
///
/// 结果既写进 AppLog（可从设置 → 调试日志导出），也直接显示在按钮弹出的报告里。
enum StepDiagnostics {
    static func report() async -> String {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let type = HealthKitTypes.stepCount
        let unit = HKUnit.count()

        guard HKHealthStore.isHealthDataAvailable() else {
            let text = "HealthKit 在这台设备上不可用。"
            appLog(.error, "StepDiag", text)
            return text
        }

        let store = HKHealthStore()
        let appValue = await statisticsSum(
            store: store, type: type, unit: unit,
            start: start, end: now, strictStartDate: true
        )
        let looseValue = await statisticsSum(
            store: store, type: type, unit: unit,
            start: start, end: now, strictStartDate: false
        )
        let rawSamples = await rawSamples(store: store, type: type, start: start, end: now)
        let rawSum = rawSamples.reduce(0) { $0 + $1.quantity.doubleValue(for: unit) }
        let rings = await activitySummary(store: store, calendar: calendar)
        let statEnergy = await statisticsSum(
            store: store, type: HealthKitTypes.activeEnergy, unit: .kilocalorie(),
            start: start, end: now, strictStartDate: true
        )
        let statExercise = await statisticsSum(
            store: store, type: HealthKitTypes.exerciseTime, unit: .minute(),
            start: start, end: now, strictStartDate: true
        )
        let statStand = await statisticsSum(
            store: store, type: HealthKitTypes.standTime, unit: .minute(),
            start: start, end: now, strictStartDate: true
        )

        let fmt = Self.timestampFormatter
        let key = DayKey.key(for: start, calendar: calendar)
        let tz = calendar.timeZone.abbreviation() ?? calendar.timeZone.identifier

        var lines: [String] = [
            "步数对账 \(fmt.string(from: now))",
            "时区: \(tz)  今天 key: \(key)",
            "窗口: \(fmt.string(from: start)) → \(fmt.string(from: now))",
            "",
            "A App 口径 (strictStartDate + cumulativeSum): \(Self.text(appValue))",
            "B 宽松口径 (无 strictStartDate):            \(Self.text(looseValue))",
            "C 样本直接累加 (\(rawSamples.count) 条):             \(Self.text(rawSum))",
            ""
        ]
        if let appValue, let looseValue {
            lines.append("A vs B 差异: \(Int((looseValue - appValue).rounded())) 步")
        }
        if let looseValue {
            lines.append("B vs C 差异: \(Int((rawSum - looseValue).rounded())) 步")
        }
        lines.append("")
        lines.append("—— 健身三环（活动 / 锻炼 / 站立）——")
        if let rings {
            lines.append(
                "D 官方摘要: 能量=\(Self.text(rings.activeEnergyKcal))/目标 \(rings.activeGoalKcal.map { Int($0) }.map(String.init) ?? "?") 卡 · "
                + "锻炼=\(Self.text(rings.exerciseMinutes))/\(rings.exerciseGoalMinutes.map { Int($0) }.map(String.init) ?? "?") 分 · "
                + "站立=\(Self.text(rings.standHours))/\(rings.standGoalHours.map { Int($0) }.map(String.init) ?? "?") 小时"
            )
        } else {
            lines.append("D 官方摘要: 无（未授权健身记录 / 今天没有活动摘要）")
        }
        lines.append(
            "统计查询:   能量=\(Self.text(statEnergy)) 卡 · 锻炼=\(Self.text(statExercise)) 分 · 站立=\(statStand.map { "\($0 / 60)" } ?? "无数据") 小时"
        )
        lines.append("判读：健身 App 圆环用 D 口径；本 App 现已切换为 D，两者应一致。")
        lines.append("")
        lines.append("判读：HealthKit 统计查询（A/B）会自动按数据源优先级去重，与健康 App 同口径；")
        lines.append("C 直接累加 iPhone+Watch 重叠样本，虚高属正常，只作参照。")
        lines.append("若 A 与健康 App 仍不同，优先核对：查看时刻、系统健康里的数据源顺序、步数是否刚从手表同步过来。")
        lines.append("")
        lines.append("—— 样本明细（按开始时间）——")
        if rawSamples.isEmpty {
            lines.append("（无样本：检查系统「设置 → 隐私与安全性 → 健康」里本 App 的步数读取权限）")
        } else {
            for sample in rawSamples {
                let source = sample.sourceRevision.source.name
                lines.append(
                    "\(fmt.string(from: sample.startDate)) – \(fmt.string(from: sample.endDate))  "
                    + "\(Int(sample.quantity.doubleValue(for: unit))) 步  [\(source)]"
                )
            }
        }

        let report = lines.joined(separator: "\n")
        appLog(.info, "StepDiag", report)
        return report
    }

    private static func text(_ value: Double?) -> String {
        guard let value else { return "无数据" }
        return "\(Int(value.rounded())) 步"
    }

    private static func statisticsSum(
        store: HKHealthStore,
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        strictStartDate: Bool
    ) async -> Double? {
        await withCheckedContinuation { continuation in
            let options: HKQueryOptions = strictStartDate ? [.strictStartDate] : []
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: options)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: nil)
                    return
                }
                var total = 0.0
                var found = false
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        total += quantity.doubleValue(for: unit)
                        found = true
                    }
                }
                continuation.resume(returning: found ? total : nil)
            }
            store.execute(query)
        }
    }

    /// 今日官方活动摘要（HKActivitySummary）：与健身 App 圆环同源。
    private static func activitySummary(
        store: HKHealthStore,
        calendar: Calendar
    ) async -> ActivityRingSummary? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ActivityRingSummary?, Never>) in
            let now = Date()
            var startComponents = calendar.dateComponents([.era, .year, .month, .day], from: calendar.startOfDay(for: now))
            startComponents.calendar = calendar
            var endComponents = calendar.dateComponents([.era, .year, .month, .day], from: now)
            endComponents.calendar = calendar
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart:
                startComponents,
                end: endComponents
            )
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ActivityRingSummary(
                    activeEnergyKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    standHours: summary.appleStandHours.doubleValue(for: .count()),
                    activeGoalKcal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseGoalMinutes: summary.exerciseTimeGoal?.doubleValue(for: .minute()),
                    standGoalHours: summary.standHoursGoal?.doubleValue(for: .count())
                ))
            }
            store.execute(query)
        }
    }

    private static func rawSamples(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()
}
