import SwiftData
import SwiftUI

/// 饮食详情页里的「今日餐次时间轴 + 规律饮食」卡片。
/// 自带 @Query 读取近 7 天饮食打卡，因此首页「饮食与饮水」与行动页「饮食」两个详情页
/// 都能直接复用，无需调用方注入数据。
struct MealTimelineCard: View {
    @Query private var records: [ActionCheckIn]

    /// 当前查看的日期：饮食详情可切换日期后，餐次与规律评分都跟随该日期。
    private let date: Date
    /// 全 App 统一的饮食评分（饮食质量 70% + 规律饮食 30%），由详情页头部传入。
    /// 卡片只展示这一个分数，规律饮食的明细作为构成说明，不再单独出分。
    private let unifiedScore: Double?

    init(date: Date = DayKey.startOfDay(.now), unifiedScore: Double? = nil) {
        let day = DayKey.startOfDay(date)
        self.date = day
        self.unifiedScore = unifiedScore
        let start = DayKey.addingDays(-7, to: day)
        let end = DayKey.addingDays(1, to: day)
        _records = Query(
            filter: #Predicate<ActionCheckIn> {
                $0.kindRaw == "meal" && $0.createdAt >= start && $0.createdAt < end
            },
            sort: \ActionCheckIn.createdAt,
            order: .reverse
        )
    }

    private var entries: [MealEntry] {
        records.compactMap { check in
            guard let slot = check.mealSlot else { return nil }
            return MealEntry(
                id: check.ensureSyncID(), date: check.createdAt, slot: slot,
                nutrition: check.nutrition, score: check.mealScore
            )
        }
    }

    private var dayRecords: [ActionCheckIn] {
        let key = DayKey.key(for: date)
        return records
            .filter { DayKey.key(for: $0.createdAt) == key }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: .now)
    }

    private var regularity: MealRegularity {
        MealScoringEngine.regularity(entries: entries, on: date)
    }

    var body: some View {
        VStack(spacing: 16) {
            regularityCard
            timelineCard
        }
    }

    // MARK: - 规律饮食

    private var regularityCard: some View {
        let r = regularity
        let score = unifiedScore
        let tint: Color = {
            guard let score else { return AppPalette.ink3 }
            if score >= ScoringConfig().mealRegularityGoodThreshold { return AppPalette.greenDeep }
            if score >= ScoringConfig().mealRegularityFairThreshold { return AppPalette.orange }
            return AppPalette.red
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppSectionHeader(title: "饮食评分", icon: "fork.knife", tint: tint)
                Spacer()
                Text(score == nil ? "暂无数据" : "质量 70% · 规律 30%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let score {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(score.rounded()))")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                    Text("/ 100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("近 7 天 \(r.stableDays) 天稳定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // 规律饮食明细作为评分构成说明，不再单独出分。
            Text(r.summary)
                .font(.footnote)
                .foregroundStyle(AppPalette.ink)

            HStack(spacing: 8) {
                ForEach(MealSlot.ordered.filter(\.isMainMeal)) { slot in
                    let covered = r.coveredMainMeals.contains(slot)
                    HStack(spacing: 4) {
                        Image(systemName: covered ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                        Text(slot.title)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(covered ? AppPalette.greenSoft : Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(covered ? AppPalette.greenDeep : .secondary)
                    .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(r.notes, id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(tint.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("饮食评分 = 营养质量 70% + 规律饮食 30%；规律部分依据三餐覆盖、进餐时段、餐间隔、夜宵与近 7 天进餐时刻稳定性。经验值，非医学建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
        .cardScrollEffect()
    }

    // MARK: - 今日餐次时间轴

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: isToday ? "今日餐次" : "当日餐次", icon: "fork.knife", tint: AppPalette.greenDeep)
            if dayRecords.isEmpty {
                Text(isToday ? "今天还没有饮食记录。点击右下角「＋」→「饮食」即可记录。" : "这一天没有饮食记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayRecords.enumerated()), id: \.element.id) { index, record in
                        timelineRow(record, isLast: index == dayRecords.count - 1)
                    }
                }
            }
        }
        .appCard()
        .cardScrollEffect()
    }

    private func timelineRow(_ record: ActionCheckIn, isLast: Bool) -> some View {
        let slot = record.mealSlot ?? .lunch
        let evaluation = MealScoringEngine.evaluate(
            nutrition: record.nutrition, slot: slot, date: record.createdAt
        )
        let score = record.mealScore ?? evaluation.score
        let healthy = (record.mealScore ?? evaluation.score) >= ScoringConfig().mealHealthyThreshold
            && evaluation.isHealthy
        let tint: Color = healthy ? AppPalette.greenDeep : AppPalette.orange
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: slot.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(AppPalette.greenDeep, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(AppPalette.line)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(slot.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(Self.timeFormatter.string(from: record.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(score.rounded())) 分")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text(healthy ? "健康" : evaluation.level)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }
                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("热量 \(Int(record.nutrition.energyKcal.rounded())) 千卡")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
