import SwiftUI

/// 当日记录：健康 App 全量样本 + 本 App 打卡，按 IntakeEntryMerger 去重后的结果。
/// 外部记录（健康 App 手动录入 / 第三方 App / Apple Watch）由健康 App 管理，本页只读展示。
struct IntakeRecordListView: View {
    let kind: ActionTileKind
    let date: Date
    let entries: [IntakeEntry]
    let notice: String?
    let onDelete: (IntakeEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    private var unit: String { kind == .water ? "ml" : "mg" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("合计")
                        Spacer()
                        Text("\(Int(IntakeEntryMerger.total(entries).rounded())) \(unit)")
                            .font(.headline.monospacedDigit())
                    }
                    HStack {
                        Text("记录条数")
                        Spacer()
                        Text("\(entries.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(dateTitle)
                }

                Section {
                    if entries.isEmpty {
                        Text("这一天还没有喝水或咖啡因记录。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(Int(entry.amount.rounded())) \(unit)")
                                        .font(.headline.monospacedDigit())
                                    Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(entry.sourceLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if entry.canDelete {
                                    Button(role: .destructive) {
                                        onDelete(entry)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("当日记录（含健康 App 同步）")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("记录来自健康 App（手动录入、第三方 App、Apple Watch）以及本 App 打卡；两侧按同步 ID 去重，不会重复计数。外部记录由健康 App 管理，本页不能删除。")
                        if let notice {
                            Text(notice)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("当日记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var dateTitle: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }
}

/// 右上角齿轮：每日目标 / 上限 + 自定义快捷按键。
/// 目标只影响展示与差额，不改变评分引擎的标准口径。
///
/// 目标值直接读写 `@AppStorage`（与行动页卡片、打卡页共用同一组键），
/// 保存后所有页面立刻同步 —— 之前用 @Binding 传递，行动页若走另一条读路径
/// 就会出现「配置里是 2000、卡片上还是 1500」的不一致。
struct IntakeGoalSettingsView: View {
    let kind: ActionTileKind

    @Environment(\.dismiss) private var dismiss
    @AppStorage(IntakeGoal.waterDefaultsKey) private var waterTargetMl = IntakeGoal.defaultWaterTargetMl
    @AppStorage(IntakeGoal.caffeineDefaultsKey) private var caffeineLimitMg = IntakeGoal.defaultCaffeineLimitMg
    @State private var text = ""
    @State private var actions: [IntakeQuickAction] = []

    private var isWater: Bool { kind == .water }
    private var unit: String { isWater ? "ml" : "mg" }

    /// 当前已保存的目标值：喝水取喝水目标，咖啡因取咖啡因上限。
    private var storedGoal: Double {
        isWater
            ? IntakeGoal.clamp(waterTargetMl, in: IntakeGoal.waterRange)
            : IntakeGoal.clamp(caffeineLimitMg, in: IntakeGoal.caffeineRange)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isWater ? "每日喝水目标（ml）" : "每日咖啡因上限（mg）", text: $text)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(isWater ? "每日目标" : "每日上限")
                } footer: {
                    Text(isWater
                         ? "默认 1500 ml，可在 100–10000 ml 之间调整。目标只影响本页展示与差额，不改变评分口径。"
                         : "默认 200 mg，可在 10–1000 mg 之间调整。上限只影响本页展示与差额，不改变评分口径。")
                }

                if isWater {
                    // 喝水只需要一个容量：每行一个输入框，右侧一个删除按钮。
                    Section {
                        ForEach($actions) { $action in
                            HStack(spacing: 12) {
                                TextField("容量（ml）", value: $action.amount, format: .number)
                                    .keyboardType(.decimalPad)
                                Text("ml")
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    actions.removeAll { $0.id == action.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(actions.count <= 1)
                                .accessibilityLabel("删除此快捷项")
                            }
                        }
                        actionListButtons
                    } header: {
                        Text("快捷按键（\(actions.count)/\(IntakeQuickActionStore.maxCount)）")
                    } footer: {
                        Text("每行填一个容量（ml），按钮文字自动显示为 +N ml；点击即写入健康 App 的饮水量。至少保留 1 个快捷项。")
                    }
                } else {
                    ForEach($actions) { $action in
                        Section {
                            IntakeQuickActionEditor(action: $action, isWater: false, unit: unit)
                            Button(role: .destructive) {
                                actions.removeAll { $0.id == action.id }
                            } label: {
                                Text("删除此快捷项")
                            }
                            .disabled(actions.count <= 1)
                        } header: {
                            Text(action.title.isEmpty ? "未命名快捷项" : action.title)
                        }
                    }

                    Section {
                        actionListButtons
                    } header: {
                        Text("快捷按键（\(actions.count)/\(IntakeQuickActionStore.maxCount)）")
                    } footer: {
                        Text("每个饮品会写入健康 App 的咖啡因（mg）与完整营养成分：热量 / 碳水 / 蛋白质 / 脂肪 / 纤维 / 糖 / 钠，删除记录时这些样本一起删除。营养值为 0 也会写入 0 样本，但不参与本 App 的饮食评分聚合。「水（ml）」既是该杯的基准容量，也会作为联动喝水量写回；打卡时点击饮品可先选本次喝的毫升数，咖啡因 / 营养 / 水量按「所选 ÷ 基准」等比换算。至少保留 1 个快捷项。打卡页的「瑞幸咖啡」是固定入口，展开可选官网产品，不占用这 6 个名额。")
                    }
                }

                Section("数据来源") {
                    Text("当日总量取自健康 App 的饮水 / 咖啡因样本，并与本 App 打卡合并去重。需要读取权限才能看到健康 App 里手动录入或第三方 App 写入的记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(kind.title)配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear {
                text = String(Int(storedGoal))
                actions = IntakeQuickActionStore.load(kind: kind.rawValue)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// 快捷按键列表底部的添加 / 恢复默认，喝水与咖啡因共用。
    private var actionListButtons: some View {
        Group {
            if actions.count < IntakeQuickActionStore.maxCount {
                Button {
                    actions.append(IntakeQuickAction.new(kind: kind.rawValue))
                } label: {
                    Label("添加快捷项", systemImage: "plus.circle.fill")
                }
            }
            Button("恢复默认") {
                actions = IntakeQuickActionStore.defaults(for: kind.rawValue)
            }
        }
    }

    private func save() {
        let raw = Double(text.replacingOccurrences(of: ",", with: ".")) ?? storedGoal
        if isWater {
            // 走 IntakeGoal 的写入函数：统一钳制口径，并顺手把新目标推给手表伴侣 App。
            waterTargetMl = IntakeGoal.setWaterTargetMl(raw)
        } else {
            caffeineLimitMg = IntakeGoal.clamp(raw, in: IntakeGoal.caffeineRange)
        }
        _ = IntakeQuickActionStore.save(actions, kind: kind.rawValue)
        dismiss()
    }
}

/// 配置页里单个快捷项的编辑行：名称 + 数量（+ 咖啡因的碳蛋脂）。
struct IntakeQuickActionEditor: View {
    @Binding var action: IntakeQuickAction
    let isWater: Bool
    let unit: String

    private var nutrition: Binding<IntakeNutrition> {
        Binding(
            get: { action.nutrition ?? IntakeNutrition() },
            set: { action.nutrition = $0 }
        )
    }

    var body: some View {
        TextField("按钮名称", text: $action.title)
        if isWater {
            TextField("数量（\(unit)）", value: $action.amount, format: .number)
                .keyboardType(.decimalPad)
        } else {
            Text("营养成分（每杯）")
                .font(.caption)
                .foregroundStyle(.secondary)
            nutrientRow("咖啡因", unit: "mg", value: $action.amount)
            nutrientRow("热量", unit: "kcal", value: nutrition.energyKcal)
            nutrientRow("碳水", unit: "g", value: nutrition.carbsG)
            nutrientRow("蛋白质", unit: "g", value: nutrition.proteinG)
            nutrientRow("脂肪", unit: "g", value: nutrition.fatG)
            nutrientRow("水", unit: "ml", value: nutrition.waterMl)
        }
    }

    /// 营养字段行：左侧常驻营养成分名称，右侧输入数值，避免占位符消失后分不清字段。
    private func nutrientRow(_ name: String, unit: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .foregroundStyle(.secondary)
            Text("（\(unit)）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }
}
