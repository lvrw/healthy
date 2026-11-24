import Foundation
import SwiftData

/// 每日评分持久化。评分算法本身是纯函数，SwiftData 对象只能在主线程访问，
/// 因此把「读快照 → 后台算分 → 主线程写差异」拆成三段：
/// 1. 主线程把 DailyMetrics 取成 Sendable 值快照；
/// 2. 后台线程跑全部评分引擎（118 天全量在 Debug 构建下需数百毫秒）；
/// 3. 回到主线程只写真正变化的字段，没有变化就不 save，避免
///    mainContext 无谓变更导致所有 Tab 的 @Query 失效并重绘。
@MainActor
enum ScoreStore {
    /// 后台纯计算的输入：SwiftData @Model 不可跨并发域，先转成值类型。
    private struct DayInput: Sendable {
        let dayKey: String
        let date: Date
        let snapshot: DailySnapshot
        /// 当天被用户手动标记为不全的数据源；评分时对应分量直接跳过。
        let manualIncomplete: Set<MetricSource>
    }

    /// 后台纯计算的输出：只带回需要落库的字段，不跨线程传递引擎结果对象。
    private struct ComputedScore: Sendable {
        let dayKey: String
        let date: Date
        let readiness: Double?
        let stress: Double?
        let readinessComponentsJSON: String?
        let stressComponentsJSON: String?
        let completeness: Int
        let missing: String
        /// 被跳过的评分项（自动不全 + 手动标记）编码后的 JSON。
        let skippedJSON: String?
        let baselineDays: Int
        let confidenceRaw: String
    }

    /// 同一时刻只跑一轮重算；重算期间到达的请求合并为「再跑一轮」。
    /// 回前台、15 分钟定时器、HealthKit 同步、喝水打卡经常同时触发，
    /// 不合并会重复占满 CPU 并重复写库。
    private static var isRunning = false
    private static var needsAnotherRun = false

    /// 重算全部日期的评分。计算结果与原先逐日全量重算完全一致，
    /// 只是把纯计算挪到后台、把落库改成幂等写入。
    static func recomputeAll(
        in context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) async throws {
        if isRunning {
            needsAnotherRun = true
            return
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            needsAnotherRun = false
            try await recomputeOnce(in: context, calendar: calendar, now: now)
        } while needsAnotherRun
    }

    /// 单轮重算：主线程取快照 → 后台算分 → 主线程写差异。
    private static func recomputeOnce(
        in context: ModelContext,
        calendar: Calendar,
        now: Date
    ) async throws {
        let rows = try context.fetch(
            FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date)])
        )
        guard !rows.isEmpty else { return }

        let inputs = rows.map {
            DayInput(
                dayKey: $0.dayKey,
                date: $0.date,
                snapshot: $0.snapshot,
                manualIncomplete: IncompleteSourceMarker.markedSources(for: $0.dayKey)
            )
        }
        let computed = await Task.detached(priority: .utility) {
            computeAll(inputs: inputs, calendar: calendar, now: now)
        }.value

        let existing = try context.fetch(FetchDescriptor<DailyScore>())
        var scoresByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.dayKey, $0) })

        for item in computed {
            let score: DailyScore
            var rowChanged = false
            if let cached = scoresByKey[item.dayKey] {
                score = cached
            } else {
                score = DailyScore(dayKey: item.dayKey, date: item.date)
                context.insert(score)
                scoresByKey[item.dayKey] = score
                rowChanged = true
            }

            if score.date != item.date {
                score.date = item.date
                rowChanged = true
            }
            if score.readiness != item.readiness {
                score.readiness = item.readiness
                rowChanged = true
            }
            if score.stress != item.stress {
                score.stress = item.stress
                rowChanged = true
            }
            if score.readinessComponentsJSON != item.readinessComponentsJSON {
                score.readinessComponentsJSON = item.readinessComponentsJSON
                rowChanged = true
            }
            if score.stressComponentsJSON != item.stressComponentsJSON {
                score.stressComponentsJSON = item.stressComponentsJSON
                rowChanged = true
            }
            if score.completeness != item.completeness {
                score.completeness = item.completeness
                rowChanged = true
            }
            if score.missing != item.missing {
                score.missing = item.missing
                rowChanged = true
            }
            if score.skippedJSON != item.skippedJSON {
                score.skippedJSON = item.skippedJSON
                rowChanged = true
            }
            if score.baselineDays != item.baselineDays {
                score.baselineDays = item.baselineDays
                rowChanged = true
            }
            if score.confidenceRaw != item.confidenceRaw {
                score.confidenceRaw = item.confidenceRaw
                rowChanged = true
            }
            if rowChanged {
                // computedAt 只在评分真的变化时推进，避免每轮重算都把全表标脏。
                score.computedAt = now
            }
        }

        // hasChanges 兼顾「调用方已经改了别的模型但还没保存」的既有行为，
        // 但没有差异且上下文干净时绝不 save。
        if context.hasChanges {
            try context.save()
        }
    }

    /// 纯计算，运行于后台线程：逐日按前缀历史算分并编码分项 JSON。
    private nonisolated static func computeAll(
        inputs: [DayInput],
        calendar: Calendar,
        now: Date
    ) -> [ComputedScore] {
        let snapshots = inputs.map(\.snapshot)
        var result: [ComputedScore] = []
        result.reserveCapacity(inputs.count)

        for (index, input) in inputs.enumerated() {
            let today = snapshots[index]
            let history = Array(snapshots[..<index])
            // 只有「今天」按真实清醒 / 日光窗口折算累计型指标，历史日期是完整日。
            let dayContext = DayProgress.context(
                for: input.date, today: today, history: history, now: now, calendar: calendar
            )
            let readiness = ReadinessEngine.evaluate(
                today: today, history: history, calendar: calendar, context: dayContext,
                manualIncomplete: input.manualIncomplete
            )
            let stress = StressEngine.evaluate(
                today: today, history: history, calendar: calendar, context: dayContext,
                manualIncomplete: input.manualIncomplete
            )

            result.append(
                ComputedScore(
                    dayKey: input.dayKey,
                    date: input.date,
                    readiness: readiness.score,
                    stress: stress.score,
                    readinessComponentsJSON: encode(readiness.components),
                    stressComponentsJSON: encode(stress.components),
                    completeness: readiness.completeness,
                    missing: readiness.missing.map(\.label).joined(separator: "、"),
                    skippedJSON: encode(readiness.skipped),
                    baselineDays: readiness.baselineDays,
                    confidenceRaw: readiness.confidence.rawValue
                )
            )
        }
        return result
    }

    private nonisolated static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
