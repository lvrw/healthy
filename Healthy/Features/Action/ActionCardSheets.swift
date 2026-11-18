import SwiftData
import SwiftUI

/// 行动页卡片内的记录 / 配置入口对应的 sheet 路由。
/// 每张卡片自己决定有哪些入口，这里只负责「点了之后打开哪一页」。
enum ActionCardSheet: String, CaseIterable, Identifiable, Hashable {
    case waterRecords
    case waterSettings
    case caffeineRecords
    case caffeineSettings
    case dietRecords
    case dietSettings
    case stepsSettings

    var id: String { rawValue }

    /// 卡片底部小按钮的文案；放在这里保证入口与路由一一对应。
    var title: String {
        switch self {
        case .waterRecords, .caffeineRecords, .dietRecords: return "记录"
        default: return "设置"
        }
    }

    /// 卡片底部按钮的完整文案：饮水卡同时承载喝水与咖啡因两类入口，
    /// 只用「记录 / 设置」会分不清，这里一律带上对象名。
    var label: String {
        switch self {
        case .waterRecords: return "喝水记录"
        case .waterSettings: return "喝水配置"
        case .caffeineRecords: return "咖啡因记录"
        case .caffeineSettings: return "咖啡因配置"
        case .dietRecords: return "饮食记录"
        case .dietSettings: return "饮食设置"
        case .stepsSettings: return "目标设置"
        }
    }

    var icon: String {
        switch self {
        case .waterRecords, .caffeineRecords, .dietRecords: return "list.bullet"
        default: return "gearshape"
        }
    }

    /// 设置类入口：收进详情页导航栏右上角的齿轮，不再占一行胶囊按钮。
    var isSettings: Bool {
        switch self {
        case .waterSettings, .caffeineSettings, .dietSettings, .stepsSettings: return true
        case .waterRecords, .caffeineRecords, .dietRecords: return false
        }
    }
}

extension ActionCardSheet {
    /// 详情页入口映射：记录 / 设置不再贴在行动页外层卡片上，而是收进「点进去之后」的详情页。
    /// 每张卡片只带自己的入口，不跨卡片重复。
    /// - Sleep / 锻炼 / 晒太阳 / 呼吸正念 / 环境音量这类纯 HealthKit 自动行动没有入口。
    static func entries(for action: InsightAction) -> [ActionCardSheet] {
        switch action {
        case .water1500: return [.waterRecords, .waterSettings]
        case .caffeineModerate: return [.caffeineRecords, .caffeineSettings]
        case .steps8000: return [.stepsSettings]
        default: return []
        }
    }
}

/// 卡片详情页顶部的「记录 / 配置」入口条。
/// 行动页外层卡片保持只显示指标与进度；入口放在详情页顶部，
/// 详情页原有的内容卡片不做任何改动，这里只是一行额外的胶囊按钮。
struct ActionEntryBar: View {
    /// 要展示的入口；空数组时整条不渲染（调用方仍需自行判断，避免多一层空容器）。
    let entries: [ActionCardSheet]
    /// 记录类入口打开哪一天，默认今天。
    var date: Date = DayKey.startOfDay(.now)
    /// 饮食设置页「每日摄入阈值」的估算依据；nil 时设置页回退默认 2000 kcal。
    var estimatedMaintenanceKcal: Double? = nil

    /// 当前打开的 sheet；nil 表示未打开。
    @State private var sheet: ActionCardSheet?

