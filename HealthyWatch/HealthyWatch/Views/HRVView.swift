import SwiftUI

struct HRVView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                card(
                    title: "最新 HRV",
                    value: env.latestHRVms.map { String(format: "%.0f ms", $0) } ?? "—",
                    sub: env.latestHRVAt.map { "于 " + shortTime($0) } ?? "尚无数据"
                )
                card(
                    title: "今日均值",
                    value: env.todayHRVms.map { String(format: "%.0f ms", $0) } ?? "—",
                    sub: "SDNN 日均"
                )
                trendCard
            }
            .padding()
        }
        .navigationTitle("HRV")
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("近 7 天 HRV 趋势").font(.caption).foregroundStyle(.secondary)
            let last7 = Array(env.hrvTrend.suffix(7))
            let maxV = max(last7.map(\.sdnn).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(last7) { item in
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(Color.cyan.opacity(0.85))
                            .frame(height: max(4, CGFloat(item.sdnn / maxV) * 44))
                        Text(weekdaySymbol(item.date))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 62, alignment: .bottom)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
    }

    private func card(title: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold))
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
    }
}
