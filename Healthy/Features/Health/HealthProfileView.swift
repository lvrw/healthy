import SwiftData
import SwiftUI

/// 「健康」页所有昂贵派生数据的一次性快照。
/// 原先这些值都是 body 里的 computed property，SwiftUI 每次求值都要重跑
/// 84 天身体年龄回归（Debug 构建约 45ms），切页与滚动时会明显掉帧。
/// 现在改为后台算一次，按数据版本失效，body 只读缓存。
private struct HealthDerived: Sendable {
    let bodyAgeResult: BodyAgeResult
    let baseline: BaselineResult
    let sevenDayAverage: [Double?]
    let bodyCompositionScore: Double?
    /// 基础代谢及其数据来源；后台算一次，body 只读缓存。
    let bmr: BMREstimate?
}

struct HealthProfileView: View {
    @Query(sort: \DailyMetrics.dayKey, order: .reverse) private var metrics: [DailyMetrics]
    @Query(sort: \DailyScore.dayKey, order: .reverse) private var scores: [DailyScore]
    @Environment(\.openURL) private var openURL
    /// 全局数据同步入口：顶部下拉刷新时重新拉取 HealthKit 数据并重算评分。
    @Environment(AppModel.self) private var appModel
    @State private var characteristics = HealthCharacteristics(chronologicalAge: nil, isMale: nil)
    @State private var didLoadCharacteristics = false
    /// 后台算好的派生数据；未就绪时页面显示轻量占位，不再阻塞主线程。
    @State private var derived: HealthDerived?

    private func loadCharacteristics(force: Bool = false) async {
        guard force || !didLoadCharacteristics else { return }
        didLoadCharacteristics = true
        let service = HealthKitService()
        // 出生日期/性别需先向 HealthKit 声明读取，否则 dateOfBirthComponents() 抛 notDetermined。
        let perfToken = PerformanceTrace.shared.begin("页面 · 健康 · 读取特征", category: .page)
        defer { PerformanceTrace.shared.end(perfToken) }
        await service.ensureCharacteristicAuthorization()
        characteristics = await service.fetchCharacteristics()
    }

    private var today: DailyMetrics? { metrics.first }
    private var todayScore: DailyScore? { scores.first }

    /// 派生数据版本：行数、最新写入时间、评分时间、个人资料任一变化才重算。
    /// 滚动、选中态等普通重绘直接复用缓存，不再重跑 84 天身体年龄回归。
    private var derivedVersion: String {
        let profile = UserProfile.load()
        return [
            "\(metrics.count)",
            metrics.first?.dayKey ?? "",
            "\(metrics.first?.updatedAt.timeIntervalSince1970 ?? 0)",
            "\(scores.first?.computedAt.timeIntervalSince1970 ?? 0)",
            "\(profile.birthDate?.timeIntervalSince1970 ?? 0)",
            profile.isMale.map { $0 ? "M" : "F" } ?? "-",
            "\(characteristics.chronologicalAge ?? 0)",
            characteristics.isMale.map { $0 ? "M" : "F" } ?? "-",
        ].joined(separator: "|")
    }

    /// 主线程取 SwiftData 值快照，纯计算放后台；结果写回 @State 后 body 只读缓存。
    @MainActor
    private func refreshDerived() async {
        let perfToken = PerformanceTrace.shared.begin("页面 · 健康 · 派生数据重算", category: .page)
        defer { PerformanceTrace.shared.end(perfToken) }
        let snapshots = metrics.map(\.snapshot)
        let profile = UserProfile.load()
        let healthKitAge = characteristics.chronologicalAge
        let healthKitMale = characteristics.isMale
        let componentsJSON = todayScore?.readinessComponentsJSON
        let now = Date()
        let calendar = Calendar.current
        derived = await Task.detached(priority: .userInitiated) {
            Self.makeDerived(
                snapshots: snapshots,
                profile: profile,
                healthKitAge: healthKitAge,
                healthKitMale: healthKitMale,
                componentsJSON: componentsJSON,
                now: now,
                calendar: calendar
            )
        }.value
    }

