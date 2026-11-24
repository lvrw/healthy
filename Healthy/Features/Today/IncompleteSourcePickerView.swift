import SwiftUI

/// 手动标记「当天某类数据不全」的选择面板。
///
/// 每条标记按 dayKey 存储，只影响当天评分：对应评分分量被跳过，
/// 其余完整指标按剩余权重归一化；系统已判定不全的项目无需手动标记。
struct IncompleteSourcePickerView: View {
    /// 日期键，用于读写该天的标记。
    let dayKey: String
    /// 系统根据当天读数判定为不全的源，仅作提示展示。
    let autoMissing: Set<MetricSource>
    /// 目标日期的可读标签；传入时在标题中显示，便于区分历史日期的配置。
    let dateLabel: String?
    /// 标记变化后触发评分重算。
    let onChanged: () -> Void

    /// 当前日期已手动标记的源。
    @State private var marked: Set<MetricSource>
    @Environment(\.dismiss) private var dismiss

    init(
        dayKey: String,
        autoMissing: Set<MetricSource>,
        dateLabel: String? = nil,
        onChanged: @escaping () -> Void
    ) {
        self.dayKey = dayKey
        self.autoMissing = autoMissing
        self.dateLabel = dateLabel
        self.onChanged = onChanged
        _marked = State(initialValue: IncompleteSourceMarker.markedSources(for: dayKey))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("标记后，这类数据不参与该日期的评分，其他完整指标不受影响。系统判定数据不全的项目会自动跳过，无需手动标记。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("数据类别") {
                    ForEach(MetricSource.allCases, id: \.self) { source in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.label)
                                    .font(.body)
                                if autoMissing.contains(source) {
                                    Text("系统判定数据不全 · 已自动跳过")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(source.requirement)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else if marked.contains(source) {
                                    Text("手动标记 · 已跳过")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: binding(for: source))
                                .labelsHidden()
                        }
                        .contentShape(Rectangle())
                    }
                }
                if !marked.isEmpty {
                    Section {
                        Button("清除本日全部标记", role: .destructive) {
                            IncompleteSourceMarker.clear(dayKey: dayKey)
                            marked = []
                            onChanged()
                        }
                    }
                }
            }
            .navigationTitle(dateLabel.map { "标记数据不全 · \($0)" } ?? "标记数据不全")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    /// 单个数据源的开关绑定：先写持久化，再通知外部重算评分。
    /// - Parameter source: 数据类别。
    private func binding(for source: MetricSource) -> Binding<Bool> {
        Binding(
            get: { marked.contains(source) },
            set: { isOn in
                IncompleteSourceMarker.set(source, marked: isOn, dayKey: dayKey)
                if isOn {
                    marked.insert(source)
                } else {
                    marked.remove(source)
                }
                onChanged()
            }
        )
    }
}
