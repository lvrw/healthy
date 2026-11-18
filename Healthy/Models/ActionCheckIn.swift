import Foundation
import SwiftData

@Model
final class ActionCheckIn {
    var dayKey: String
    var kindRaw: String
    var amount: Double
    var note: String?
    var createdAt: Date
    /// 写回 HealthKit 时使用的稳定同步 ID；旧记录为空，首次对账时补齐后持久化。
    var syncID: String?
    /// 饮品快捷项附带的碳水 / 蛋白质 / 脂肪（JSON 编码的 IntakeNutrition）。
    /// 只有咖啡因饮品打卡才有值，写回健康 App 时生成额外的营养样本。
    var nutritionJSON: String?
    /// 食物识别打卡的识别来源：ai / local；仅作记录与展示，不参与计算。
    var recognitionSource: String?
    /// 餐次（MealSlot.rawValue）。仅 meal 打卡有值；旧记录为 nil，展示时按用餐时刻推断。
    var mealSlotRaw: String?
    /// 保存时算好的单餐健康评分（0–100）；旧记录 / 非 meal 打卡为 nil。
    var mealScore: Double?
    /// 这一餐的逐样食物明细（`[MealItem]` 的 JSON 编码）。
    /// 有值时记录编辑页按「每样食物」逐项编辑，改数量会等比缩放该样营养；
    /// 旧记录为 nil，仍按聚合营养编辑，不做改造。
    var mealItemsJSON: String?

    init(
        dayKey: String,
        kindRaw: String,
        amount: Double,
        note: String? = nil,
        syncID: String? = nil,
        /// 打卡页允许选择当天任意时刻（顶部时间选择器），默认沿用当前时间。
        createdAt: Date = .now,
        nutritionJSON: String? = nil,
        recognitionSource: String? = nil,
        mealSlotRaw: String? = nil,
        mealScore: Double? = nil,
        mealItemsJSON: String? = nil
    ) {
        self.dayKey = dayKey
        self.kindRaw = kindRaw
        self.amount = amount
        self.note = note
        self.createdAt = createdAt
        self.syncID = syncID ?? UUID().uuidString
        self.nutritionJSON = nutritionJSON
        self.recognitionSource = recognitionSource
        self.mealSlotRaw = mealSlotRaw
        self.mealScore = mealScore
        self.mealItemsJSON = mealItemsJSON
    }

    /// 该条饮食记录的餐次：优先用保存时的选择，旧记录按 createdAt 推断。
    var mealSlot: MealSlot? {
        guard kindRaw == "meal" else { return nil }
        if let raw = mealSlotRaw, let slot = MealSlot(rawValue: raw) { return slot }
        return MealSlot.infer(from: createdAt)
    }

    /// 该条饮食记录的营养；无 JSON 时返回零值。
    var nutrition: IntakeNutrition {
        nutritionJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(IntakeNutrition.self, from: $0) }
            ?? .zero
    }

    /// 这一餐的逐样食物明细；旧记录（无分项数据）返回空数组。
    /// 解析失败也返回空数组，让编辑页自动退回聚合营养编辑。
    var mealItems: [MealItem] {
        guard let json = mealItemsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MealItem].self, from: data)) ?? []
    }

    /// 写入逐样食物明细（nil / 空数组表示清空分项数据）。
    func setMealItems(_ items: [MealItem]) {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(items) else {
            mealItemsJSON = nil
            return
        }
        mealItemsJSON = String(data: data, encoding: .utf8)
    }

    /// 取得可稳定复用的同步 ID；旧数据为空时生成并写回属性，由调用方负责保存。
    func ensureSyncID() -> String {
        if let syncID, !syncID.isEmpty { return syncID }
        let generated = UUID().uuidString
        self.syncID = generated
        return generated
    }

    /// 饮品打卡（咖啡因）联动的「含水量」喝水记录，其 syncID 由咖啡因打卡的 syncID 派生，
    /// 删除咖啡因记录时可据此一并删除关联喝水记录，无需新增模型字段。
    static func linkedWaterSyncID(for caffeineSyncID: String) -> String {
        "linked.\(caffeineSyncID)"
    }
}

// configured by qoder
