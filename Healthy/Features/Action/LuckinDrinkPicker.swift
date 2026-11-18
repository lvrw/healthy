import Foundation
import SwiftUI

/// 咖啡因打卡页里的固定「瑞幸咖啡」快捷按钮：点击展开产品选择列表，
/// 选中后按官网公示的咖啡因 mg 直接打卡。该入口不写入 UserDefaults，
/// 不占用「设置 → 快捷按键」里可编辑的 6 个名额。
struct LuckinQuickActionButton: View {
    let tint: Color
    let onSelect: (LuckinDrink) -> Void

    @State private var showsPicker = false

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "mug.fill")
                        .font(.system(size: 10))
                    Text("瑞幸咖啡")
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
            LuckinDrinkPickerView(onSelect: onSelect)
        }
    }
}

/// 瑞幸产品选择列表：按官网分类分组、支持搜索，列出官网全部在售产品
/// （未公示咖啡因的产品同样展示，选中后咖啡因按 0 记录）。
struct LuckinDrinkPickerView: View {
    let onSelect: (LuckinDrink) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var groups: [LuckinDrinkGroup] { LuckinCatalog.grouped(query: query) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("数据来自瑞幸咖啡官网产品公示（2026-11-18 复核，共 \(LuckinCatalog.drinks.count) 款），为推荐点单配置下的每杯值。标「≈」的为推算值（官网未公示，参考同系列公示产品或公开测评）；选中后咖啡因、热量 / 蛋白质与杯容量随本次打卡一并写入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    Section(group.category) {
                        ForEach(group.drinks) { drink in
                            Button {
                                onSelect(drink)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    FoodRemoteIcon(imageURL: drink.imageURL, fallbackSymbol: "cup.and.saucer.fill")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(drink.name)
                                            .font(.subheadline.weight(.medium))
                                        Text(Self.subtitle(for: drink))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Text(Self.caffeineLabel(for: drink))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(drink.caffeineMg > 0 ? Color(red: 0.663, green: 0.455, blue: 0.310) : Color.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜索瑞幸产品")
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("瑞幸咖啡")
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

    private static func mg(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// 行尾咖啡因标注：官网公示值显示 mg，推算值带 ≈ 前缀，不含咖啡因显示「无」。
    private static func caffeineLabel(for drink: LuckinDrink) -> String {
        if drink.caffeineMg <= 0 { return "无" }
        return drink.caffeineEstimated ? "≈\(mg(drink.caffeineMg)) mg" : "\(mg(drink.caffeineMg)) mg"
    }

    private static func subtitle(for drink: LuckinDrink) -> String {
        let kcal = drink.nutrition.energyKcal
        let energy = kcal > 0 ? "\(Int(kcal.rounded())) 千卡" : "热量未公示"
        return "\(energy) · \(Int(drink.waterMl)) ml"
    }
}