    /// 一行最多两块：入口文案都带对象名，三块挤在一行会被截断。
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: min(2, max(1, entries.count)))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(entries) { entry in
                Button {
                    sheet = entry
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: entry.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(entry.label)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(AppPalette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(AppPalette.line2, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $sheet) { sheet in
            ActionCardSheetPage(
                sheet: sheet,
                date: date,
                estimatedMaintenanceKcal: estimatedMaintenanceKcal
            )
        }
    }
}

/// 入口对应的具体页面：详情页顶部的入口条与导航栏齿轮共用同一套映射。
struct ActionCardSheetPage: View {
    let sheet: ActionCardSheet
    var date: Date = DayKey.startOfDay(.now)
    var estimatedMaintenanceKcal: Double? = nil

    var body: some View {
        switch sheet {
        case .waterRecords:
            IntakeRecordsSheet(kind: .water, date: date)
        case .caffeineRecords:
            IntakeRecordsSheet(kind: .caffeine, date: date)
        case .waterSettings:
            IntakeGoalSettingsView(kind: .water)
        case .caffeineSettings:
            IntakeGoalSettingsView(kind: .caffeine)
        case .dietRecords:
            FoodRecognitionView.MealRecordsListView()
        case .dietSettings:
            ActionGoalSettingsView(focus: .diet, estimatedMaintenanceKcal: estimatedMaintenanceKcal)
        case .stepsSettings:
            ActionGoalSettingsView(focus: .steps, estimatedMaintenanceKcal: estimatedMaintenanceKcal)
        }
    }
}

/// 详情页日期切换条：一周 7 天 + 左右切换整周，最右侧不会超过今天。
struct ActionDayStrip: View {
    @Binding var selectedDate: Date
    var tint: Color = AppPalette.greenDeep

    private var calendar: Calendar { .current }
    private var today: Date { DayKey.startOfDay(.now) }

    /// 选中日期所在周的周一 → 周日。
    private var weekDates: [Date] {
        let weekday = calendar.component(.weekday, from: selectedDate)
        let offsetToMonday = (weekday + 5) % 7
        let monday = DayKey.addingDays(-offsetToMonday, to: DayKey.startOfDay(selectedDate))
        return (0..<7).map { DayKey.addingDays($0, to: monday) }
    }

    /// 当前周是否已经包含今天：包含时不能再往后翻。
    private var isCurrentWeek: Bool {
        weekDates.contains { $0 >= today }
    }

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        HStack(spacing: 4) {
            arrow("chevron.left", disabled: false) {
                selectedDate = DayKey.addingDays(-7, to: selectedDate)
            }
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                dayButton(date, weekday: weekdays[index])
                    .frame(maxWidth: .infinity)
            }
            arrow("chevron.right", disabled: isCurrentWeek) {
                selectedDate = DayKey.addingDays(7, to: selectedDate)
            }
        }
        .padding(.vertical, 2)
    }

    private func dayButton(_ date: Date, weekday: String) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        return Button {
            selectedDate = DayKey.startOfDay(date)
        } label: {
            VStack(spacing: 3) {
                Text(isToday ? "今" : weekday)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? tint : Color.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? tint : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                isSelected ? tint.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.month().day()))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func arrow(_ systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.3) : Color.secondary)
                .frame(width: 26, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// 行动页「喝水 / 咖啡因记录」直达页：健康 App 当日全量样本 + 本 App 打卡，按同步 ID 去重，
/// 与打卡页底部的「当日记录」共用同一套取值与删除口径，但不需要先进入打卡页。
struct IntakeRecordsSheet: View {
    let kind: ActionTileKind
    let date: Date

    @Environment(\.modelContext) private var context
    @Query private var allChecks: [ActionCheckIn]

    /// 健康 App 当天该类型的全部逐条样本。
    @State private var remoteEntries: [IntakeEntry] = []
    @State private var healthKitNotice: String?

    private var key: String { DayKey.key(for: date) }

    /// 本 App 本地打卡；老数据缺 syncID 时由 load() 先补齐。
    private var localEntries: [IntakeEntry] {
        allChecks
            .filter { $0.dayKey == key && $0.kindRaw == kind.rawValue }
            .compactMap { check in
                guard let syncID = check.syncID, !syncID.isEmpty else { return nil }
                return IntakeEntry(
                    id: "local-\(syncID)",
                    date: check.createdAt,
                    amount: check.amount,
                    origin: .local,
                    syncID: syncID
                )
            }
    }

    private var entries: [IntakeEntry] {
        IntakeEntryMerger.merge(remote: remoteEntries, local: localEntries)
    }

    var body: some View {
        IntakeRecordListView(
            kind: kind,
            date: date,
            entries: entries,
            notice: healthKitNotice
        ) { entry in
            delete(entry)
        }
        .task { await load() }
    }

    /// 与 ActionCheckInSheet 一致：先补齐老打卡的同步 ID，再读健康 App 当日样本。
    @MainActor
    private func load() async {
        _ = try? WaterMerge.localRecords(in: context)
        let service = HealthKitService()
        do {
            remoteEntries = try await service.fetchIntakeEntries(kind: kind.rawValue, day: date)
            healthKitNotice = nil
        } catch {
            remoteEntries = []
            healthKitNotice = "健康 App 记录暂时不可用：\(error.localizedDescription)"
        }
    }

    /// 删除本 App 打卡（含咖啡因饮品联动生成的喝水记录），并同步移除健康 App 回写样本。
    private func delete(_ entry: IntakeEntry) {
        guard let syncID = entry.syncID,
              let syncKind = SyncableCheckInKind(rawValue: kind.rawValue) else { return }
        let linkedWaterSyncID = syncKind == .caffeine
            ? ActionCheckIn.linkedWaterSyncID(for: syncID)
            : nil
        let local = allChecks.first(where: {
            $0.dayKey == key && $0.kindRaw == kind.rawValue && $0.syncID == syncID
        })
        let waterLocal = linkedWaterSyncID.flatMap { wid in
            allChecks.first(where: {
                $0.dayKey == key && $0.kindRaw == SyncableCheckInKind.water.rawValue && $0.syncID == wid
            })
        }
        if let local { context.delete(local); try? context.save() }
        if let waterLocal { context.delete(waterLocal); try? context.save() }
        Task {
            await WaterCheckInSync.remove(syncID: syncID, kind: syncKind.rawValue, context: context)
            if let linkedWaterSyncID {
                await WaterCheckInSync.remove(
                    syncID: linkedWaterSyncID,
                    kind: SyncableCheckInKind.water.rawValue,
                    context: context
                )
            }
            await load()
        }
    }
}

/// 行动页「步数设置 / 饮食设置」共用页。
/// 步数只配每日目标；饮食配减肥目标并据此推导每日卡路里摄入阈值，
/// 同时把既有饮食相关配置（AI 识别、智能评分、本地营养库）收拢到同一页。
struct ActionGoalSettingsView: View {
    enum Focus {
        case steps
        case diet
    }

    let focus: Focus
    /// 近 7 个完整日「静息能量 + 活动能量」均值；nil 表示健康 App 没有可用能量数据。
    let estimatedMaintenanceKcal: Double?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ActionGoal.stepsDefaultsKey) private var stepsTarget = ActionGoal.defaultStepsTarget
    @AppStorage(ActionGoal.weeklyWeightLossDefaultsKey) private var weeklyLoss = ActionGoal.defaultWeeklyWeightLossKg
    @State private var aiFoodEnabled = FoodRecognitionSettings.isAIEnabled
    @State private var aiSmartScoringEnabled = AISmartScoringSettings.isEnabled

    /// 自动估算的维持热量；健康 App 没数据时兜底默认 2000 kcal。
    private var maintenanceKcal: Double {
        estimatedMaintenanceKcal ?? ActionGoal.defaultMaintenanceKcal
    }

    private var thresholdKcal: Double {
        ActionGoal.calorieThreshold(maintenanceKcal: maintenanceKcal, weeklyLossKg: weeklyLoss)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch focus {
                case .steps:
                    stepsSection
                case .diet:
                    weightLossSection
                    calorieSection
                    recognitionSection
                    foodDataSection
                }
            }
            .navigationTitle(focus == .steps ? "步数设置" : "饮食设置")
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

    /// 步数目标：数字输入 + 步进，写入 UserDefaults 后行动页卡片即时刷新。
    private var stepsSection: some View {
        Section {
            Stepper(value: $stepsTarget, in: ActionGoal.stepsRange, step: 500) {
                Text("\(Int(stepsTarget.rounded())) 步 / 天")
                    .font(.body.monospacedDigit())
            }
            TextField("自定义步数目标", value: $stepsTarget, format: .number)
                .keyboardType(.numberPad)
        } header: {
            Text("每日步数目标")
        } footer: {
            Text("默认 8000 步，可在 1000–50000 步之间调整。目标只影响行动页展示与进度条，不改变评分口径。")
        }
    }

    /// 减肥目标：每周减重速度决定每日热量缺口。
    private var weightLossSection: some View {
        Section {
            Picker("每周减重", selection: $weeklyLoss) {
                ForEach(ActionGoal.weeklyWeightLossOptions, id: \.self) { value in
                    Text(weightLossLabel(value)).tag(value)
                }
            }
        } header: {
            Text("减肥目标")
        } footer: {
            Text("按 1 kg 脂肪约 7700 kcal 估算每日热量缺口；维持体重时阈值等于维持热量。经验值，非医学建议。")
        }
    }

    /// 卡路里阈值：维持热量自动估算，改完即时算给行动页用。
    private var calorieSection: some View {
        Section {
            HStack {
                Text("每日摄入阈值")
                Spacer()
                Text("\(Int(thresholdKcal)) kcal")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppPalette.greenDeep)
            }
            HStack {
                Text("估算维持热量")
                Spacer()
                Text(estimatedMaintenanceKcal.map { "\(Int($0.rounded())) kcal" } ?? "无数据")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("每日卡路里摄入阈值")
        } footer: {
            Text("阈值 = 维持热量 − 每周减重 × 7700 ÷ 7，最低 1200 kcal。维持热量取近 7 个完整日健康 App「静息能量 + 活动能量」均值；无数据时默认 2000 kcal。")
        }
    }

    /// 食物识别与智能评分开关，与设置页 AISettingsView 使用同一份偏好。
    private var recognitionSection: some View {
        Section {
            Toggle("食物识别", isOn: $aiFoodEnabled)
                .onChange(of: aiFoodEnabled) { _, newValue in
                    FoodRecognitionSettings.isAIEnabled = newValue
                }
            Toggle("智能评分", isOn: $aiSmartScoringEnabled)
                .onChange(of: aiSmartScoringEnabled) { _, newValue in
                    AISmartScoringSettings.isEnabled = newValue
                }
        } header: {
            Text("识别与评分")
        } footer: {
            Text("关闭食物识别后改用本地营养库匹配；关闭智能评分后简报只用本机确定性评分。")
        }
    }

    /// 营养库与 AI 服务配置直接复用现有页面，不另建一套设置。
    private var foodDataSection: some View {
        Section("食物数据") {
            NavigationLink {
                FoodLibraryView()
            } label: {
                Label("本地营养库", systemImage: "books.vertical")
            }
            NavigationLink {
                AISettingsView()
            } label: {
                Label("AI 服务", systemImage: "sparkles")
            }
        }
    }

    private func weightLossLabel(_ value: Double) -> String {
        if value == 0 { return "维持体重" }
        return String(format: "%.2g kg / 周", value)
    }
}
