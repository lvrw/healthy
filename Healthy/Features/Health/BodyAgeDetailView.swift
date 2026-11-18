import SwiftUI

/// 身体年龄详情页。对应 docs/ 原型：环形年龄 + 衰老速度标尺 + 影响因素逐项拆解。
struct BodyAgeDetailView: View {
    let result: BodyAgeResult
    var notice: String? = nil

    @State private var expandedFactor: BodyAgeFactor? = nil
    @State private var showSpeedExplanation = false

    private static let gradientColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ageHero
                speedCard
                factorsCard
                disclaimerCard
            }
            .padding(16)
        }
        .background(AppScreenBackground(tone: .peach))
        .navigationTitle("身体年龄")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 身体年龄

    private var ageHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.9))
                    .frame(width: 212, height: 212)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.blue, .mint, .green, .yellow, .orange, .pink, .purple, .blue],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .frame(width: 236, height: 236)
                    .opacity(0.85)
                VStack(spacing: 4) {
                    Text("身体年龄")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(result.ageText)
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(result.gapText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(result.gapColor)
                }
            }
            .frame(height: 250)

            if let age = result.chronologicalAge {
                Text(String(format: "实际年龄 %.1f 岁 · 各项影响合计 %+.1f 岁", age, result.ageGap ?? 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - 衰老速度

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("衰老速度")
                    .font(.headline)
                Spacer()
                Text(result.level?.label ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.speedColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(result.speedColor.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.speedText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(result.speedColor)
                Text("x")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                if result.isAgingSpeedBaseline {
                    Text("基准 · 数据积累中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
            }

            BodyAgeSpeedScale(speed: result.agingSpeed ?? BodyAgeScale.neutral)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
                Text(result.interpretation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(speedDataNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            DisclosureGroup("为什么基准是 1.0x？", isExpanded: $showSpeedExplanation) {
                Text(result.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
            .tint(.purple)
        }
        .appCard()
    }

    private var speedDataNote: String {
        if result.isAgingSpeedBaseline {
            return "每日随健康数据更新 · 约需 \(BodyAgeScale.minimumDataDays) 天连续数据（完整 7 天窗口 + ≥ \(BodyAgeScale.minimumSpanDays) 天趋势）"
        }
        return "每日随健康数据更新 · 近 \(result.sampleSpanDays) 天身体年龄趋势拟合"
    }

    // MARK: - 影响因素

    private var factorsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("影响因素")
                .font(.headline)
            Text("各维度相对参考带的加减岁数，展开可查看当前值与算式")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            let factors = BodyAgeFactor.allCases.sorted { $0.order < $1.order }
            ForEach(Array(factors.enumerated()), id: \.element.id) { item in
                factorRow(
                    factor: item.element,
                    adjustment: result.adjustments.first { $0.factor == item.element }
                )
                if item.offset < factors.count - 1 {
                    Divider().opacity(0.6)
                }
            }

            Text("饮水量为健康 App 同步值与本 App 喝水打卡的合并结果，饮食质量来自健康 App 的营养记录，两者均取近 7 日均值；睡眠效率、HRV、BMI、血压、血糖、日照与正念为扩展维度，取近 7 日均值或最近一次读数。今日尚未过完时，累计型指标按清醒 / 日光窗口进度折算，睡眠时段不计入；缺失的维度不参与估算。原型中的 Z1–Z3 / Z4–Z5 训练时长与力量训练时长暂无对应数据源（TODO: 接入 workouts 心率区间）；体脂率需要档案里填写性别。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .appCard()
    }

    private func factorRow(factor: BodyAgeFactor, adjustment: BodyAgeAdjustment?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedFactor = expandedFactor == factor ? nil : factor
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: factor.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(factorColor(adjustment))
                        .frame(width: 28, height: 28)
                        .background(factorColor(adjustment).opacity(0.12), in: Circle())
                    Text(factor.title)
                        .font(.subheadline)
                        .foregroundStyle(adjustment == nil ? .secondary : .primary)
                    Spacer()
                    if let adjustment {
                        Text(String(format: "%+.1f 岁", adjustment.years))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(factorColor(adjustment))
                    } else {
                        Text("暂无数据")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expandedFactor == factor ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if expandedFactor == factor {
                VStack(alignment: .leading, spacing: 7) {
                    if let adjustment {
                        detailLine("当前值", adjustment.measured)
                        detailLine("参考带", adjustment.reference)
                        detailLine("怎么算", adjustment.formula)
                        Text(adjustment.note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("近 7 天没有读到这一项的数据，或缺少计算所需的前提（例如性别）。缺失的维度不参与加减，也不会被当成 0 分凑数。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func factorColor(_ adjustment: BodyAgeAdjustment?) -> Color {
        guard let years = adjustment?.years else { return .secondary }
        if years > 0.05 { return .orange }
        if years < -0.05 { return .green }
        return .secondary
    }

    // MARK: - 说明

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: "关于这个估算", icon: "info.circle.fill", tint: .purple)
            Text("身体年龄 = 实际年龄 + 各项影响之和。每一项都相对自己的参考带加减，并单独封顶；缺失的数据不参与计算。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("衰老速度看的是最近这段时间身体年龄的变化快慢，1.0x 表示与日历同速。两者都是娱乐性可视化估算，所有系数为经验设定，不是医学指标，也不能替代医生诊断。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("数据来源：本机 HealthKit 近 7 日窗口；每日随同步更新。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }
}

/// 原型里的 -1x ~ 3x 渐变标尺，1x 为中性基准刻度。
struct BodyAgeSpeedScale: View {
    var speed: Double
    var showLabels: Bool = true

    private var fraction: CGFloat {
        let clamped = min(max(speed, BodyAgeScale.lower), BodyAgeScale.upper)
        return CGFloat((clamped - BodyAgeScale.lower) / (BodyAgeScale.upper - BodyAgeScale.lower))
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let markerX = min(max(width * fraction, 7), width - 7)
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .teal, .blue, .purple, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width, height: 8)
                        .position(x: width / 2, y: 8)
                    // 1x 在标尺正中（-1x ~ 3x 的 50%），作为基准参考线。
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: 14)
                        .position(x: width / 2, y: 8)
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .position(x: markerX, y: 8)
                }
            }
            .frame(height: 18)

            if showLabels {
                HStack {
                    Text("-1x")
                    Spacer()
                    Text("1x")
                    Spacer()
                    Text("3x")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
    }
}

/// 摘要卡与详情页共用的展示口径，避免两处数字/配色漂移。
extension BodyAgeResult {
    var ageText: String {
        guard let bodyAge else { return "—" }
        return String(format: "%.1f", bodyAge)
    }

    var gapText: String {
        guard let gap = ageGap else { return "无法估算" }
        if abs(gap) < 0.05 { return "与实际年龄持平" }
        return String(format: "%@ %.1f 岁", gap > 0 ? "多" : "少", abs(gap))
    }

    /// 不带符号的一位小数，页面自行拼接「x」；负值自带「-」。
    var speedText: String {
        guard let speed = agingSpeed else { return "—" }
        return String(format: "%.1f", speed)
    }

    var gapColor: Color {
        guard let gap = ageGap else { return .secondary }
        if abs(gap) < 0.05 { return .secondary }
        return gap > 0 ? .orange : .green
    }

    var speedColor: Color {
        guard let level else { return .secondary }
        switch level {
        case .younger: return .green
        case .normal: return .blue
        case .accelerated: return .orange
        }
    }
}

// configured by qoder
