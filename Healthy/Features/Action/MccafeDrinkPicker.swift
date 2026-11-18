import SwiftData
import SwiftUI

/// 咖啡因打卡页里的固定「麦咖啡」快捷按钮：点击展开营养库「麦当劳麦咖啡」分组的全部产品，
/// 选中后按杯型估算咖啡因打卡，并写入该产品的热量 / 碳蛋脂与杯容量。
/// 该入口不写入 UserDefaults，不占用「设置 → 快捷按键」里可编辑的 6 个名额。
struct MccafeQuickActionButton: View {
    let tint: Color
    let onSelect: (CustomFood) -> Void

    @State private var showsPicker = false

    var body: some View {
        Button {
            showsPicker = true
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
        .sheet(isPresented: $showsPicker) {
            MccafeDrinkPickerView(onSelect: onSelect)
        }
    }
}

/// 麦咖啡的咖啡因估算：官方营养计算器只公示热量与宏量营养，不公示咖啡因，
/// 因此按「品类 + 杯型」给出可解释的估算值，供咖啡因打卡使用。
/// 牛奶 / 燕麦奶等无咖啡饮品返回 0，选择列表里标记为「无咖啡因」，
/// 选中后按 0mg 打卡（记录营养与含水量，不产生咖啡因剂量）。
enum MccafeCaffeine {
    /// 营养库中「麦当劳麦咖啡」分组 ID（见 FoodSeed）。
    static let groupID = "group.mcd.mccafe"

    static func estimatedMg(for name: String) -> Double {
        let size = cupSize(of: name)
        if name.contains("阿芙佳朵") { return name.contains("抹茶") ? 15 : 45 }
        // 滴滤黑咖（2025-02 上架，无杯型名）：按中杯美式档估算。
        if name.contains("鲜萃") { return 110 }
        // 单份浓缩 espresso：低于中杯奶咖档，单独给可解释的估算值。
        if name.contains("浓缩咖啡") { return 65 }
        if name.contains("抹茶") { return size == .large ? 60 : 45 }
        if name.contains("黑巧") { return size == .large ? 30 : 25 }
        if name.contains("雪冰") { return size == .large ? 12 : 10 }
        guard containsCoffee(name) else { return 0 }
        switch size {
        case .small: return 75
        case .medium, .unspecified: return 110
        case .large: return 150
        }
    }

    /// 营养库里的一条麦咖啡产品 → 咖啡因快捷项（点击时构造，不落 UserDefaults）。
    static func quickAction(for food: CustomFood) -> IntakeQuickAction {
        var nutrition = food.nutrition
        nutrition.caffeineMg = estimatedMg(for: food.name)
        let portion = FoodDatabase.parsePortion(from: food.portion)
        if portion.unit.lowercased() == "ml" {
            nutrition.waterMl = portion.amount
        }
        return IntakeQuickAction(
            id: "mccafe-\(food.id)",
            title: food.name,
            amount: nutrition.caffeineMg,
            nutrition: nutrition
        )
    }

    private enum CupSize { case small, medium, large, unspecified }

    private static func cupSize(of name: String) -> CupSize {
        if name.contains("（小）") { return .small }
        if name.contains("（中）") { return .medium }
        if name.contains("（大）") { return .large }
        return .unspecified
    }

    private static func containsCoffee(_ name: String) -> Bool {
        ["美式", "奶铁", "拿铁", "玛奇朵", "卡布奇诺", "摩卡", "浓缩"].contains { name.contains($0) }
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
            .searchable(text: $query, prompt: "搜索麦咖啡产品")
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
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
