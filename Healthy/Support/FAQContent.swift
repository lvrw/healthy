import Foundation

enum FAQTopic: String, CaseIterable, Sendable {
    case stress
    case hrv
    case sleep
    case baseline
    case body

    var title: String {
        switch self {
        case .stress: return "压力"
        case .hrv: return "HRV"
        case .sleep: return "睡眠"
        case .baseline: return "个人基线"
        case .body: return "身体与心脏"
        }
    }
}

struct FAQItem: Identifiable, Equatable, Sendable {
    var id: String
    var topic: FAQTopic
    var question: String
    var answer: String
}

enum FAQContent {
    static let all: [FAQItem] = [
        FAQItem(
            id: "stress-what",
            topic: .stress,
            question: "什么是身体压力？",
            answer: "这里的压力指身体的生理应激水平，由 HRV、静息心率等指标相对个人基线的偏离估算，反映自主神经的紧张程度，不等同于情绪上的心理压力。疲劳、疾病、饮酒、咖啡因等都会影响它。"
        ),
        FAQItem(
            id: "stress-gray",
            topic: .stress,
            question: "为什么有的时段是灰色？",
            answer: "睡眠、运动，以及心率明显高于个人日均基线（可能正在活动）的时段不参与压力估算，只保留灰色标记，避免把正常活动误判为压力过载。"
        ),
        FAQItem(
            id: "stress-refresh",
            topic: .stress,
            question: "压力多久更新一次？",
            answer: "打开 App 或手动刷新时，会用最近的心率与 HRV 重新估算。Apple Watch 的心率约每几分钟记录一次，HRV 只在静息时偶尔测量，没有数据的时段不会强行给分。"
        ),
        FAQItem(
            id: "hrv-what",
            topic: .hrv,
            question: "什么是 HRV？",
            answer: "HRV（心率变异性）是相邻心跳间隔的差异程度。差异越大，通常说明自主神经调节越灵活、恢复状态越好；持续偏低可能与疲劳、压力或睡眠不足有关。"
        ),
        FAQItem(
            id: "hrv-higher",
            topic: .hrv,
            question: "HRV 越高越好吗？",
            answer: "在个人基线范围内偏高通常是好信号，但更重要的是看相对自己基线的长期趋势，而不是和别人比较绝对值。单次异常偏高或偏低都可能是测量误差。"
        ),
        FAQItem(
            id: "hrv-source",
            topic: .hrv,
            question: "这里的 HRV 和苹果健康一样吗？",
            answer: "数值直接来自 HealthKit 的 SDNN 读数，与苹果健康一致；本 App 额外做的是把它相对你过去 28 天的基线做标准化解读。"
        ),
        FAQItem(
            id: "baseline-what",
            topic: .baseline,
            question: "什么是个人基线？",
            answer: "基线是你过去 28 天各指标的均值与波动范围。所有评分都相对你自己的基线计算，而不是套用人群标准，因此需要连续佩戴积累数据。"
        ),
        FAQItem(
            id: "baseline-missing",
            topic: .baseline,
            question: "为什么有时不显示评分？",
            answer: "基线不足 3 天时置信度为「积累中」，不给总分；达到 7 天后评分才稳定。缺少某类数据时，对应分量会被跳过并按剩余权重归一化。"
        ),
        FAQItem(
            id: "sleep-restorative",
            topic: .sleep,
            question: "恢复性睡眠是什么？",
            answer: "深睡与 REM（快速眼动）睡眠合称恢复性睡眠，分别负责身体修复与大脑整理。成人参考占比约为深睡 13–23%、REM 20–25%，合计 33–48%。"
        ),
        FAQItem(
            id: "sleep-heart-rate",
            topic: .sleep,
            question: "睡眠心率多少算正常？",
            answer: "睡眠时平均心率 40–60 次/分通常代表恢复良好，60–75 属正常范围，持续高于 75 可能与疲劳、饮酒或压力有关。仅供参考，不构成医疗建议。"
        ),
        FAQItem(
            id: "sleep-excluded",
            topic: .sleep,
            question: "为什么睡眠时段不计入压力？",
            answer: "睡眠时心率自然下降，若按清醒口径估算会失真，因此睡眠时段在压力时间线上单独标记，不参与压力评分。"
        ),
        FAQItem(
            id: "body-age",
            topic: .body,
            question: "身体年龄是怎么算的？",
            answer: "以实际年龄为起点，把近 7 日的睡眠时长、睡眠一致性、睡眠效率、周运动量、步数、最大摄氧量、静息心率、HRV、体脂率、BMI、饮水与饮食质量逐项与参考带比较，血压、血糖、日照与正念取最近一次读数或近 7 日均值，各自加减岁数并单独封顶后求和。展开「影响因素」每一行可看到当前实测值、参考带与具体算式。当日尚未结束时，饮水、饮食、运动、日照、正念等累计量按实际清醒 / 日光窗口的进度折算，睡眠时段不计入，不会在清晨被判为「今日不足」。缺失数据的维度不参与，训练区间与力量训练分项暂无数据源。娱乐性估算，不是医学指标。"
        ),
        FAQItem(
            id: "body-age-speed",
            topic: .body,
            question: "衰老速度为什么是 1.0x？",
            answer: "1.0x 是标尺的中性基准：每过 1 年，身体年龄也增长 1 岁，和日历同步。真正的衰老速度取近 28 天身体年龄相对实际年龄的回归斜率：0.3x 表示只长 0.3 岁（老得更慢），-0.2x 表示身体年龄在下降，2.0x 表示一年长 2 岁。每个每日样本都要有完整 7 天数据窗口、趋势跨度至少 14 天且样本至少 7 个（约需 21 天连续数据），不足时不做拟合，按 1.0x 基准占位并标注「数据积累中」，此时的 1.0x 不是估算结果。它也不是「身体年龄 ÷ 实际年龄」：那个比值只反映当前比实际年龄大几岁，不反映变化快慢。"
        ),
        FAQItem(
            id: "body-age-adjustment",
            topic: .body,
            question: "影响因素里的 +x.x 岁 / -x.x 岁是什么意思？",
            answer: "它是这一项数据相对参考带给身体年龄加或减的岁数：橙色为加岁（身体年龄变大），绿色为减岁。例如睡眠 6.3 小时，(7 − 6.3) × 0.8 ≈ +0.6 岁；周运动 300 分钟则是 (150 − 300) × 0.01 = −1.5 岁。每项都有封顶，所有系数是经验设定，仅用于展示相对变化。"
        ),
        FAQItem(
            id: "body-heart",
            topic: .body,
            question: "心脏健康卡里的数值代表什么？",
            answer: "VO2max 反映心肺耐力，HRV 与静息心率反映自主神经状态，均与你过去 28 天的基线对比。持续异常变化时建议咨询医生，本 App 不做诊断。"
        ),
    ]

    static func items(for topic: FAQTopic) -> [FAQItem] {
        all.filter { $0.topic == topic }
    }
}

// configured by qoder