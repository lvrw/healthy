import SwiftUI

struct StressReadingDetailView: View {
    @Environment(\.openURL) private var openURL
    let reading: IntradayReading
    let summary: IntradaySummary
    let moodValence: Double?
    @State private var showMeasurementGuide = false
    @State private var showMoodRecord = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                sourceNote
                allData
                moodCard
                measureButton
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("读数详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMeasurementGuide) {
            MeasurementGuideSheet()
        }
        .sheet(isPresented: $showMoodRecord) {
            MoodRecordSheet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(reading.date.formatted(date: .omitted, time: .shortened)) 测量")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(levelColor)
                    .frame(width: 12, height: 12)
                Text(hrvText)
                    .font(AppType.display(34))
                Text(levelText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(levelColor)
            }
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Label("数据来源：Apple Watch", systemImage: "applewatch")
                if let stress = reading.stress {
                    Text("· 压力 \(Int(stress.rounded())) / 100")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private var previousReading: IntradayReading? {
        guard let index = summary.readings.firstIndex(where: { $0.date == reading.date }), index > 0 else { return nil }
        return summary.readings[index - 1]
    }

    private var sourceNote: some View {
        Text("HealthKit 的「心率变异性」使用 SDNN；iOS 27 的「恢复心率变异性」使用 RMSSD，两者算法不同，数值不可直接比较。Mean RR 由心率派生（60000/心率），属估算；pNN50、MxDMn、Moda、CV 需从逐拍 RR 间期序列统计，而 HealthKit 的光学心率只给 SDNN / RMSSD 聚合值、不含逐拍序列，因此本 App 暂不计算。Apple Watch 心电图（ECG，需手动测量、部分地区可用）的波形才含逐拍数据，详见「关于 HRV 与压力」。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(padding: 14)
    }

    private var allData: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("所有数据")
                .font(.headline)
            dataRow("SDNN", reading.sdnn.map { "\(Int($0.rounded())) ms" } ?? "—")
            dataRow("RMSSD（恢复 HRV）", reading.rmssd.map { "\(Int($0.rounded())) ms" } ?? "—")
            dataRow("当时心率", reading.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "—")
            dataRow("Mean RR（=60000/心率，派生）", reading.meanRRms.map { "\(Int($0.rounded())) ms" } ?? "—")
            if let previous = previousReading {
                let minutes = reading.date.timeIntervalSince(previous.date) / 60
                dataRow("距上次测量", minutes > 0 ? String(format: "%.0f 分钟", minutes) : "—")
            }
            dataRow("28 天 SDNN 基线", summary.baselineHRVms.map { "\(Int($0.rounded())) ms" } ?? "—")
            dataRow("偏离基线的 z 分数", reading.zScore.map { String(format: "%+.2f", $0) } ?? "—")
            dataRow("压力分", reading.stress.map { "\(Int($0.rounded())) / 100" } ?? "—")
            dataRow("压力等级", levelText)
        }
        .appCard()
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("关联感受", systemImage: "face.smiling")
                    .font(.headline)
                Spacer()
                Button("去记录") {
                    showMoodRecord = true
                }
                .font(.caption)
            }
            if let moodValence {
                Text("今天的心情：\(moodLabel(moodValence))（\(String(format: "%+.2f", moodValence))）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("今天还没有心情记录。点「去记录」在本 App 内记一笔（仅存本机），也可在健康 App 的「心理状态」里记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .appCard()
    }

    private var measureButton: some View {
        Button {
            showMeasurementGuide = true
        } label: {
            HStack {
                Label("立即测量 HRV", systemImage: "waveform.path.ecg")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .appCard()
        }
        .buttonStyle(.plain)
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private var hrvText: String {
        if let sdnn = reading.sdnn {
            return "\(Int(sdnn.rounded())) ms"
        }
        if let rmssd = reading.rmssd {
            return "RMSSD \(Int(rmssd.rounded())) ms"
        }
        return "—"
    }

    private var levelText: String {
        switch reading.level {
        case .low: return "放松"
        case .moderateLow: return "中低压力"
        case .elevated: return "压力偏高"
        case .high: return "压力过载"
        case nil: return "仅展示"
        }
    }

    private var levelColor: Color {
        switch reading.level {
        case .low: return .teal
        case .moderateLow: return .blue
        case .elevated: return .orange
        case .high: return .red
        case nil: return .gray
        }
    }

    private var explanation: String {
        guard let z = reading.zScore else {
            return "当前只有 RMSSD 读数，暂无 28 天基线，不参与压力评分。"
        }
        if z < -1 {
            return "此刻你的 HRV 明显低于个人基线，可能与身体疲劳、心理压力或睡眠不足有关；刚运动完 HRV 降低属于正常情况。"
        }
        if z > 1 {
            return "此刻你的 HRV 高于个人基线，恢复状态较好。"
        }
        return "此刻你的 HRV 接近个人基线，状态平稳。"
    }

    private func moodLabel(_ valence: Double) -> String {
        if valence <= -0.2 { return "消极" }
        if valence < 0.2 { return "中性" }
        return "积极"
    }

    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        openURL(url)
    }
}

struct StressReadingListView: View {
    let summary: IntradaySummary
    let moodValence: Double?

    var body: some View {
        List(summary.readings.reversed()) { reading in
            NavigationLink {
                StressReadingDetailView(
                    reading: reading,
                    summary: summary,
                    moodValence: moodValence
                )
            } label: {
                HStack {
                    Circle()
                        .fill(levelColor(reading.level))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.date.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.medium))
                        Text(readingSubtitle(reading))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(levelText(reading.level))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("今日记录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StressDayDetailView(summary: summary)
                } label: {
                    Text("当日详情")
                }
            }
        }
    }

    private func levelColor(_ level: StressLevel?) -> Color {
        switch level {
        case .low: return .teal
        case .moderateLow: return .blue
        case .elevated: return .orange
        case .high: return .red
        case nil: return .gray
        }
    }

    private func readingSubtitle(_ reading: IntradayReading) -> String {
        if let sdnn = reading.sdnn {
            return "SDNN \(Int(sdnn.rounded())) ms"
        }
        if let rmssd = reading.rmssd {
            return "RMSSD \(Int(rmssd.rounded())) ms"
        }
        return "—"
    }

    private func levelText(_ level: StressLevel?) -> String {
        switch level {
        case .low: return "放松"
        case .moderateLow: return "中低压力"
        case .elevated: return "压力偏高"
        case .high: return "压力过载"
        case nil: return "仅展示"
        }
    }
}

struct StressSourceInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    infoSection(
                        title: "SDNN 与 RMSSD",
                        text: "Apple 健康里的「心率变异性」是 SDNN；iOS 27 新增的「恢复心率变异性」是 RMSSD。两者计算方式不同，数值不能直接比较。本 App 的评分与 28 天基线使用 SDNN，RMSSD 只展示。"
                    )
                    infoSection(
                        title: "实时压力怎么算",
                        text: "此刻压力用最近一次心率、近 6 小时 HRV 与 28 天静息基线估算，0–100，越高压力越大。运动后心率升高属于正常，因此运动后参考意义有限。"
                    )
                    infoSection(
                        title: "今日压力时间线",
                        text: "按 15 分钟平均心率相对 28 天日均心率估算；检测到运动或处于睡眠时段的部分不参与，避免把运动心率误判为压力。"
                    )
                    infoSection(
                        title: "pNN50 / MxDMn / Moda / CV 怎么算",
                        text: """
                        这四个是传统 HRV 时域 / 几何指标，都要从一段连续的逐拍心搏间期（NN/RR 间期，单位毫秒）序列里统计。HealthKit 的光学心率只给聚合值（SDNN 或 RMSSD），不含逐拍序列，所以本 App 目前算不了。各自含义与算法：

                        • pNN50：相邻 NN 间期差值绝对值大于 50 ms 的相邻对数，占总相邻对数 (N−1) 的百分比，反映副交感（迷走）驱动的快速波动。公式：NN50 ÷ (N−1) × 100%，NN50 为满足 |RR(i) − RR(i−1)| > 50 ms 的对数。

                        • MxDMn（变异范围）：整段序列里最长间期减最短间期，即 max(RR) − min(RR)。它是 Baevsky 压力指数 SI 的分母项，值越小说明心率越收敛（压力下趋于稳定）。

                        • Moda（Mode）：NN 间期直方图里出现频率最高的区间的中心值（众数），即心脏最常回到的时间，可近似看作更稳健的平均 RR。

                        • CV（变异系数）：SDNN ÷ 平均 NN 间期 × 100%，是去除心率水平影响后的相对变异度。平均 NN 须取全部间期的算术平均，而不是 60000/心率 这种瞬时估算。

                        唯一可靠的逐拍数据来源是 Apple Watch 心电图（ECG）：你在手表上手动测量一次（约 30 秒）后，健康 App 里才会有这条 ECG 记录，其波形（单导联、512 Hz）可检测 R 峰还原出逐拍 RR 间期，进而算出上述指标。注意 ECG 需手动测量、单次仅 30 秒，且 Apple Watch 的 ECG 功能在部分地区（不含中国大陆）才可用；在此之前没有数据，本 App 不会展示这些指标。
                        """
                    )
                    infoSection(
                        title: "数据来源与限制",
                        text: "HRV 来自 Apple Watch 在静息、正念等时段的记录；心率大约每 5 分钟测量一次。HealthKit 不提供逐拍心搏间期（原始 RR 序列），因此 pNN50、Mean RR、MxDMn、Moda、CV 等需要逐拍序列的指标无法计算，本 App 不会展示。"
                    )
                    infoSection(
                        title: "非医疗建议",
                        text: "所有分数都是基于可穿戴设备的估计，不构成医疗诊断。如持续不适，请咨询医生。"
                    )
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("关于 HRV 与压力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func infoSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MeasurementGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step("1", "在 Apple Watch 上打开「正念」或「呼吸」，完成约 1 分钟。")
                    step("2", "或者保持静止 1–2 分钟，让手表在后台记录一次 HRV。")
                    step("3", "回到本页点「刷新」，新的读数会出现在今日趋势里。")
                    Text("iPhone 不能直接启动手表上的正念会话；需要你在手表上操作。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        openHealthApp()
                    } label: {
                        Label("打开健康 App", systemImage: "heart.text.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("测量 HRV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func step(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.subheadline)
        }
    }

    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        openURL(url)
    }
}
