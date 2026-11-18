import Foundation
import Testing

struct ActionImpactTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)) ?? .now
    }

    private func day(
        offset: Int,
        stress: Double,
        sleep: Double? = 7.5,
        steps: Double? = 8_000,
        daylight: Double? = 30,
        mindful: Double? = nil,
        flights: Double? = nil,
        efficiency: Double? = 0.93
    ) -> ActionDay {
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return ActionDay(
            date: date,
            stress: stress,
            snapshot: DailySnapshot(
                dayKey: DayKey.key(for: date, calendar: calendar),
                date: date,
                sleepTotalH: sleep,
                sleepEfficiency: efficiency,
                steps: steps,
                flightsClimbed: flights,
                daylightMinutes: daylight,
                mindfulMinutes: mindful
            )
        )
    }

    @Test func goodSleepLowersStress() {
        var days: [ActionDay] = []
        for index in 0..<20 {
            let good = index % 2 == 0
            days.append(day(offset: -index, stress: good ? 30 : 60, sleep: good ? 8 : 5))
        }
        let summary = ActionImpactEngine.evaluate(days: days)
        let impact = summary.positive.first { $0.action == .sleep7h }
        #expect(impact != nil)
        #expect(impact?.impact == .large)
        #expect(impact?.daysMet == 10)
        #expect(impact?.daysNotMet == 10)
    }

    @Test func lowStepsRaiseStress() {
        var days: [ActionDay] = []
        for index in 0..<20 {
            let low = index % 2 == 0
            days.append(day(offset: -index, stress: low ? 70 : 40, steps: low ? 2_000 : 9_000))
        }
        let summary = ActionImpactEngine.evaluate(days: days)
        let impact = summary.negative.first { $0.action == .lowSteps3000 }
        #expect(impact != nil)
        #expect(impact?.isPositive == false)
    }

    @Test func insufficientGroupIsSkipped() {
        var days: [ActionDay] = []
        for index in 0..<20 {
            days.append(day(offset: -index, stress: 50, sleep: index < 3 ? 8 : 5))
        }
        let summary = ActionImpactEngine.evaluate(days: days)
        #expect(summary.positive.contains { $0.action == .sleep7h } == false)
    }

    @Test func neutralDeltaIsExcluded() {
        var days: [ActionDay] = []
        for index in 0..<20 {
            days.append(day(offset: -index, stress: 50, sleep: index % 2 == 0 ? 8 : 5))
        }
        let summary = ActionImpactEngine.evaluate(days: days)
        #expect(summary.positive.isEmpty)
        #expect(summary.negative.isEmpty)
    }

    @Test func insufficientDaysReturnsEmptySummary() {
        let days = (0..<10).map { day(offset: -$0, stress: 50) }
        let summary = ActionImpactEngine.evaluate(days: days)
        #expect(summary.daysAnalyzed == 10)
        #expect(summary.positive.isEmpty)
        #expect(summary.negative.isEmpty)
    }

    /// 天数够但两组压力几乎一样：必须判成「差异不显著」，并保留两组均值，
    /// 这样详情页不会把「没算压力差」误写成「天数不足 5 天」。
    @Test func detailReportsNeutralDeltaWithAverages() {
        let days = (0..<20).map { index in
            day(offset: -index, stress: 50, sleep: index % 2 == 0 ? 8 : 5)
        }
        guard case let .notSignificant(daysMet, daysNotMet, metAverage, notMetAverage, delta)
            = ActionImpactEngine.detail(action: .sleep7h, days: days)
        else {
            Issue.record("应判为 notSignificant")
            return
        }
        #expect(daysMet == 10)
        #expect(daysNotMet == 10)
        #expect(metAverage == 50)
        #expect(notMetAverage == 50)
        #expect(abs(delta) < ActionImpactEngine.neutralDelta)

        // 均值和差值都能取到，页面据此显示数字而不是「—」。
        let outcome = ActionImpactEngine.detail(action: .sleep7h, days: days)
        #expect(outcome.averageStressMet == 50)
        #expect(outcome.averageStressNotMet == 50)
        #expect(outcome.delta == 0)
    }

    /// 符合组只有 3 天：这是真的天数不足，要报出两组的实际天数。
    @Test func detailReportsInsufficientGroupCounts() {
        let days = (0..<20).map { index in
            day(offset: -index, stress: index < 6 ? 50 : 55, sleep: index < 3 ? 8 : 5)
        }
        guard case let .insufficientGroups(daysMet, daysNotMet)
            = ActionImpactEngine.detail(action: .sleep7h, days: days)
        else {
            Issue.record("应判为 insufficientGroups")
            return
        }
        #expect(daysMet == 3)
        #expect(daysNotMet == 17)
    }

    /// 总天数不足 14 天时不做任何分组结论，只回传实际天数。
    @Test func detailReportsInsufficientTotalDays() {
        let days = (0..<10).map { index in
            day(offset: -index, stress: 50, sleep: index % 2 == 0 ? 8 : 5)
        }
        #expect(ActionImpactEngine.detail(action: .sleep7h, days: days) == .insufficientTotal(daysAnalyzed: 10))
    }

    /// 通过门槛的行动，`detail` 与 `evaluate` 的结果必须完全一致（同一个判定源）。
    @Test func detailMatchesSummaryForSignificantImpact() {
        let days = (0..<20).map { index in
            let good = index % 2 == 0
            return day(offset: -index, stress: good ? 30 : 60, sleep: good ? 8 : 5)
        }
        guard case let .impact(detailImpact) = ActionImpactEngine.detail(action: .sleep7h, days: days) else {
            Issue.record("应判为 impact")
            return
        }
        let summaryImpact = ActionImpactEngine.evaluate(days: days).positive.first { $0.action == .sleep7h }
        #expect(summaryImpact == detailImpact)
    }

    @Test func trendPointsSkipMissingBehaviorData() {
        let days = [
            day(offset: -1, stress: 50, sleep: 8),
            day(offset: -2, stress: 60, sleep: nil),
            day(offset: -3, stress: 40, sleep: 5),
        ]
        let points = ActionImpactEngine.trendPoints(action: .sleep7h, days: days)
        #expect(points.count == 2)
        #expect(points[0].status == .met)
        #expect(points[1].status == .notMet)
    }

    @Test func impactLevels() {
        #expect(ActionImpactEngine.level(for: 3) == .small)
        #expect(ActionImpactEngine.level(for: 8) == .medium)
        #expect(ActionImpactEngine.level(for: 20) == .large)
    }

    private func manualDay(offset: Int, stress: Double, water: Double? = nil, caffeine: Double? = nil) -> ActionDay {
        var actionDay = day(offset: offset, stress: stress)
        var manual: [String: Double] = [:]
        if let water { manual["water"] = water }
        if let caffeine { manual["caffeine"] = caffeine }
        actionDay.manual = manual
        return actionDay
    }

    @Test func waterManualCheckInsDriveImpact() {
        let days = (0..<20).map { index in
            manualDay(offset: -index, stress: index % 2 == 0 ? 30 : 60, water: index % 2 == 0 ? 1_600 : 800)
        }
        let summary = ActionImpactEngine.evaluate(days: days)
        let impact = summary.positive.first { $0.action == .water1500 }
        #expect(impact != nil)
        #expect(impact?.daysMet == 10)
        #expect(impact?.daysNotMet == 10)
        #expect(impact?.impact == .large)
    }

    @Test func missingManualSkipsWaterImpact() {
        let days = (0..<20).map { manualDay(offset: -$0, stress: $0 % 2 == 0 ? 30 : 60, water: nil) }
        let summary = ActionImpactEngine.evaluate(days: days)
        #expect(summary.positive.contains { $0.action == .water1500 } == false)
        #expect(summary.negative.contains { $0.action == .water1500 } == false)
    }

    /// 喝水目标来自「喝水配置」：标题、判定、逐日日历必须同步到同一个目标值，
    /// 不能出现「标题写 2000、实际按 1500 判」的两套口径。
    @Test func waterTargetFollowsConfiguredGoal() {
        let snapshot = DailySnapshot(dayKey: "2026-11-02", date: now)
        // 默认目标下 1500 刚好符合；目标改成 2000 后同样的 1500 就变成不符合。
        #expect(InsightAction.water1500.status(snapshot, manual: ["water": 1_500]) == .met)
        #expect(InsightAction.water1500.status(snapshot, manual: ["water": 1_500], waterTargetMl: 2_000) == .notMet)
        #expect(InsightAction.water1500.status(snapshot, manual: ["water": 2_000], waterTargetMl: 2_000) == .met)

        // 目标 2000 时 1600 / 800 全部不符合，分组数据不足，不应给出关联结论。
        let days = (0..<20).map {
            manualDay(offset: -$0, stress: $0 % 2 == 0 ? 30 : 60, water: $0 % 2 == 0 ? 1_600 : 800)
        }
        let summary = ActionImpactEngine.evaluate(days: days, waterTargetMl: 2_000)
        #expect(summary.positive.contains { $0.action == .water1500 } == false)
        #expect(summary.negative.contains { $0.action == .water1500 } == false)

        // 逐日日历的「符合」点与等级分布同源，也应跟着目标走。
        let points = ActionImpactEngine.trendPoints(action: .water1500, days: days, waterTargetMl: 2_000)
        #expect(points.allSatisfy { $0.status == .notMet })

        // 标题按目标展示，其他行动保持固定文案。
        #expect(InsightAction.water1500.title(waterTargetMl: 2_000) == "喝水 2000 毫升以上")
        #expect(InsightAction.water1500.title == "喝水 1500 毫升以上")
        #expect(InsightAction.sleep7h.title(waterTargetMl: 2_000) == "睡够 7 小时")
    }

    @Test func caffeineThresholds() {
        let snapshot = DailySnapshot(dayKey: "2026-11-02", date: now)
        #expect(InsightAction.caffeineModerate.status(snapshot, manual: ["caffeine": 150]) == .met)
        #expect(InsightAction.caffeineModerate.status(snapshot, manual: ["caffeine": 0]) == .met)
        #expect(InsightAction.caffeineModerate.status(snapshot, manual: ["caffeine": 250]) == .notMet)
        #expect(InsightAction.caffeineModerate.status(snapshot, manual: [:]) == nil)
    }

    /// 咖啡因上限来自「咖啡因配置」：标题与判定跟着配置走，
    /// 不能出现「配置 300、详情仍按 200 判」的两套口径。
    @Test func caffeineLimitFollowsConfiguredGoal() {
        let snapshot = DailySnapshot(dayKey: "2026-11-02", date: now)
        #expect(InsightAction.caffeineModerate.status(
            snapshot, manual: ["caffeine": 250], caffeineLimitMg: 300
        ) == .met)
        #expect(InsightAction.caffeineModerate.status(
            snapshot, manual: ["caffeine": 250], caffeineLimitMg: 200
        ) == .notMet)

        let days = (0..<20).map {
            manualDay(offset: -$0, stress: $0 % 2 == 0 ? 30 : 60, caffeine: $0 % 2 == 0 ? 250 : 100)
        }
        let points = ActionImpactEngine.trendPoints(
            action: .caffeineModerate, days: days, caffeineLimitMg: 300
        )
        #expect(points.allSatisfy { $0.status == .met })

        #expect(InsightAction.caffeineModerate.title(caffeineLimitMg: 300) == "咖啡因 300 毫克以内")
        #expect(InsightAction.caffeineModerate.title == "咖啡因 200 毫克以内")
        #expect(InsightAction.sleep7h.title(caffeineLimitMg: 300) == "睡够 7 小时")
    }

    @Test func quietStatusReadsNoise() {
        func withNoise(_ db: Double?) -> DailySnapshot {
            var snapshot = DailySnapshot(dayKey: "2026-11-02", date: now)
            snapshot.environmentalNoiseDb = db
            return snapshot
        }
        #expect(InsightAction.quietUnder55.status(withNoise(50)) == .met)
        #expect(InsightAction.quietUnder55.status(withNoise(55)) == .met)
        #expect(InsightAction.quietUnder55.status(withNoise(55.1)) == .notMet)
        #expect(InsightAction.quietUnder55.status(withNoise(nil)) == nil)
    }

    @Test func quietMetricValueIsTheJudgedDecibels() {
        func withNoise(_ db: Double?) -> DailySnapshot {
            var snapshot = DailySnapshot(dayKey: "2026-11-02", date: now)
            snapshot.environmentalNoiseDb = db
            return snapshot
        }
        let action = InsightAction.quietUnder55
        #expect(action.metricValue(withNoise(50)) == 50)
        #expect(action.metricValue(withNoise(55)) == 55)
        #expect(action.metricValue(withNoise(62)) == 62)
        #expect(action.metricValue(withNoise(nil)) == nil)
        #expect(action.metricText(62) == "62")
        #expect(action.metricUnit == "dB")
        #expect(action.metricCaption == "当日环境音量日均（dB）")
        #expect(action.status(withNoise(50)) == .met)
        #expect(action.status(withNoise(62)) == .notMet)
    }

    /// 详情页日历展示的是判定所用的实测值，不是压力分数；两者与 status 必须同源。
    @Test func trendPointsCarryActionMetricNotStress() {
        var noisySnapshot = DailySnapshot(dayKey: "2026-11-02", date: now)
        noisySnapshot.environmentalNoiseDb = 68
        var quietSnapshot = DailySnapshot(dayKey: "2026-11-01", date: now)
        quietSnapshot.environmentalNoiseDb = 52
        let days = [
            ActionDay(date: now, stress: 44, snapshot: noisySnapshot),
            ActionDay(date: now, stress: 56, snapshot: quietSnapshot)
        ]
        let points = ActionImpactEngine.trendPoints(action: .quietUnder55, days: days)
        #expect(points.count == 2)
        #expect(points[0].metricValue == 68)
        #expect(points[0].status == .notMet)
        #expect(points[0].stress == 44)
        #expect(points[1].metricValue == 52)
        #expect(points[1].status == .met)
        #expect(points[1].stress == 56)
    }

    @Test func metricTextFormatsEfficiencyAsPercent() {
        let snapshot = DailySnapshot(dayKey: "2026-11-02", date: now, sleepEfficiency: 0.93)
        #expect(InsightAction.sleepEfficiency90.metricValue(snapshot) == 0.93)
        #expect(InsightAction.sleepEfficiency90.metricText(0.93) == "93%")
        #expect(InsightAction.sleepEfficiency90.status(snapshot) == .met)
    }

    @Test func autoActionStatusesIgnoreManual() {
        let snapshot = DailySnapshot(dayKey: "2026-11-02", date: now, sleepTotalH: 8)
        #expect(InsightAction.sleep7h.status(snapshot, manual: ["water": 2000]) == .met)
    }

    /// 回归：不同行动必须用各自指标分组，不能出现「步数低于 3000」与「睡眠少于 6 小时」
    /// 下钻页拿到同一份压力对比。这里让两个行动的符合日完全错开，结果必须不同。
    @Test func distinctActionsYieldDistinctDetail() {
        var days: [ActionDay] = []
        for index in 0..<20 {
            let lowStep = index >= 10
            let lowSleep = index % 2 != 0
            // 压力只跟步数走：低步数日高压力，这样两个行动的分组均值必然不同。
            let stress = lowStep ? 70.0 : 40.0
            days.append(day(
                offset: -index,
                stress: stress,
                sleep: lowSleep ? 5 : 8,
                steps: lowStep ? 2_000 : 9_000
            ))
        }
        let forSteps = ActionImpactEngine.detail(action: .lowSteps3000, days: days)
        let forSleep = ActionImpactEngine.detail(action: .shortSleep6h, days: days)
        guard case let .impact(stepImpact) = forSteps else {
            Issue.record("步数行动应判为显著影响")
            return
        }
        guard case let .notSignificant(_, _, sleepMet, sleepNotMet, sleepDelta) = forSleep else {
            Issue.record("睡眠行动应判为无显著差异")
            return
        }
        #expect(stepImpact.daysMet == 10)
        #expect(stepImpact.averageStressMet == 70)
        #expect(stepImpact.averageStressNotMet == 40)
        // 睡眠符合日前后各占一半，两组压力均值相等；与步数页的 70/40 明显不同。
        #expect(sleepMet == 55)
        #expect(sleepNotMet == 55)
        #expect(sleepDelta == 0)
        #expect(stepImpact.delta != sleepDelta)
    }
}
