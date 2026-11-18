import SwiftData
import SwiftUI

/// 新增或编辑一条自定义食物。复用识别页的 NutrientField 做该数量营养的逐项输入。
struct FoodLibraryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let editing: CustomFood?
    /// 新建时预选的分组（从分组详情页进入时传入）。
    private let initialGroupID: String?

    @State private var name: String
    @State private var keywordsText: String
    @State private var portion: String
    @State private var nutrition: IntakeNutrition
    @State private var showExtendedNutrition = false
    @State private var selectedGroupID: String?
    @Query(sort: \FoodGroup.sortOrder, order: .forward) private var groups: [FoodGroup]

    init(editing: CustomFood? = nil, groupID: String? = nil) {
        self.editing = editing
        self.initialGroupID = groupID
        _name = State(initialValue: editing?.name ?? "")
        _keywordsText = State(initialValue: (editing?.keywords ?? []).joined(separator: "、"))
        _portion = State(initialValue: editing?.portion.isEmpty == false ? (editing?.portion ?? "") : "100g")
        _nutrition = State(initialValue: editing?.nutrition ?? .zero)
        _selectedGroupID = State(initialValue: editing?.groupID ?? groupID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("食物名称", text: $name)
                    TextField("别名 / 关键词（用、分隔，如 白饭、大米）", text: $keywordsText)
                    TextField("数量（如 150g / 330ml）", text: $portion)
                }
                Section("分组") {
                    Picker("所属分组", selection: $selectedGroupID) {
                        Text("不分组").tag(String?.none)
                        // 系统维护的品牌分组（isBuiltin）不允许用户把自己的食物加进去，
                        // 否则下次 FoodSeed.sync 会因为 groupID 匹配而把食物当成内置条目处理。
                        ForEach(groups.filter { !$0.isBuiltin }) { group in
                            Text(group.name).tag(group.id as String?)
                        }
                    }
                }
                Section("该数量营养") {
                    NutritionFieldsEditor(nutrition: $nutrition, fields: NutritionField.primaryFields)
                    Button {
                        showExtendedNutrition.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showExtendedNutrition ? "chevron.up" : "chevron.down")
                            Text("苹果健康其他营养指标（\(NutritionField.extendedFields.count) 项）")
                        }
                        .font(.caption)
                        .foregroundStyle(AppPalette.greenDeep)
                    }
                    .buttonStyle(.plain)
                    if showExtendedNutrition {
                        Text("未公示的指标保持 0。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        NutritionFieldsEditor(
                            nutrition: $nutrition,
                            fields: NutritionField.extendedFields,
                            labelWidth: 104
                        )
                    }
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            if let food = editing {
                                context.delete(food)
                                try? context.save()
                            }
                            dismiss()
                        } label: {
                            Text("删除这条食物")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增食物" : "编辑食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let keywords = keywordsText
            .split(separator: "、")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPortion = portion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "100g"
            : portion.trimmingCharacters(in: .whitespacesAndNewlines)

        if let food = editing {
            food.name = cleanName
            food.keywordsJSON = encode(keywords)
            food.portion = cleanPortion
            food.nutritionJSON = encode(nutrition)
            food.groupID = selectedGroupID
        } else {
            let food = CustomFood(name: cleanName, keywords: keywords, portion: cleanPortion, nutrition: nutrition, groupID: selectedGroupID)
            context.insert(food)
        }
        try? context.save()
        dismiss()
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
