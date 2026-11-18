import SwiftUI

struct SleepVitalsCard: View {
    let snapshot: DailySnapshot
    let history: [DailySnapshot]

    private var baseline: BaselineResult {
        Baseline.compute(history: history, today: snapshot)
    }

    private var sleepHRBaseline: (mean: Double, sd: Double)? {
        let todayStart = Calendar.current.startOfDay(for: snapshot.date)
        let start = DayKey.addingDays(-28, to: todayStart)
        let values = history.compactMap { item -> Double? in
            guard Calendar.current.startOfDay(for: item.date) >= start else { return nil }
            return item.sleepAvgHR
        }
        guard values.count >= 3,
              let mean = ScoreSupport.mean(values),
              let sd = ScoreSupport.standardDeviation(values)
        else { return nil }
        return (mean, max(sd, 2.0))
    }

    /// 血氧基线单独用「睡眠窗口内均值」构造：日间血氧与个人睡眠血氧口径不同，
    /// 混用会产生数量级错误的 σ 偏差。
    private var sleepSpo2Baseline: (mean: Double, sd: Double)? {
        let todayStart = Calendar.current.startOfDay(for: snapshot.date)
        let start = DayKey.addingDays(-28, to: todayStart)
        let values = history.compactMap { item -> Double? in
            let day = Calendar.current.startOfDay(for: item.date)
            guard day >= start, day < todayStart else { return nil }
            return ScoreSupport.spo2Percent(item.sleepAvgSpo2)
                .flatMap { MetricSanitizer.value($0, in: MetricRange.spo2) }
        }
        guard values.count >= 3,
              let mean = ScoreSupport.mean(values),
              let sd = ScoreSupport.standardDeviation(values)
        else { return nil }
        return (mean, max(sd, 0.5))
    }

    private struct VitalRow: Identifiable {
        let id: String
        let label: String
        let value: Double?
        let format: String
        let unit: String
        let z: Double?
    }

    private var rows: [VitalRow] {
        let hrZ = sleepHRBaseline.flatMap { stats in
            snapshot.sleepAvgHR.map { ($0 - stats.mean) / stats.sd }
        }
        // 历史落库可能还留着 0–1 比例值，统一换算成 0–100 百分数后再展示 / 比较。
        let spo2 = ScoreSupport.spo2Percent(snapshot.sleepAvgSpo2)
        let spo2Z = spo2.flatMap { value in
            sleepSpo2Baseline.map { (value - $0.mean) / $0.sd }
        }
        return [
            VitalRow(id: "hr", label: "心率", value: snapshot.sleepAvgHR, format: "%.0f", unit: "次/分", z: hrZ),
            VitalRow(id: "hrv", label: "HRV", value: snapshot.sleepAvgHRV, format: "%.0f", unit: "ms", z: snapshot.sleepAvgHRV.flatMap { baseline.zHRV($0) }),
            VitalRow(id: "resp", label: "呼吸", value: snapshot.sleepAvgResp, format: "%.1f", unit: "次/分", z: snapshot.sleepAvgResp.flatMap { baseline.zScore($0, stats: baseline.respiratoryRate) }),
            VitalRow(id: "spo2", label: "血氧", value: spo2, format: "%.0f", unit: "%", z: spo2Z),
            VitalRow(id: "temp", label: "腕温", value: snapshot.wristTempC, format: "%.1f", unit: "℃", z: snapshot.wristTempC.flatMap { baseline.zScore($0, stats: baseline.wristTempC) }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "睡眠生命体征", icon: "waveform.path.ecg.rectangle", tint: .teal)
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.caption.weight(.medium))
                        .frame(width: 36, alignment: .leading)
                    Text(row.value.map { String(format: row.format, $0) + " " + row.unit } ?? "—")
                        .font(.caption.monospacedDigit())
                        .frame(width: 86, alignment: .trailing)
                    zTrack(row.z)
                    Text(zText(row.z))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }
            Text("中心刻度为个人基线，圆点为当晚位置（±2.5σ 截断）。σ 是与近 28 天个人基线相差的标准差个数，±0.5σ 内记为「接近基线」；血氧基线取睡眠窗口均值。腕温为当日均值，其余为睡眠窗口内均值；仅展示，不参与评分。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func zTrack(_ z: Double?) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 4)
                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 1, height: 10)
                    .offset(x: width / 2)
                if let z {
                    let clamped = max(-2.5, min(2.5, z))
                    Circle()
                        .fill(abs(z) < 0.5 ? Color.teal : (z > 0 ? Color.orange : Color.blue))
                        .frame(width: 8, height: 8)
                        .offset(x: width / 2 + CGFloat(clamped / 2.5) * (width / 2) - 4)
                }
            }
        }
        .frame(height: 10)
    }

    private func zText(_ z: Double?) -> String {
        guard let z, z.isFinite else { return "基线不足" }
        if abs(z) < 0.5 { return "接近基线" }
        // 单位已经换算一致后不应再出现极大偏差；仍做一层显示保护。
        if abs(z) > 9.9 { return z > 0 ? "＞ +9.9σ" : "＜ −9.9σ" }
        return String(format: "%+.1fσ", z)
    }
}

// configured by qoder