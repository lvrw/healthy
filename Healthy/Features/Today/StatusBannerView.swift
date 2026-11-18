import SwiftUI

/// 状态区展示样式：今日首页用 hero（居中、大字号），详情页沿用 inline（左对齐、紧凑）。
enum StatusBannerStyle {
    case inline
    case hero
}

struct StatusBannerView: View {
    let stress: Double?
    let readiness: Double?
    var confidenceRaw: String? = nil
    /// 原型 hero 文案右侧的 ⓘ 按钮，用于打开「压力水平」说明弹层。
    var onInfo: (() -> Void)? = nil
    /// 简介整块可点进入详情时，在问候语右侧显示箭头提示。
    var showsChevron: Bool = false
    var style: StatusBannerStyle = .inline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: TodayStatusPresentation {
        TodayStatusPresentation.make(stress: stress)
    }

    /// 原型句式「Hi …，你今日综合压力状态」。原型含具体用户名，当前 App 无该字段，
    /// 因此不硬编码人名，保留句式与信息按钮。
    private var caption: String { "Hi，你今日综合压力状态" }

    /// 原型状态大字为四档名称（状态优秀 / 状态正常 / 注意压力 / 压力过载）。
    private var stateWord: String {
        presentation.level?.displayName ?? presentation.word
    }

    var body: some View {
        Group {
            switch style {
            case .inline: inlineBody
            case .hero: heroBody
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: presentation.bandPosition)
    }

    // MARK: - 详情页 / 弹层内的紧凑样式

    private var inlineBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                infoLabel
                Spacer()
                if let confidenceRaw {
                    ConfidenceBadge(raw: confidenceRaw)
                }
            }
            Text(stateWord)
                .font(AppType.display(32))
                .foregroundStyle(presentation.level?.tint ?? Color.secondary)
                .contentTransition(.opacity)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                scoreLine
                Spacer()
                Text("相对 28 天个人基线 · 非医疗诊断")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            StressStatusScaleView(presentation: presentation)
                .frame(height: 20)
                .accessibilityLabel("压力状态四段指示，当前为\(stateWord)")
        }
        .padding(.top, 8)
    }

    // MARK: - 首页 Hero 样式

    /// 参考图布局：问候语、状态大字、四段状态条全部居中，下方一行小字补充评分与置信度。
    private var heroBody: some View {
        VStack(spacing: 10) {
            infoLabel
            Text(stateWord)
                .font(AppType.display(34))
                .foregroundStyle(presentation.level?.tint ?? Color.secondary)
                .contentTransition(.opacity)
            StressStatusScaleView(presentation: presentation)
                .frame(height: 20)
                .padding(.horizontal, 38)
                .accessibilityLabel("压力状态四段指示，当前为\(stateWord)")
            HStack(spacing: 8) {
                scoreLine
                if let confidenceRaw {
                    ConfidenceBadge(raw: confidenceRaw)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var infoLabel: some View {
        HStack(spacing: 6) {
            Text(caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppPalette.ink2)
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(AppPalette.ink4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看压力水平说明")
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.ink4)
            }
        }
    }

    @ViewBuilder
    private var scoreLine: some View {
        if let stress, let readiness {
            Text("状态 \(Int(readiness.rounded())) · 压力 \(Int(stress.rounded()))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        } else {
            Text("基线积累中，继续佩戴手表")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// 压力状态四段指示条：从左到右为 压力过载 → 注意压力 → 状态正常 → 状态优秀。
struct StressStatusScaleView: View {
    let presentation: TodayStatusPresentation

    var body: some View {
        GeometryReader { geometry in
            band(width: geometry.size.width)
        }
        .frame(height: 20)
    }

    /// 原型状态条从左到右为 压力过载 → 注意压力 → 状态正常 → 状态优秀，
    /// 与内部 stress 数值方向相反，且四段不等宽（1:1:1:2.4）。
    /// 将 stress 映射到所属等级段的区间内，保证 marker 颜色与所在分段一致。
    private func markerFraction(level: StressLevel?) -> Double? {
        guard let level, let position = presentation.bandPosition else { return nil }
        let stress = min(max(position, 0), 1)
        let segments = presentation.bandSegments
        guard segments.count == 4 else { return nil }
        let total = AppStatusScale.weights.reduce(0, +)
        var cumulative: [Double] = [0]
        for weight in AppStatusScale.weights {
            cumulative.append((cumulative.last ?? 0) + weight / total)
        }
        let bounds: (Double, Double, Double, Double)
        switch level {
        case .high:
            bounds = (segments[2], segments[3], cumulative[0], cumulative[1])
        case .elevated:
            bounds = (segments[1], segments[2], cumulative[1], cumulative[2])
        case .moderateLow:
            bounds = (segments[0], segments[1], cumulative[2], cumulative[3])
        case .low:
            bounds = (0, segments[0], cumulative[3], cumulative[4])
        }
        let lower = bounds.0
        let upper = bounds.1
        let clamped = min(max(stress, lower), upper)
        let ratio = upper > lower ? (upper - clamped) / (upper - lower) : 0
        return bounds.2 + ratio * (bounds.3 - bounds.2)
    }

    private func band(width: CGFloat) -> some View {
        let colors = AppStatusScale.colors
        let total = AppStatusScale.weights.reduce(0, +)
        let widths = AppStatusScale.weights.map { CGFloat($0 / total) * width }
        let levelIndex: Int = switch presentation.level {
        case .high: 0
        case .elevated: 1
        case .moderateLow: 2
        case .low: 3
        case nil: 3
        }
        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(Array(widths.enumerated()), id: \.offset) { index, segmentWidth in
                    Rectangle()
                        .fill(colors[index])
                        .frame(width: max(0, segmentWidth))
                }
            }
            .frame(height: 13)
            .clipShape(Capsule())
            .opacity(presentation.bandPosition == nil ? 0.25 : 1)
            if let fraction = markerFraction(level: presentation.level) {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(colors[levelIndex], lineWidth: 3))
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .offset(x: CGFloat(fraction) * max(0, width - 20))
            }
        }
        .frame(height: 20)
    }
}
