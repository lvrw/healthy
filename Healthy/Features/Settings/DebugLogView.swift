import Combine
import SwiftUI
import UIKit

/// 日志等级筛选。nil 表示全部。
private enum LevelFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var id: String { rawValue }

    var level: AppLogLevel? {
        switch self {
        case .all: return nil
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}

/// App 内置日志查看器。设置 → 调试日志 进入。
/// 自动每 2 秒刷新，可搜索 / 按级别筛选 / 系统分享导出 / 清空 / 跑一次步数对账。
struct DebugLogView: View {
    @State private var entries: [AppLogEntry] = []
    @State private var searchText = ""
    @State private var levelFilter: LevelFilter = .all
    @State private var showShare = false
    @State private var showClearConfirm = false
    @State private var fileSize = "—"
    @State private var diagnosticReport: DiagnosticReport?
    @State private var isDiagnosing = false
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var filtered: [AppLogEntry] {
        let level = levelFilter.level
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries
            .filter { level == nil || $0.level == level }
            .filter { keyword.isEmpty || $0.message.lowercased().contains(keyword) || $0.category.lowercased().contains(keyword) }
            .reversed()
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("\(entries.count) 条 · \(fileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await runDiagnostic() }
                    } label: {
                        if isDiagnosing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("数据对账", systemImage: "figure.walk")
                                .font(.caption)
                        }
                    }
                    .disabled(isDiagnosing)
                }
            }

            Section {
                ForEach(filtered) { entry in
                    NavigationLink {
                        LogDetailView(entry: entry)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.level.symbol)
                                .font(.caption.monospaced())
                                .foregroundStyle(color(for: entry.level))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(entry.shortTime)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text(entry.category)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.message)
                                    .font(.caption)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            } footer: {
                if filtered.isEmpty {
                    Text("暂无日志。操作一下 App（比如同步健康数据）后会在这里出现。")
                }
            }
        }
        .navigationTitle("调试日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索内容或分类")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("级别", selection: $levelFilter) {
                        ForEach(LevelFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showShare = true
                    } label: {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清空日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(text: AppLog.shared.exportText())
        }
        .sheet(item: $diagnosticReport) { report in
            DiagnosticReportView(report: report.text)
        }
        .alert("清空全部日志？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                AppLog.shared.clear()
                refresh()
            }
        }
        .onAppear { refresh() }
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        entries = AppLog.shared.snapshot()
        fileSize = AppLog.shared.fileSizeDescription
    }

    private func runDiagnostic() async {
        isDiagnosing = true
        defer { isDiagnosing = false }
        let report = await StepDiagnostics.report()
        diagnosticReport = DiagnosticReport(text: report)
        refresh()
    }

    private func color(for level: AppLogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private struct LogDetailView: View {
    let entry: AppLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(entry.level.rawValue, systemImage: "flag")
                Text(Self.fullFormatter.string(from: entry.time))
                Text(entry.category)
                    .font(.headline)
                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("日志详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS XXX"
        return f
    }()
}

/// UIKit 分享面板的 SwiftUI 包装。
private struct ActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = UIView()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 步数对账报告刚好是 String，包一层 Identifiable 便于 .sheet(item:)。
private struct DiagnosticReport: Identifiable {
    let id = UUID()
    let text: String
}

private struct DiagnosticReportView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("步数对账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: report) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
