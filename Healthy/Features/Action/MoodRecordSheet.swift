import SwiftData
import SwiftUI

struct MoodRecordSheet: View {
    var date: Date = .now

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allEntries: [MoodEntry]
    @State private var valence = 0.0
    @State private var note = ""
    @State private var tags: [String] = []

    private let tagOptions = ["工作", "学习", "运动", "社交", "家庭", "放松", "压力"]

    /// 与 Apple 健康「记录情绪」一致的七级色带：红 → 橙 → 黄 → 绿。
    private let moodLevels: [MoodLevel] = [
        MoodLevel(value: -1.0, emoji: "😖", label: "非常不愉快", color: .red),
        MoodLevel(value: -0.66, emoji: "🙁", label: "不愉快", color: .orange),
        MoodLevel(value: -0.33, emoji: "😕", label: "有点不愉快", color: .yellow),
        MoodLevel(value: 0.0, emoji: "😐", label: "一般", color: .gray),
        MoodLevel(value: 0.33, emoji: "🙂", label: "有点愉快", color: Color(red: 0.6, green: 0.75, blue: 0.2)),
        MoodLevel(value: 0.66, emoji: "😊", label: "愉快", color: .green),
        MoodLevel(value: 1.0, emoji: "😄", label: "非常愉快", color: .mint),
    ]

    private var key: String { DayKey.key(for: date) }

    private var existing: MoodEntry? {
        allEntries.first { $0.dayKey == key }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("你此刻的感受") {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Text(currentLevel.emoji)
                                .font(.system(size: 34))
                            Text(currentLevel.label)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(currentLevel.color)
                                .contentTransition(.opacity)
                        }
                        moodPicker
                    }
                    .padding(.vertical, 6)
                }
                Section("关联（可选）") {
                    FlowTags(selected: $tags, options: tagOptions)
                }
                Section("描述一下这种感受（可选）") {
                    TextField("发生了什么？", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("记录情绪")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
    }

    /// 七级情绪选择条：选中项放大并加白底，整体保持 Apple 健康的红→绿渐变观感。
    private var moodPicker: some View {
        HStack(spacing: 2) {
            ForEach(moodLevels) { level in
                let isSelected = currentLevel.id == level.id
                Button {
                    withAnimation(.snappy) {
                        valence = level.value
                    }
                } label: {
                    Text(level.emoji)
                        .font(.system(size: isSelected ? 24 : 20))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            isSelected ? Color(.systemBackground) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(level.label)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(
            LinearGradient(
                colors: moodLevels.map { $0.color.opacity(0.22) },
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    /// 最近的一档情绪，滑块 / 外部传入的值都归到七档之一。
    private var currentLevel: MoodLevel {
        let index = ((valence + 1) / 2 * Double(moodLevels.count - 1)).rounded()
        let clamped = min(Double(moodLevels.count - 1), max(0, index))
        return moodLevels[Int(clamped)]
    }

    private func save() {
        let row = existing ?? MoodEntry(dayKey: key, valence: valence)
        row.valence = valence
        row.note = note.isEmpty ? nil : note
        row.tags = tags
        if existing == nil {
            context.insert(row)
        }
        try? context.save()
        dismiss()
        // 同步到健康 App 的「心理状态」：未授权时先补一次写入授权，失败也不影响本地记录。
        let payload = HealthKitService.MoodSyncPayload(
            syncID: "mood-\(key)",
            date: date,
            valence: valence,
            note: row.note,
            tags: tags
        )
        Task {
            let service = HealthKitService()
            let canWrite = await service.canWriteStateOfMind()
            if !canWrite {
                _ = try? await service.requestAuthorization()
            }
            try? await service.saveStateOfMind(payload)
        }
    }
}

/// 七级情绪档位：Apple 健康「记录情绪」色带上的一个刻度。
private struct MoodLevel: Identifiable {
    let value: Double
    let emoji: String
    let label: String
    let color: Color

    var id: Double { value }
}

struct FlowTags: View {
    @Binding var selected: [String]
    let options: [String]

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains(option)
                Button {
                    if isOn {
                        selected.removeAll { $0 == option }
                    } else {
                        selected.append(option)
                    }
                } label: {
                    Text(option)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isOn ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// configured by qoder
