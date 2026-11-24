import SwiftData
import SwiftUI

/// 咖啡因打卡页里的固定「麦咖啡」快捷按钮：点击展开营养库「麦当劳麦咖啡」分组的全部产品，
/// 选中后按杯型估算咖啡因打卡，并写入该产品的热量 / 碳蛋脂与杯容量。
/// 该入口不写入 UserDefaults，不占用「设置 → 快捷按键」里可编辑的 6 个名额。
struct MccafeQuickActionButton: View {
    let tint: Color
    /// 呈现状态由打卡页持有：按钮位于 LazyVGrid 中，键盘弹出时会随网格重建，
    /// 若状态放在按钮自身，重建后归 false 会让选择弹窗被关掉。
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 10))
                    Text("麦咖啡")
                        .font(.system(size: 13, weight: .semibold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text("选产品")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 麦咖啡快捷入口：从营养库「麦当劳麦咖啡」分组构造咖啡因打卡项。
/// 咖啡因数值统一走 `MccafeCaffeineEstimate`（与饮食识别记录共用口径），
/// 牛奶 / 燕麦奶等无咖啡饮品返回 0，选择列表里标记为「无咖啡因」，
/// 选中后按 0mg 打卡（记录营养与含水量，不产生咖啡因剂量）。
enum MccafeCaffeine {
    /// 营养库中「麦当劳麦咖啡」分组 ID（见 FoodSeed）。
    static let groupID = "group.mcd.mccafe"

    /// 按品类 + 杯型估算咖啡因（毫克）。
    static func estimatedMg(for name: String) -> Double {
        MccafeCaffeineEstimate.estimatedMg(for: name)
    }

    /// 营养库里的一条麦咖啡产品 → 咖啡因快捷项（点击时构造，不落 UserDefaults）。
    static func quickAction(for food: CustomFood) -> IntakeQuickAction {
        var nutrition = food.nutrition
        nutrition.caffeineMg = estimatedMg(for: food.name)
        // waterMl 已在营养库按成分折算（牛奶 / 奶泡里的固形物不算水）。
        // 只有老数据仍为 0 时才按杯容量 90% 兜底；旧版直接写整杯容量会让奶咖虚增饮水。
        if nutrition.waterMl <= 0 {
            let portion = FoodDatabase.parsePortion(from: food.portion)
            if portion.unit.lowercased() == "ml" {
                nutrition.waterMl = (portion.amount * 0.9).rounded()
            }
        }
        return IntakeQuickAction(
            id: "mccafe-\(food.id)",
            title: food.name,
            amount: nutrition.caffeineMg,
            nutrition: nutrition
        )
    }

}

/// 麦咖啡产品选择列表：直接读取营养库「麦当劳麦咖啡」分组，按冰 / 热 / 其他分组并支持搜索。
struct MccafeDrinkPickerView: View {
    let onSelect: (CustomFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomFood.name, order: .forward) private var allFoods: [CustomFood]
    @State private var query = ""

    private struct DrinkSection: Identifiable {
        var title: String
        var foods: [CustomFood]
        var id: String { title }
    }

    private var pickerFoods: [CustomFood] {
        allFoods.filter { $0.groupID == MccafeCaffeine.groupID }
    }

    private var sections: [DrinkSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = pickerFoods.filter { food in
            guard !trimmed.isEmpty else { return true }
            return food.name.lowercased().contains(trimmed)
                || food.keywords.contains { $0.lowercased().contains(trimmed) }
        }
        let iced = matched.filter { $0.name.contains("冰") }
        let hot = matched.filter { $0.name.contains("热") }
        let other = matched.filter { !$0.name.contains("冰") && !$0.name.contains("热") }
        return [
            DrinkSection(title: "冰饮", foods: iced),
            DrinkSection(title: "热饮", foods: hot),
            DrinkSection(title: "其他", foods: other),
        ].filter { !$0.foods.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 固定搜索栏（不随列表滚动）：sheet 内用普通 TextField，点击可正常弹键盘。
                DrinkSearchField(prompt: "搜索麦咖啡产品", text: $query)
                List {
                    Section {
                        Text("读取营养库「麦当劳麦咖啡」分组的全部 \(pickerFoods.count) 款产品（2026-11-18 与官网 McCafé 列表核对）。官网只公示热量与宏量营养，咖啡因按品类与杯型估算：美式 / 奶铁小杯约 75mg、中杯约 110mg、大杯约 150mg，浓缩咖啡约 65mg、鲜萃咖啡约 110mg，抹茶 / 黑巧 / 雪冰更低；牛奶类无咖啡因。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.foods) { food in
                                let caffeine = MccafeCaffeine.estimatedMg(for: food.name)
                                Button {
                                    onSelect(food)
                                    dismiss()
                                } label: {
                                    row(food, caffeine: caffeine)
                                }
                                .buttonStyle(.plain)
                                // 无咖啡因饮品（牛奶 / 燕麦奶等，估 0mg）也允许选择：
                                // 打卡记录 0mg 咖啡因 + 产品营养 + 联动含水量，见打卡页 add(_:)。
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if sections.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("麦咖啡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ food: CustomFood, caffeine: Double) -> some View {
        HStack(spacing: 12) {
            FoodRemoteIcon(imageURL: food.imageURL, fallbackSymbol: "cup.and.saucer.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.subheadline.weight(.medium))
                Text(subtitle(for: food))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if caffeine > 0 {
                Text("≈ \(Self.number(caffeine)) mg")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.663, green: 0.455, blue: 0.310))
            } else {
                // 无咖啡因饮品：同样可点，直接按 0mg 打卡记录营养 / 含水量。
                Text("无咖啡因")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            // 所有行统一带箭头：无论有没有咖啡因剂量，点进去都是「选中直接打卡」。
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func subtitle(for food: CustomFood) -> String {
        let kcal = food.nutrition.energyKcal
        let energy = kcal > 0 ? "\(Int(kcal.rounded())) 千卡" : "热量未公示"
        return "\(food.portion) · \(energy)"
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