    /// 与原 computed property 完全相同的计算口径，只是集中执行一次。
    /// nonisolated：View 成员默认继承 MainActor，这里必须在后台线程可调用。
    private nonisolated static func makeDerived(
        snapshots: [DailySnapshot],
        profile: UserProfile,
        healthKitAge: Double?,
        healthKitMale: Bool?,
        componentsJSON: String?,
        now: Date,
        calendar: Calendar
    ) -> HealthDerived {
        let effective = profile.effective(
            healthKitAge: healthKitAge, healthKitMale: healthKitMale,
            now: now, calendar: calendar
        )
        let age = effective.chronologicalAge
        let isMale = effective.isMale

        let bodyAgeInput = BodyAgeEngine.input(
            asOf: now, snapshots: snapshots, chronologicalAge: age, isMale: isMale,
            now: now, calendar: calendar
        )
        let bodyAgeSamples = BodyAgeEngine.samples(
            snapshots: snapshots, chronologicalAge: age, isMale: isMale,
            now: now, calendar: calendar
        )
        let bodyAgeResult = BodyAgeEngine.evaluate(
            bodyAgeInput, samples: bodyAgeSamples, now: now, calendar: calendar
        )

        let baseline: BaselineResult
        if let latest = snapshots.first {
            baseline = Baseline.compute(history: Array(snapshots.dropFirst()), today: latest)
        } else {
            baseline = BaselineResult(baselineDays: 0)
        }

        // VO2max 是稀疏读数：今天没测不代表没有值，取近 28 天最近一次读数。
        let cutoff = DayKey.addingDays(-28, to: DayKey.startOfDay(now, calendar: calendar), calendar: calendar)
        let latestVO2Max = snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .last { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) != nil }
            .flatMap { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) }

        let week = Array(snapshots.prefix(7))
        func average(_ extract: (DailySnapshot) -> Double?) -> Double? {
            let values = week.compactMap(extract)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let exercise = week.compactMap(\.exerciseMinutes).reduce(0, +)
        let sevenDayAverage: [Double?] = [
            average(\.restingHR),
            average(\.sleepTotalH),
            week.isEmpty ? nil : exercise,
            latestVO2Max,
            snapshots.first?.leanBodyMassKg,
        ]

        let composition: Double?
        if let json = componentsJSON,
           let data = json.data(using: .utf8),
           let components = try? JSONDecoder().decode(ReadinessComponents.self, from: data) {
            composition = components.bodyComposition
        } else {
            composition = nil
        }

        return HealthDerived(
            bodyAgeResult: bodyAgeResult,
            baseline: baseline,
            sevenDayAverage: sevenDayAverage,
            bodyCompositionScore: composition,
            bmr: BodyAgeEngine.bmrEstimate(snapshots: snapshots, now: now, calendar: calendar)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // 原型「健康」页标题下的副标题。
                    Text("身体比你想象的更诚实，它记得你每一次选择")
                        .font(AppType.small)
                        .foregroundStyle(AppPalette.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if metrics.isEmpty {
                        ContentUnavailableView(
                            "还没有健康数据",
                            systemImage: "heart.text.square",
                            description: Text("同步 HealthKit 或载入示例数据后查看。")
                        )
                        .padding(.top, 60)
                    } else if let derived {
                        bodyAgeCard(derived)
                        bodyConditionCard(derived)
                        heartCard(derived)
                        energyCard(derived)
                        trainingZonesCard
                        faqCard
                    } else {
                        ProgressView("正在计算身体指标…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .padding(16)
            }
            // 顶部下拉刷新：同步数据 + 重读身高体重等特征，数据版本变化自动重算派生指标。
            .withPullToRefresh {
                await appModel.sync()
                await loadCharacteristics(force: true)
            }
            .background(AppScreenBackground(tone: .mint))
            .navigationTitle("健康")
            .task {
                await loadCharacteristics()
            }
            .task(id: derivedVersion) {
                await refreshDerived()
            }
        }
    }

    private func bodyAgeCard(_ derived: HealthDerived) -> some View {
        // 直接读后台算好的结果，body 求值不再触发 84 天回归。
        let result = derived.bodyAgeResult
        return Group {
            if result.bodyAge != nil {
                NavigationLink {
                    BodyAgeDetailView(result: result, notice: characteristics.notice)
                } label: {
                    bodyAgeSummary(result: result)
                }
                .buttonStyle(.plain)
            } else {
                bodyAgeMissingCard
            }
        }
    }

    /// 健康 Tab 摘要卡：数字 + 衰老速度标尺，点进详情页看逐维度拆解。
    private func bodyAgeSummary(result: BodyAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "身体年龄",
                icon: "hourglass",
                tint: .purple,
                trailing: AnyView(
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                )
            )
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(result.ageText + " 岁")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.purple)
                Text(result.gapText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(result.gapColor)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("衰老速度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.speedText + "x")
                    .font(.headline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(result.speedColor)
                Spacer()
                if result.isAgingSpeedBaseline {
                    Text("基准 · 数据积累中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(result.level?.label ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            BodyAgeSpeedScale(speed: result.agingSpeed ?? BodyAgeScale.neutral)
            Text("查看各维度对年龄的影响与计算方式 ›")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let notice = characteristics.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .appCard()
    }

    private var bodyAgeMissingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "身体年龄", icon: "hourglass", tint: .purple)
            Text((characteristics.notice ?? "还无法估算身体年龄：需要先知道出生年份与性别。") + "可在本 App「设置 → 基本资料」直接填写（仅存本机）。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("打开健康 App") {
                    if let url = URL(string: "x-apple-health://") {
                        openURL(url)
                    }
                }
                Button("重新读取") {
                    didLoadCharacteristics = false
                    HealthKitService.clearCharacteristicsCache()
                    Task {
                        await loadCharacteristics(force: true)
                    }
                }
            }
            .font(.subheadline)
        }
        .appCard()
    }

    /// 身体状况：体重 / 体脂 / 肌肉量 / BMI / 腰围，点进详情看趋势。
    @ViewBuilder
    private func bodyConditionCard(_ derived: HealthDerived) -> some View {
        if let group = MetricGroupFactory.bodyCompositionGroup(metrics: metrics) {
            NavigationLink {
                MetricGroupDetailView(
                    group: group,
                    score: derived.bodyCompositionScore,
                    metrics: metrics
                )
            } label: {
                MetricGroupCard(
                    title: group.title,
                    icon: group.icon,
                    tint: group.tint,
                    rows: group.rows,
                    footnote: group.footnote,
                    score: derived.bodyCompositionScore,
                    showsDetail: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func heartCard(_ derived: HealthDerived) -> some View {
        let values = derived.sevenDayAverage
        let baseline = derived.baseline
        return VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "心脏健康", icon: "heart.fill", tint: .red)
            metricLine(
                title: "VO2max",
                value: values[3].map { String(format: "%.1f ml/kg/min", $0) } ?? "—",
                detail: baseline.vo2Max.map { String(format: "28 天基线 %.1f", $0.mean) } ?? "基线积累中"
            )
            metricLine(
                title: "HRV（SDNN）",
                value: today?.hrvSDNN.map { "\(Int($0.rounded())) ms" } ?? "—",
                detail: baseline.hrvLog.map { String(format: "基线 %.0f ms", exp($0.mean) - 1) } ?? "基线积累中"
            )
            metricLine(
                title: "静息心率",
                value: values[0].map { "\(Int($0.rounded())) 次/分" } ?? "—",
                detail: baseline.restingHR.map { String(format: "基线 %.0f 次/分", $0.mean) } ?? "基线积累中"
            )
            Text("以上均与你的 28 天个人基线对比，不构成医疗建议；持续异常请咨询医生。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func metricLine(title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private func energyCard(_ derived: HealthDerived) -> some View {
        let bmr = derived.bmr
        return VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "能量消耗", icon: "flame.fill", tint: .orange)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bmr.map { "\(Int($0.kcal.rounded()))" } ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("基础代谢（千卡/天）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(today?.activeEnergy.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("今日活动消耗（千卡）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(bmrNote(for: bmr?.source))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    /// 按基础代谢的数据来源给出对应口径说明；无数据时明确告知缺什么。
    private func bmrNote(for source: BMRSource?) -> String {
        switch source {
        case .basalEnergy(let days)?:
            return "没有体成分记录时暂用健康 App「静息能量」近 \(days) 个完整日均值兜底；同步一次体重、体脂或去脂体重后会改回公式计算。"
        case .basalEnergyTodayProjection?:
            return "没有体成分记录时暂用今日「静息能量」按已过时间折算全天兜底；同步体成分后改回公式计算，估算值仅供参考。"
        case .leanBodyMass?:
            return "Katch-McArdle：370 + 21.6 × 去脂体重（kg）。去脂体重取最近一次记录（体成分不是每天都测），估算值仅供参考。"
        case .estimatedLeanBodyMass?:
            return "去脂体重由最近一次体重 ×（1 − 体脂率）推算；基础代谢用 Katch-McArdle 公式（370 + 21.6 × 去脂体重），估算值仅供参考。"
        case nil:
            return "基础代谢按 Katch-McArdle 公式计算，需要体重与体脂率（或去脂体重）；健康 App 里连静息能量兜底数据也没有时暂无法估算。"
        }
    }

    private var faqCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "常见问题", icon: "questionmark.circle.fill", tint: .blue)
            FAQListView(topic: .body)
        }
        .appCard()
    }

    // Z1–Z5 配色：恢复→极限 由冷到暖。
    private let trainingZoneColors: [Color] = [
        Color(red: 0.36, green: 0.71, blue: 0.36),
        Color(red: 0.20, green: 0.70, blue: 0.66),
        Color(red: 0.26, green: 0.58, blue: 0.93),
        Color(red: 0.96, green: 0.62, blue: 0.18),
        Color(red: 0.90, green: 0.32, blue: 0.30),
    ]

    @ViewBuilder
    private var trainingZonesCard: some View {
        let zones = today?.workoutZones
        let total = zones?.total ?? (today?.workoutMinutes ?? 0)
        let count = today?.workoutCount ?? 0
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "训练区间", icon: "figure.run", tint: .orange)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(total.rounded()))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("训练分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if count > 0 {
                    Text("\(count) 次训练")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let zones, zones.total > 0 {
                // 5 区间堆叠条
                HStack(spacing: 2) {
                    ForEach(Array(zones.minutes.enumerated()), id: \.offset) { index, minutes in
                        if minutes > 0 {
                            Rectangle()
                                .fill(trainingZoneColors[index])
                                .frame(width: max(CGFloat(minutes / zones.total) * 240, 3), height: 12)
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // 图例
                HStack(spacing: 12) {
                    ForEach(Array(zones.minutes.enumerated()), id: \.offset) { index, minutes in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(trainingZoneColors[index])
                                .frame(width: 8, height: 8)
                            Text("\(WorkoutZoneMinutes.labels[index]) \(Int(minutes.rounded()))′")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("今日训练时长已记录，但心率区间需先在「设置 → 基本资料」填写年龄、重新同步后才会计算。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text("区间按最大心率百分比划分（Z1 恢复 <60% → Z5 极限 ≥90%），来自 workouts 时间窗内的心率采样。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }
}

// configured by qoder
