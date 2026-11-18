import Combine
import SwiftUI
import UIKit

/// 性能面板：按耗时聚合展示页面与接口的调用统计，定位卡顿来源。
///
/// 两套视图：
/// - 「统计」按名称聚合次数 / 平均 / P50 / P95 / 最大，慢项按阈值高亮，点进去看明细。
/// - 「明细」按时间倒序列出每一次调用（含成败与备注）。
/// 数据来自 PerformanceTrace，每秒刷新一次，可导出文本文件、清空。
struct PerformanceView: View {
    @State private var stats: [PerfStat] = []
    @State private var spans: [PerfSpan] = []
    @State private var fileSize = "—"
    @State private var categoryFilter: PerfCategory? = nil
    @State private var showShare = false
    @State private var showClearConfirm = false
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var filteredStats: [PerfStat] {
        guard let categoryFilter else { return stats }
        return stats.filter { $0.category == categoryFilter }
    }

    private var filteredSpans: [PerfSpan] {
        let base = spans.reversed()
        guard let categoryFilter else { return Array(base) }
        return Array(base.filter { $0.category == categoryFilter })
    }

    private var totalCalls: Int { filteredStats.reduce(0) { $0 + $1.count } }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .foregroundStyle(.secondary)
                    Text("\(totalCalls) 次调用 · \(fileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("分类", selection: $categoryFilter) {
                        Text("全部").tag(PerfCategory?.none)
                        ForEach(PerfCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(PerfCategory?.some(category))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            Section("统计（按平均耗时降序）") {
                if filteredStats.isEmpty {
                    Text("暂无数据。切换页面或触发同步 / AI 请求后会出现。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredStats) { stat in
                        NavigationLink {
                            PerfSpanListView(name: stat.name, spans: filteredSpans)
                        } label: {
                            PerfStatRow(stat: stat)
                        }
                    }
                }
            }

            Section("慢调用（P95 ≥ 800ms 或失败）") {
                let slow = filteredStats.filter { $0.isSlow || $0.failCount > 0 }
                if slow.isEmpty {
                    Text("没有检测到慢调用或失败。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(slow) { stat in
                        PerfStatRow(stat: stat)
                    }
                }
            }

            Section("最近明细（最新 100 次）") {
                ForEach(Array(filteredSpans.prefix(100))) { span in
                    PerfSpanRow(span: span)
                }
            }
        }
        .navigationTitle("性能监控")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showShare = true
                    } label: {
                        Label("导出数据", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清空数据", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(text: PerformanceTrace.shared.exportText())
        }
        .alert("清空全部性能数据？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                PerformanceTrace.shared.clear()
                refresh()
            }
        }
        .onAppear { refresh() }
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        stats = PerformanceTrace.shared.stats()
        spans = PerformanceTrace.shared.snapshot()
        fileSize = PerformanceTrace.shared.fileSizeDescription
    }
}

/// 单条聚合统计行。
private struct PerfStatRow: View {
    let stat: PerfStat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(stat.category.symbol)
                    .font(.caption.monospaced())
                    .foregroundStyle(tint)
                Text(stat.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(String(format: "%.0f ms", stat.avgMs))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint)
            }
            HStack(spacing: 12) {
                metric("平均", String(format: "%.0f", stat.avgMs))
                metric("P50", String(format: "%.0f", stat.p50Ms))
                metric("P95", String(format: "%.0f", stat.p95Ms))
                metric("最大", String(format: "%.0f", stat.maxMs))
                metric("次数", "\(stat.count)")
                if stat.failCount > 0 {
                    metric("失败", "\(stat.failCount)", warn: true)
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        if stat.failCount > 0 { return .red }
        return stat.isSlow ? .orange : .primary
    }

    private func metric(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(warn ? Color.red : Color.secondary)
        }
    }
}

/// 单次调用明细行。
private struct PerfSpanRow: View {
    let span: PerfSpan

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(span.category.symbol)
                .font(.caption.monospaced())
                .foregroundStyle(span.success ? Color.secondary : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(span.start.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text(span.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                if let detail = span.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(span.durationText)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(span.success ? (span.durationMs >= 800 ? Color.orange : Color.primary) : Color.red)
        }
    }
}

/// 某个名称下的全部调用明细。
private struct PerfSpanListView: View {
    let name: String
    let spans: [PerfSpan]

    private var matching: [PerfSpan] {
        spans.filter { $0.name == name }.reversed()
    }

    var body: some View {
        List {
            Section("\(matching.count) 次调用") {
                ForEach(matching) { span in
                    PerfSpanRow(span: span)
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// UIKit 分享面板包装（与调试日志页保持一致的导出体验）。
private struct ActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = UIView()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
