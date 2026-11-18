import Foundation
import Testing

/// 行动页「饮食与体重」关联卡的取值 / 窗口 / 文案回归测试。
struct DietWeightRelationTests {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return value
    }()

    /// 相对 2026-11-17 的日期，避免测试依赖真实「今天」。
    private func day(_ offset: Int) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func sample(offset: Int, energy: Double? = nil, mass: Double? = nil) -> DietWeightDay {
        DietWeightDay(date: day(offset), energyKcal: energy, bodyMassKg: mass)
    }

    @Test func emptyInputReturnsGuidanceInsteadOfBlankCard() {
        let relation = DietWeightRelation.evaluate(days: [], calendar: calendar)
        #expect(relation.points.isEmpty)
        #expect(relation.averageEnergyKcal == nil)
        #expect(relation.bodyMassChangeKg == nil)
        #expect(relation.summary.contains("还没有饮食记录"))
    }

    @Test func windowKeepsOnlyRecentSevenDaysAndIgnoresOlderRecords() {
        let days = (-39...0).map { sample(offset: $0, energy: $0 < -6 ? 5_000 : 1_800) }
        let relation = DietWeightRelation.evaluate(days: days, calendar: calendar)
        #expect(relation.points.count == DietWeightRelation.windowDays)
        #expect(relation.points.first?.date == day(-6))
        #expect(relation.points.last?.date == day(0))
        // 窗口外的 5000 kcal 不能混进 7 天均值。
        #expect(relation.averageEnergyKcal == 1_800)
    }

    @Test func weightChangeUsesFirstAndLastRecordAcrossSparseDays() {
        let days = (-29...0).map { offset in
            sample(
                offset: offset,
                energy: 1_800,
                mass: offset == -5 ? 70 : (offset == 0 ? 69.2 : nil)
            )
        }
        let relation = DietWeightRelation.evaluate(days: days, calendar: calendar)
        #expect(relation.firstBodyMassKg == 70)
        #expect(relation.lastBodyMassKg == 69.2)
        #expect(abs((relation.bodyMassChangeKg ?? 0) + 0.8) < 0.000_1)
        #expect(relation.summary.contains("下降 0.8 kg"))
    }

    @Test func decreasingEnergyAndWeightAreReportedAsSameDirection() {
        let days = (-29...0).map { offset in
            sample(
                offset: offset,
                energy: offset < -3 ? 2_000 : 1_700,
                mass: 70 - Double(offset + 6) / 6.0
            )
        }
        let relation = DietWeightRelation.evaluate(days: days, thresholdKcal: 1_800, calendar: calendar)
        #expect(relation.pairedDays == 7)
        #expect((relation.energyTrendKcal ?? 0) < -80)
        #expect(relation.summary.contains("目标 1800 kcal"))
        #expect(relation.summary.contains("方向一致"))
    }

    @Test func tooFewPairedDaysAvoidsCausalClaim() {
        let relation = DietWeightRelation.evaluate(
            days: [sample(offset: -1, energy: 2_200, mass: 70), sample(offset: 0, energy: 1_500)],
            calendar: calendar
        )
        #expect(relation.pairedDays == 1)
        #expect(!relation.summary.contains("方向一致"))
        #expect(relation.summary.contains("体重记录不足两次"))
    }

    @Test func energyOnlyDaysDoNotInventWeightChange() {
        let days = (-3...0).map { sample(offset: $0, energy: 1_600) }
        let relation = DietWeightRelation.evaluate(days: days, calendar: calendar)
        #expect(relation.bodyMassChangeKg == nil)
        #expect(relation.summary.contains("日均摄入 1600 kcal"))
        #expect(!relation.summary.contains("体重下降"))
    }
}
