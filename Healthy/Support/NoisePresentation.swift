import Foundation

/// 环境音量的展示口径（行动页格子 / 行动详情逐日日历 / 数据来源说明）。
///
/// 数据来源链路：
/// Apple Watch（或 iPhone 麦克风）把环境音量写成健康 App 的
/// 「环境音量」样本 —— HealthKit `environmentalAudioExposure`，单位 dB(A)；
/// `HealthKitService.dailyAverages` 用 `HKStatisticsCollectionQuery`（`.discreteAverage`）
/// 按自然日求均值，落到 `DailyMetrics.environmentalNoiseDb`；
/// 行动页格子读 `DailyMetrics.snapshot.environmentalNoiseDb`，
/// 行动详情的逐日日历读 `ActionImpactEngine.metricValue(.quietUnder55)` —— 同一个字段，
/// 因此同一天的数值在两处必然一致（差异只可能来自「不同日期」或「白天未结束的部分日」）。
enum NoisePresentation {
    /// 判定阈值（dB(A)）：低于该值视为环境安静，与 InsightAction.quietUnder55 同口径。
    static let quietThreshold = 55.0

    /// 行动页格子主值：当日日均 dB。无样本时明确写「无数据」，不显示 0。
    static func tileValue(_ db: Double?) -> String {
        guard let db, db.isFinite else { return "无数据" }
        return "\(Int(db.rounded())) dB"
    }

    /// 行动页格子副值：点明「日均」口径，避免和日历里某一天的数值互相误解。
    static let tileCaption = "日均 · 目标 <55"

    /// 详情页里的完整写法。
    static func detailValue(_ db: Double) -> String {
        "\(Int(db.rounded())) dB"
    }

    /// 数据来源说明：行动详情页（环境音量）底部展示。
    static let sourceNote = """
    数据来自健康 App 的「环境音量」样本（HealthKit environmentalAudioExposure，dB(A)，由 Apple Watch / iPhone 麦克风采集）。
    这里的数值是「当日全部采样的日均」：健康 App 与逐日日历用的是同一批样本、同一个日均口径。
    需要注意两点：① 今天还没结束，日均会随新采样继续变化（清晨安静时段占比大，早上看起来会明显偏低）；
    ② 日均把睡眠等安静时长也算进去，所以它不代表「最吵的时刻」，只用来判断整体环境是否偏吵。
    """
}
