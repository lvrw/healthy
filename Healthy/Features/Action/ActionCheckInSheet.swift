import SwiftData
import SwiftUI
import UIKit

/// 喝水 / 咖啡因打卡页。
/// 版式按原型：喝水用玻璃杯水位、咖啡因用咖啡豆填充 + 大数字 + 目标差额 +
/// 可自定义快捷项 + 底部当日记录入口。
/// 当日总量与记录明细都取自「健康 App 全量样本 + 本 App 打卡」的合并结果，
/// 不再只展示本 App 自己写入的 SwiftData 记录。
struct ActionCheckInSheet: View {
    let kind: ActionTileKind
    /// 当前查看 / 补记的日期；顶部日期可点，改天只影响这一屏，不影响其他页面。
    @State private var selectedDate: Date

    init(kind: ActionTileKind, date: Date) {
        self.kind = kind
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: date))
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allChecks: [ActionCheckIn]

    /// 健康 App 当天该类型的全部逐条样本（含健康 App 手动录入、第三方、本 App 回写）。
    @State private var remoteEntries: [IntakeEntry] = []
    @State private var healthKitNotice: String?
    /// 新记录记在当天的什么时刻。
    @State private var entryTime: Date = .now
    @State private var showsTimePicker = false
    @State private var showsRecords = false
    @State private var showsGoalSettings = false
    @State private var showsManualInput = false
    @State private var showsDatePicker = false
    /// 日期选择器的临时值：点「完成」才应用，取消则保持原日期。
    @State private var draftDate: Date = .now
    @State private var manualAmountText = ""
    /// 目标 / 上限直接绑定 UserDefaults，与行动页卡片、配置页共用同一组键：
    /// 配置页一保存，这里与行动页同时刷新，不会出现两处数值不一致。
    @AppStorage(IntakeGoal.waterDefaultsKey) private var waterTargetMl = IntakeGoal.defaultWaterTargetMl
    @AppStorage(IntakeGoal.caffeineDefaultsKey) private var caffeineLimitMg = IntakeGoal.defaultCaffeineLimitMg
    /// 齿轮里自定义的快捷项；保存后由配置 sheet 的 onDismiss 重新加载。
    @State private var quickActions: [IntakeQuickAction] = []
    /// 配置是否已从 UserDefaults 读过：读之前用默认预设，避免 body 里反复 decode。
    @State private var actionsLoaded = false
    /// 待选容量的咖啡因饮品：有基准容量（水 ml）的项点击后先弹容量选择，再按比例打卡。
    @State private var volumeAction: IntakeQuickAction?
    /// 瑞幸 / 麦咖啡产品选择弹窗：状态必须挂在打卡页本身，不能挂在 LazyVGrid 的按钮里。
    /// 弹窗内点搜索框会弹键盘、触发网格重建；若按钮被重建，它自身的 @State 归 false 会直接关掉弹窗。
    @State private var showsLuckinPicker = false
    @State private var showsMccafePicker = false

    private var key: String { DayKey.key(for: selectedDate) }
    private var isWater: Bool { kind == .water }
    private var unit: String { isWater ? "ml" : "mg" }
    private var tint: Color {
        isWater
            ? Color(red: 0.282, green: 0.663, blue: 0.973)
            : Color(red: 0.663, green: 0.455, blue: 0.310)
    }
    /// 首帧还没加载配置时直接用默认预设，避免按钮区空白；读过后只读缓存，
    /// 不在 body 里反复走 UserDefaults decode（这是打卡页掉帧的主要来源之一）。
    private var displayedActions: [IntakeQuickAction] {
        actionsLoaded ? quickActions : IntakeQuickActionStore.defaults(for: kind.rawValue)
    }
    /// 当前目标：按各自取值范围钳制，避免配置里出现异常值。
    private var goal: Double {
        isWater
            ? IntakeGoal.clamp(waterTargetMl, in: IntakeGoal.waterRange)
            : IntakeGoal.clamp(caffeineLimitMg, in: IntakeGoal.caffeineRange)
    }

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

    /// 合并后的当日记录：健康 App 外部样本 + 本 App 打卡（同一同步 ID 只出现一次）。
    private var entries: [IntakeEntry] {
        IntakeEntryMerger.merge(remote: remoteEntries, local: localEntries)
    }

    private var total: Double { IntakeEntryMerger.total(entries) }
    private var progress: Double { goal > 0 ? min(max(total / goal, 0), 1) : 0 }

    var body: some View {
        // 合并 / 求和只算一次再传给各子视图：原先 amountLabel、goalLabel、进度图、
        // 记录入口各自读这些计算属性，body 每次求值都要重复遍历全部 SwiftData 记录。
        let mergedEntries = entries
        let shownTotal = IntakeEntryMerger.total(mergedEntries)
        let shownProgress = goal > 0 ? min(max(shownTotal / goal, 0), 1) : 0

        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    timeSection
                    Group {
                        if isWater {
                            IntakeGlassView(progress: shownProgress, tint: tint)
                        } else {
                            CoffeeBeanFillView(progress: shownProgress, tint: tint)
                        }
                    }
                    .frame(width: 246, height: 292)
                    .padding(.top, 22)
                    amountLabel(total: shownTotal)
                        .padding(.top, 24)
                    goalLabel(total: shownTotal)
                        .padding(.top, 18)
                    presetGrid
                        .padding(.top, 36)
                        .padding(.horizontal, 30)
                    manualButton
                        .padding(.top, 12)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            }
            // 底部记录入口固定贴底，不随内容滚动。
            recordsButton(count: mergedEntries.count)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            quickActions = IntakeQuickActionStore.load(kind: kind.rawValue)
            actionsLoaded = true
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onChange(of: selectedDate) { _, _ in
            // 换日期后重新拉取健康 App 当天的样本，杯子与记录列表一起刷新。
            Task { await load() }
        }
        .sheet(isPresented: $showsDatePicker) {
            datePickerSheet
        }
        // 产品选择弹窗挂在本页（稳定的视图层级），不挂在会被键盘重建的网格按钮上。
        .sheet(isPresented: $showsLuckinPicker) {
            LuckinDrinkPickerView { drink in
                add(LuckinCatalog.quickAction(for: drink))
                triggerHaptic()
            }
        }
        .sheet(isPresented: $showsMccafePicker) {
            MccafeDrinkPickerView { food in
                add(MccafeCaffeine.quickAction(for: food))
                triggerHaptic()
            }
        }
        .sheet(isPresented: $showsRecords) {
            IntakeRecordListView(
                kind: kind,
                date: selectedDate,
                entries: entries,
                notice: healthKitNotice
            ) { entry in
                delete(entry)
            }
        }
        .sheet(
            isPresented: $showsGoalSettings,
            onDismiss: {
                // 目标值由 @AppStorage 自动同步，这里只重载自定义快捷项。
                quickActions = IntakeQuickActionStore.load(kind: kind.rawValue)
            }
        ) {
            IntakeGoalSettingsView(kind: kind)
        }
        .sheet(item: $volumeAction) { action in
            DrinkVolumeSheet(action: action) { scaled in
                add(scaled)
                triggerHaptic()
            }
        }
        .alert("手动输入\(kind.title)", isPresented: $showsManualInput) {
            TextField("数量（\(unit)）", text: $manualAmountText)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) { manualAmountText = "" }
            Button("记录") { addManual() }
        } message: {
            Text("记入 \(dateTitle) \(entryTime.formatted(date: .omitted, time: .shortened))，并同步写回健康 App。")
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                circleButton("xmark", weight: .semibold) { dismiss() }
                Spacer()
                circleButton("gearshape", weight: .regular) { showsGoalSettings = true }
            }
            Button {
                draftDate = selectedDate
                showsDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(dateTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .overlay(
                    Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    /// 选择日期：只允许选今天及更早，方便补记历史饮水 / 咖啡因。
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "日期",
                selection: $draftDate,
                in: ...Calendar.current.startOfDay(for: .now),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showsDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        selectedDate = Calendar.current.startOfDay(for: draftDate)
                        showsDatePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func circleButton(
        _ name: String,
        weight: Font.Weight,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16, weight: weight))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(
                    Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var dateTitle: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    // MARK: - 时间 / 杯子 / 数值

    /// 时间选择内联展开，不再弹半透明 sheet：sheet 会把下面的蓝色按钮透成一片光斑。
    private var timeSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) {
                    showsTimePicker.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(entryTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                    Image(systemName: showsTimePicker
                          ? "chevron.up.circle.fill"
                          : "chevron.down.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(AppPalette.ink)
            }
            .buttonStyle(.plain)

            if showsTimePicker {
                // 不要给 wheel 时间选择器加过小的固定高度：UIKit 会忽略该高度改用自身
                // 最小可渲染高度，导致滚轮溢出、压住下方的「使用当前时间」按钮（叠字）。
                // 这里去掉 frame(height:)，让滚轮使用原生高度，按钮自然落在滚轮下方。
                DatePicker("记录时间", selection: $entryTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal, 56)
                    .padding(.top, 6)
                Button("使用当前时间") { entryTime = .now }
                    .font(.footnote)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
        }
        .padding(.top, 18)
    }

    private func amountLabel(total shownTotal: Double) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(Int(shownTotal.rounded()))")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppPalette.ink)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.gray)
        }
    }

    private func goalLabel(total shownTotal: Double) -> some View {
        let remaining = goal - shownTotal
        let prefix = isWater ? "目标：" : "上限："
        let suffix: String
        let tail: String
        if remaining > 0 {
            suffix = isWater ? "，还差 " : "，还可摄入 "
            tail = "\(Int(remaining.rounded()))\(unit)"
        } else if remaining == 0 {
            suffix = isWater ? "，已达成" : "，已达上限"
            tail = ""
        } else {
            suffix = isWater ? "，已达成" : "，已超出 "
            tail = isWater ? "" : "\(Int((-remaining).rounded()))\(unit)"
        }
        return (Text(prefix).foregroundStyle(.secondary)
            + Text("\(Int(goal.rounded()))\(unit)").fontWeight(.bold)
            + Text(suffix).foregroundStyle(.secondary)
            + Text(tail).fontWeight(.bold))
            .font(.system(size: 17))
            .foregroundStyle(AppPalette.ink)
    }

    // MARK: - 快捷加量

    private var presetGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 84), spacing: 12), count: 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(displayedActions) { action in
                Button {
                    if isWater || action.baseVolumeMl <= 0 {
                        // 喝水 / 未配置基准容量的自定义咖啡因项：维持原「按固定量直接打卡」。
                        add(action)
                        triggerHaptic()
                    } else {
                        // 茶 / 美式 / 拿铁 / 可乐这类配了容量的饮品：先选本次喝了多少 ml。
                        volumeAction = action
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(action.title)
                            .font(.system(size: isWater ? 16 : 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !isWater {
                            Text(action.amount > 0 ? "\(Int(action.amount.rounded())) mg" : "无咖啡因")
                                .font(.system(size: 10, weight: .medium))
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            // 固定的瑞幸 / 麦咖啡产品入口：展开按分类分组的选择列表，不占用可编辑快捷项名额。
            if !isWater {
                LuckinQuickActionButton(tint: tint, isPresented: $showsLuckinPicker)
                MccafeQuickActionButton(tint: tint, isPresented: $showsMccafePicker)
            }
        }
    }

    private var manualButton: some View {
        Button {
            manualAmountText = ""
            showsManualInput = true
        } label: {
            presetLabel("+ 手动输入", width: 146)
        }
        .buttonStyle(.plain)
    }

    private func presetLabel(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: width == nil ? .infinity : width, minHeight: 50)
            .background(tint, in: Capsule())
    }

    private func recordsButton(count: Int) -> some View {
        Button {
            showsRecords = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isWater ? "drop.fill" : "mug.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                Text("当日记录")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(AppPalette.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    /// 喝水 / 咖啡因快捷加量按钮的触觉反馈：轻量「轻触」震动，
    /// 仅在快捷加量时触发（手动输入走弹窗确认，不在此处震动）。
    @MainActor
    private func triggerHaptic() {
        if reduceMotion { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    @MainActor
    private func load() async {
        let trace = PerformanceTrace.shared.begin(
            "打卡页 · 读取\(kind.title)当天记录", category: .api,
            detail: "day=\(DayKey.key(for: selectedDate))"
        )
        var succeeded = true
        defer { PerformanceTrace.shared.end(trace, success: succeeded) }
        // 老版本留下的打卡没有 syncID，补齐后才能与健康 App 回写样本对账去重。
        _ = try? WaterMerge.localRecords(in: context)
        let service = HealthKitService()
        do {
            remoteEntries = try await service.fetchIntakeEntries(kind: kind.rawValue, day: selectedDate)
            healthKitNotice = nil
        } catch {
            succeeded = false
            remoteEntries = []
            healthKitNotice = "健康 App 记录暂时不可用：\(error.localizedDescription)"
        }
    }

    private func addManual() {
        let parsed = Double(manualAmountText.replacingOccurrences(of: ",", with: "."))
        manualAmountText = ""
        if let value = parsed, value > 0 { add(value) }
    }

    /// 饮品快捷项：除了咖啡因，还要把配置的碳蛋脂一起写回健康 App。
    private func add(_ action: IntakeQuickAction) {
        let nutrition = isWater ? nil : action.nutrition
        let nutritionJSON = nutrition.flatMap { value -> String? in
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        add(
            action.amount,
            nutrition: nutrition,
            nutritionJSON: nutritionJSON,
            linkedWaterMl: nutrition?.waterMl ?? 0,
            drinkTitle: action.title
        )
    }

    private func add(
        _ value: Double,
        nutrition: IntakeNutrition? = nil,
        nutritionJSON: String? = nil,
        linkedWaterMl: Double = 0,
        drinkTitle: String = ""
    ) {
        // 咖啡因页允许 0mg：记录无咖啡因饮品（牛奶 / 果汁等）的产品营养与含水量；
        // 喝水页仍必须 >0，纯 0ml 的水没有记录意义。
        guard value.isFinite, value > 0 || (kind == .caffeine && value == 0) else { return }
        let createdAt = combinedTime()
        let entry = ActionCheckIn(
            dayKey: key,
            kindRaw: kind.rawValue,
            amount: value,
            note: drinkTitle.isEmpty ? nil : drinkTitle,
            createdAt: createdAt,
            nutritionJSON: nutritionJSON
        )
        context.insert(entry)
        try? context.save()
        guard let syncID = entry.syncID,
              let syncKind = SyncableCheckInKind(rawValue: kind.rawValue) else { return }
        let record = WaterSyncRecord(
            syncID: syncID,
            amountMl: value,
            date: createdAt,
            kind: syncKind.rawValue,
            nutrition: nutrition
        )
        // 咖啡因饮品配置了含水量时，联动生成一条喝水记录，喝水量总额随之增加，
        // 并与本咖啡因记录共用派生 syncID，删除时一并清理、写回健康 App。
        var linkedWaterRecord: WaterSyncRecord?
        if !isWater, linkedWaterMl > 0 {
            let waterID = ActionCheckIn.linkedWaterSyncID(for: syncID)
            let waterEntry = ActionCheckIn(
                dayKey: key,
                kindRaw: SyncableCheckInKind.water.rawValue,
                amount: linkedWaterMl,
                note: drinkTitle.isEmpty ? "饮品含水量" : drinkTitle,
                syncID: waterID,
                createdAt: createdAt
            )
            context.insert(waterEntry)
            try? context.save()
            linkedWaterRecord = WaterSyncRecord(
                syncID: waterID,
                amountMl: linkedWaterMl,
                date: createdAt,
                kind: SyncableCheckInKind.water.rawValue
            )
        }
        Task {
            let trace = PerformanceTrace.shared.begin(
                "打卡页 · 写入\(kind.title)到健康App", category: .api
            )
            await WaterCheckInSync.push(record: record, context: context)
            if let linkedWaterRecord {
                await WaterCheckInSync.push(record: linkedWaterRecord, context: context)
            }
            PerformanceTrace.shared.end(trace)
            await load()
        }
    }

    private func delete(_ entry: IntakeEntry) {
        guard let syncID = entry.syncID,
              let syncKind = SyncableCheckInKind(rawValue: kind.rawValue) else { return }
        // 咖啡因打卡联动删除其含水量对应的喝水记录（syncID 由咖啡因 syncID 派生）。
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
            let trace = PerformanceTrace.shared.begin(
                "打卡页 · 删除\(kind.title)记录", category: .api
            )
            await WaterCheckInSync.remove(syncID: syncID, kind: syncKind.rawValue, context: context)
            if let linkedWaterSyncID {
                await WaterCheckInSync.remove(
                    syncID: linkedWaterSyncID,
                    kind: SyncableCheckInKind.water.rawValue,
                    context: context
                )
            }
            PerformanceTrace.shared.end(trace)
            await load()
        }
    }

    /// 所看日期 + 顶部选中的时刻；查看历史日期时不会把记录错记到今天。
    private func combinedTime() -> Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let time = calendar.dateComponents([.hour, .minute], from: entryTime)
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = time.hour
        parts.minute = time.minute
        parts.second = 0
        return calendar.date(from: parts) ?? .now
    }
}

/// 咖啡因饮品的容量选择：默认项（茶 / 美式 / 拿铁 / 可乐）配置了基准容量，
/// 点击后在这里选本次实际喝了多少 ml，确认时按 `实际 / 基准` 等比换算咖啡因与营养。
struct DrinkVolumeSheet: View {
    let action: IntakeQuickAction
    let onConfirm: (IntakeQuickAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditing: Bool
    @State private var volumeText: String

    /// 与打卡页咖啡豆同一棕色，容量卡与按钮共用，避免各控件颜色不一。
    private let coffee = Color(red: 0.663, green: 0.455, blue: 0.310)

    /// 常用容量档位；基准容量不在档位里时也补进去，方便一键回到「一杯」。
    private var presets: [Double] {
        var values: [Double] = [150, 200, 250, 300, 350, 450, 500, 600]
        let base = action.baseVolumeMl
        if base > 0, !values.contains(where: { $0 == base }) { values.append(base) }
        return values.sorted()
    }

    private var volume: Double? {
        let parsed = Double(volumeText.replacingOccurrences(of: ",", with: "."))
        guard let parsed, parsed.isFinite else { return nil }
        return IntakeQuickActionStore.drinkVolumeRange.contains(parsed) ? parsed : nil
    }

    private var scaled: IntakeQuickAction? {
        guard let volume else { return nil }
        return action.scaled(toVolumeMl: volume)
    }

    init(action: IntakeQuickAction, onConfirm: @escaping (IntakeQuickAction) -> Void) {
        self.action = action
        self.onConfirm = onConfirm
        _volumeText = State(initialValue: String(Int(action.baseVolumeMl.rounded())))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 饮品身份：标题 + 基准说明，去掉重复的大图标，让输入卡成为视觉中心。
                        VStack(spacing: 4) {
                            Text(action.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("一杯约 \(Int(action.baseVolumeMl.rounded())) ml · \(Int(action.amount.rounded())) mg 咖啡因")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)

                        // 容量卡：居中大数字 + 两侧圆形步进，下面一排可横滑档位。
                        VStack(spacing: 14) {
                            Text("这次喝了多少毫升？")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 16) {
                                stepButton(systemName: "minus", delta: -50,
                                           label: "减少 50 毫升")
                                HStack(alignment: .lastTextBaseline, spacing: 4) {
                                    TextField("", text: $volumeText)
                                        .textFieldStyle(.plain)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 50, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .frame(width: 130)
                                        .focused($isEditing)
                                        .submitLabel(.done)
                                        .onSubmit { isEditing = false }
                                    Text("ml")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                stepButton(systemName: "plus", delta: 50,
                                           label: "增加 50 毫升")
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(presets, id: \.self) { value in
                                        Button {
                                            setVolume(value)
                                            isEditing = false
                                        } label: {
                                            Text("\(Int(value)) ml")
                                                .font(.system(size: 13, weight: .semibold))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .foregroundStyle(volume == value ? .white : coffee)
                                                .background(
                                                    Capsule().fill(coffee.opacity(volume == value ? 1 : 0.10))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                        .padding(18)
                        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        // 换算预览：咖啡因为主值，水与热量作次要行。
                        if let scaled {
                            VStack(spacing: 0) {
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: "cup.and.saucer.fill")
                                        .font(.title3)
                                        .foregroundStyle(coffee)
                                    Text("本次咖啡因")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(scaled.amount.rounded()))")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(coffee)
                                    Text("mg")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Divider().padding(.vertical, 12)
                                previewRow("联动喝水", "\(Int((scaled.nutrition?.waterMl ?? 0).rounded())) ml")
                                if let kcal = scaled.nutrition?.energyKcal, kcal > 0 {
                                    previewRow("热量", "\(Int(kcal.rounded())) kcal")
                                }
                            }
                            .padding(18)
                            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        } else {
                            Text("请输入 \(Int(IntakeQuickActionStore.drinkVolumeRange.lowerBound))–\(Int(IntakeQuickActionStore.drinkVolumeRange.upperBound)) ml 之间的容量")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Text("咖啡因、营养成分与联动喝水量都按所选容量等比换算，记入打卡页选择的时间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // 记录按钮固定贴底，输入键盘弹出时随安全区上移，不被遮挡。
                Button {
                    guard let scaled else { return }
                    onConfirm(scaled)
                    dismiss()
                } label: {
                    Text("记录")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(coffee, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(scaled == nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("选择容量")
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

    /// 圆形 ± 步进按钮：按 50 ml 调整，结果钳制在允许范围内。
    private func stepButton(systemName: String, delta: Double, label: String) -> some View {
        Button {
            setVolume((volume ?? action.baseVolumeMl) + delta)
            isEditing = false
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(coffee)
                .frame(width: 40, height: 40)
                .background(coffee.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func setVolume(_ value: Double) {
        let range = IntakeQuickActionStore.drinkVolumeRange
        volumeText = String(Int(min(max(value, range.lowerBound), range.upperBound).rounded()))
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// 上宽下窄、顶部小圆角 / 底部大圆角的玻璃杯轮廓。
/// 侧边内收 13%、底部圆角 11%，避免小尺寸下看起来像普通方块。
struct IntakeGlassShape: Shape {
    /// 由 GeometryReader 显式传入的尺寸。SwiftUI 给 clipShape 的 Shape 传的 rect
    /// 不一定等于被裁剪视图的 bounds，固定 rect 可以保证杯身与水位共用同一坐标系。
    var fixedRect: CGRect? = nil

    func path(in rect: CGRect) -> Path {
        let bounds = fixedRect ?? rect
        let w = bounds.width
        let h = bounds.height
        let originX = bounds.minX
        let originY = bounds.minY
        let topCorner = min(w, h) * 0.045
        let bottomCorner = min(w, h) * 0.11
        let sideInset = w * 0.13
        var path = Path()
        path.move(to: CGPoint(x: topCorner, y: 0))
        path.addLine(to: CGPoint(x: w - topCorner, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w, y: topCorner),
            control: CGPoint(x: w, y: 0)
        )
        path.addLine(to: CGPoint(x: w - sideInset, y: h - bottomCorner))
        path.addQuadCurve(
            to: CGPoint(x: w - sideInset - bottomCorner, y: h),
            control: CGPoint(x: w - sideInset, y: h)
        )
        path.addLine(to: CGPoint(x: sideInset + bottomCorner, y: h))
        path.addQuadCurve(
            to: CGPoint(x: sideInset, y: h - bottomCorner),
            control: CGPoint(x: sideInset, y: h)
        )
        path.addLine(to: CGPoint(x: 0, y: topCorner))
        path.addQuadCurve(
            to: CGPoint(x: topCorner, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        path.closeSubpath()
        return path.applying(CGAffineTransform(translationX: originX, y: originY))
    }
}

/// 带波浪的液面，level 为 0–1 的完成度。
struct IntakeLiquidShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(level, 0), 1)
        guard clamped > 0 else { return Path() }
        let y = rect.height * (1 - clamped)
        let wave = min(rect.height * 0.035, 12)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y + wave * 0.35))
        path.addCurve(
            to: CGPoint(x: rect.width, y: y - wave * 0.35),
            control1: CGPoint(x: rect.width * 0.30, y: y - wave),
            control2: CGPoint(x: rect.width * 0.72, y: y + wave)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct IntakeGlassView: View {
    let progress: Double
    let tint: Color

    var body: some View {
        // 杯身与水位放在同一个 ZStack 里统一裁剪。杯形用 GeometryReader 量到的
        // 真实尺寸固定，避免 SwiftUI 传给 clipShape 的 rect 与被裁剪视图不一致，
        // 导致真机上水位被裁成直上直下的方块。
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                IntakeLiquidShape(level: progress)
                    .fill(tint)
                    .frame(width: bounds.width, height: bounds.height)
            }
            .frame(width: bounds.width, height: bounds.height)
            .clipShape(IntakeGlassShape(fixedRect: bounds))
        }
        .animation(.easeInOut(duration: 0.4), value: progress)
    }
}
