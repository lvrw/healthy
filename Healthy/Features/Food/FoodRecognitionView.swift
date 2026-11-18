import SwiftUI
import SwiftData
import UIKit

/// 食物识别主界面：拍照 / 相册选图 + 文字描述，按设置走 AI 或本地营养库匹配，
/// 结果可逐项编辑营养与数量（数字 + 单位），保存后写入本 App 记录并回写健康 App。
struct FoodRecognitionView: View {
    /// 用餐时间，默认沿用行动页选中的日期（用户可在行动页改日期后进入）。
    let date: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var imageData: Data?
    @State private var description = ""
    @State private var showSourcePicker = false
    @State private var pickerSource: CameraImagePicker.Source = .photoLibrary
    @State private var showPicker = false
    @State private var isRecognizing = false
    @State private var recognized: RecognizedMeal?
    @State private var errorMessage: String?
    /// 保存校验收到的提示（如某样食物没填数量），就近显示在「记录饮食」按钮上方。
    @State private var saveMessage: String?
    /// 识别记录改为右上角按钮点击后弹出独立页面，避免主页面铺满历史记录显得杂乱。
    @State private var showRecords = false
    /// 识别结果区的锚点：识别开始后收起键盘并滚动到这里，让用户直接看到结果。
    @State private var scrollToResult = false

    /// 用餐时刻：默认「所选日期 + 当前时刻」，用户可改（含补录其他日期）。
    @State private var mealTime: Date
    /// 餐次：默认按用餐时刻自动推断，用户手动改过后不再随时间联动。
    @State private var selectedSlot: MealSlot
    @State private var slotIsAuto = true

    init(date: Date) {
        self.date = date
        let initial = FoodRecognitionView.combined(date: date, time: .now)
        _mealTime = State(initialValue: initial)
        _selectedSlot = State(initialValue: MealSlot.infer(from: initial))
    }

    /// 把「所选日期」与「某个时刻」合成为真实用餐时间（避免所有记录都落在 00:00）。
    static func combined(date: Date, time: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = 0
        return calendar.date(from: parts) ?? time
    }

    /// 进入页面时读取一次当前开关，文案随之切换（本地模式不再提「AI 识别」为主流程）。
    private var aiEnabled: Bool { FoodRecognitionSettings.isAIEnabled }

    /// 当前配置的模型是否支持图片：不支持时照片不会发送，必须靠文字描述识别。
    private var visionSupported: Bool {
        let settings = LLMSettingsStore.load()
        return LLMClient.supportsVision(model: settings.model)
    }

    private var canRecognize: Bool {
        guard !isRecognizing else { return false }
        // 模型不支持视觉时照片无效，必须用文字描述，否则请求必然失败
        if aiEnabled, !visionSupported { return !description.isEmpty }
        return !description.isEmpty || imageData != nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        mealMetaSection
                        photoSection
                        descriptionSection
                        recognizeButton
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .appCard(padding: 14)
                        }
                        if recognized != nil {
                            resultSection(Binding($recognized)!)
                                .id(Self.resultAnchor)
                        }
                    }
                    .padding(16)
                }
                // 识别开始后收起键盘、滚动到结果区；延迟一帧等结果视图渲染出来再定位。
                .onChange(of: scrollToResult) { _, shouldScroll in
                    guard shouldScroll else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(Self.resultAnchor, anchor: .top)
                        }
                        scrollToResult = false
                    }
                }
            }
            .background(AppScreenBackground(tone: .mint))
            .navigationTitle("识别食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecords = true
                    } label: {
                        Label("识别记录", systemImage: "list.bullet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.greenDeep)
                    }
                }
            }
            .confirmationDialog("选择图片来源", isPresented: $showSourcePicker) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照") {
                        pickerSource = .camera
                        showPicker = true
                    }
                }
                Button("从相册选择") {
                    pickerSource = .photoLibrary
                    showPicker = true
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showPicker) {
                CameraImagePicker(source: pickerSource) { picked in
                    image = picked
                    imageData = picked.jpegData(compressionQuality: 0.7)
                }
            }
            .sheet(isPresented: $showRecords) {
                MealRecordsListView()
            }
        }
    }

    /// 餐次 + 用餐时刻：默认按当前时间自动推断，用户可手动改餐次或补录其他日期/时刻。
    private var mealMetaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "用餐信息", icon: "clock.fill", tint: AppPalette.orange)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("餐次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if slotIsAuto {
                            Text("按时间自动判断")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                        ForEach(MealSlot.ordered) { slot in
                            Button {
                                selectedSlot = slot
                                slotIsAuto = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: slot.icon)
                                        .font(.system(size: 11))
                                    Text(slot.title)
                                        .font(.caption.weight(.medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    selectedSlot == slot ? AppPalette.greenDeep : Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .foregroundStyle(selectedSlot == slot ? .white : AppPalette.ink2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DatePicker(
                    "用餐时间",
                    selection: $mealTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)
                .foregroundStyle(AppPalette.ink)
                .onChange(of: mealTime) { _, newValue in
                    if slotIsAuto {
                        selectedSlot = MealSlot.infer(from: newValue)
                    }
                }
                if slotIsAuto {
                    Button("使用当前时间") {
                        mealTime = FoodRecognitionView.combined(date: date, time: .now)
                        selectedSlot = MealSlot.infer(from: mealTime)
                    }
                    .font(.caption)
                    .foregroundStyle(AppPalette.greenDeep)
                }
            }
            .appCard(padding: 14)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "食物照片", icon: "camera.fill", tint: AppPalette.greenDeep)
            Button {
                showSourcePicker = true
            } label: {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 248)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Label("重新选择", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppPalette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(10)
                        }
                } else {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppPalette.greenSoft)
                                .frame(width: 60, height: 60)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(AppPalette.greenDeep)
                        }
                        VStack(spacing: 4) {
                            Text("添加食物照片")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text(aiEnabled
                                 ? (visionSupported ? "照片会发给 AI 视觉模型一起分析" : "当前 AI 模型不支持图片，照片不会发送")
                                 : "照片仅作参考，识别以文字描述为准")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(
                        LinearGradient(
                            colors: [AppPalette.greenSoft, Color(.secondarySystemGroupedBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                            .strokeBorder(AppPalette.line, lineWidth: 1)
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "描述这道食物", icon: "text.bubble.fill", tint: AppPalette.lav)
            TextField("例如：米饭 150g、炒青菜 200g、炸鸡 100g…", text: $description, axis: .vertical)
                .font(.subheadline)
                .padding(14)
                .lineLimit(2...4)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppPalette.line, lineWidth: 1)
                )
            Text(aiEnabled
                 ? (visionSupported
                    ? "照片和文字会一起发送给 AI 视觉模型分析。"
                    : "当前 AI 模型不支持图片输入，将只按这段文字估算营养；想用照片识别请到「设置 → AI 服务」改用支持视觉的模型。")
                 : "将按这段文字从本地营养库匹配食物与营养，不联网。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recognizeButton: some View {
        Button {
            Task { await recognize() }
        } label: {
            HStack(spacing: 8) {
                if isRecognizing {
                    ProgressView()
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isRecognizing ? "识别中…" : (canRecognize ? "开始识别" : "请输入描述或添加照片"))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isRecognizing ? AppPalette.greenDeep : (canRecognize ? AppPalette.greenDeep : AppPalette.ink4),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canRecognize)
    }

    /// 识别结果区在 ScrollView 里的锚点，识别成功后据此自动定位。
    private static let resultAnchor = "foodRecognitionResult"

    /// 收起当前第一响应者的输入法（描述框或营养编辑框）。
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private func recognize() async {
        guard !isRecognizing else { return }
        // 开始识别即收起输入法，否则键盘会一直盖住下方的结果区。
        dismissKeyboard()
        isRecognizing = true
        errorMessage = nil
        saveMessage = nil
        recognized = nil
        defer { isRecognizing = false }
        do {
            // 本地匹配时，把「我的常吃食物」(CustomFood) 与「常用饮食」(FrequentFood) 一起纳入。
            // 常用饮食只补内置库 / 自定义里没有的新名字，避免同名导致识别结果重复命中。
            let custom = (try? context.fetch(FetchDescriptor<CustomFood>()))?
                .map { $0.foodItem } ?? []
            let frequent = (try? context.fetch(FetchDescriptor<FrequentFood>()))?
                .map { $0.foodItem } ?? []
            let knownNames = Set((FoodDatabase.all + custom).map { $0.name.lowercased() })
            let extraFrequent = frequent.filter { !knownNames.contains($0.name.lowercased()) }
            let result = try await FoodRecognitionService.recognize(
                image: imageData,
                description: description,
                custom: custom + extraFrequent
            )
            recognized = result
            // 结果写入后触发一次性滚动定位；onChange 里会重置该标志。
            scrollToResult = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func resultSection(_ meal: Binding<RecognizedMeal>) -> some View {
        let value = meal.wrappedValue
        let isAI = value.source == .ai
        let sourceLabel = isAI ? "AI 识别" : "本地营养库匹配"
        let sourceTint: Color = isAI ? AppPalette.sky : AppPalette.greenDeep
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AppSectionHeader(title: "识别结果", icon: "fork.knife", tint: AppPalette.orange)
                Spacer()
                Text(sourceLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(sourceTint.opacity(0.12))
                    .foregroundStyle(sourceTint)
                    .clipShape(Capsule())
            }
            if let notice = value.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppPalette.orange)
                    .appCard(padding: 12)
            }
            if value.items.isEmpty {
                Text(isAI
                     ? "AI 没有识别出食物。补充文字描述，或关闭 AI 识别改用本地营养库匹配。"
                     : "本地营养库没有匹配到食物。换种说法描述，或开启 AI 识别用照片分析。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .appCard(padding: 14)
            } else {
                ForEach(value.items.indices, id: \.self) { index in
                    MealItemEditCard(item: meal.items[index]) {
                        // 按索引删除当前识别结果里的这一样食物；删空时显示空态提示。
                        guard index < meal.wrappedValue.items.count else { return }
                        meal.wrappedValue.items.remove(at: index)
                    }
                }
                totalCard(value)
                mealScoreCard(value)
                saveButton(value)
            }
        }
    }

    /// 本餐健康评分：营养随数量编辑实时变化，评分同步刷新，并列出具体原因。
    private func mealScoreCard(_ meal: RecognizedMeal) -> some View {
        let evaluation = MealScoringEngine.evaluate(
            nutrition: meal.total, slot: selectedSlot, date: mealTime
        )
        let tint: Color = evaluation.isHealthy
            ? AppPalette.greenDeep
            : (evaluation.score >= ScoringConfig().mealFairThreshold ? AppPalette.orange : AppPalette.red)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppSectionHeader(title: "本餐评分", icon: "heart.text.square.fill", tint: tint)
                Spacer()
                Text(selectedSlot.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppPalette.greenSoft)
                    .foregroundStyle(AppPalette.greenDeep)
                    .clipShape(Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(evaluation.score.rounded()))")
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                Text("/ 100")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(evaluation.isHealthy ? "健康" : evaluation.level)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(evaluation.notes, id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(tint.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("参考该餐次建议摄入量与用餐时段评估，为经验值，非医学建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func totalCard(_ meal: RecognizedMeal) -> some View {
        let t = meal.total
        let stats: [(icon: String, value: String, unit: String, tint: Color)] = [
            ("flame.fill", String(format: "%.0f", t.energyKcal), "千卡", AppPalette.orange),
            ("leaf.fill", String(format: "%.0f", t.carbsG), "碳水 g", AppPalette.greenDeep),
            ("dumbbell", String(format: "%.0f", t.proteinG), "蛋白 g", AppPalette.red),
            ("drop.fill", String(format: "%.0f", t.fatG), "脂肪 g", AppPalette.purple),
            ("heart.fill", String(format: "%.0f", t.fiberG), "纤维 g", AppPalette.teal),
            ("cube.fill", String(format: "%.0f", t.sugarG), "糖 g", AppPalette.sky),
            ("salt", String(format: "%.0f", t.sodiumMg), "钠 mg", AppPalette.ink2),
            ("drop", String(format: "%.0f", t.waterMl), "水 ml", AppPalette.sky),
            ("cup.and.saucer.fill", String(format: "%.0f", t.caffeineMg), "咖啡因 mg", AppPalette.orange),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("合计营养")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(stats, id: \.unit) { stat in
                    NutrientStat(icon: stat.icon, value: stat.value, unit: stat.unit, tint: stat.tint)
                }
            }
            Text("已按苹果健康「营养摄入」\(NutritionField.allCases.count) 项留档，未识别项记 0；完整数值见每项编辑区。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func saveButton(_ meal: RecognizedMeal) -> some View {
        VStack(spacing: 8) {
            if let saveMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(saveMessage)
                        .font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppPalette.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    AppPalette.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            Button {
                if let message = save(meal) {
                    saveMessage = message
                } else {
                    saveMessage = nil
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("记录饮食")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppPalette.greenDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// 保存识别结果为本机记录并回写健康 App；同时把（编辑后的）每样食物写入「常用饮食」列表。
    /// 返回 nil 表示保存成功（调用方关闭页面）；返回文案表示校验失败原因。
    private func save(_ meal: RecognizedMeal) -> String? {
        // 保存前统一归一数量：单位只允许 g / kg / ml / L，数量必须 > 0，
        // 保证新增记录记的是「多少克 / 多少毫升」而不是「一份」。
        let items = meal.items.map { item -> MealItem in
            var copy = item
            copy.portionUnit = MealItem.normalizeUnit(item.portionUnit)
            copy.portionAmount = max(1, item.portionAmount)
            return copy
        }
        guard !items.isEmpty, items.allSatisfy({ $0.hasValidAmount && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return "请给每样食物填写名称和实际数量（克 / 毫升）后再记录。"
        }
        let normalizedMeal = RecognizedMeal(
            items: items,
            source: meal.source,
            rawDescription: meal.rawDescription,
            notice: meal.notice
        )
        let total = normalizedMeal.total
        guard total.hasAny else { return "这一餐的营养全部为 0，请编辑营养后再记录。" }
        // 记录备注同时保留用户描述与（可修改后的）食物名称，方便回看核对。
        let note = buildNote(normalizedMeal)
        let id = UUID().uuidString
        // 用餐时刻用用户选定的真实时刻（不再是当天 00:00），餐次与单餐评分一并落库，
        // 供规律饮食判断、识别记录时间轴与状态分使用。
        let evaluation = MealScoringEngine.evaluate(
            nutrition: total, slot: selectedSlot, date: mealTime
        )
        let checkIn = ActionCheckIn(
            dayKey: DayKey.key(for: mealTime),
            kindRaw: "meal",
            amount: 0,
            note: note,
            syncID: id,
            createdAt: mealTime,
            nutritionJSON: encode(total),
            recognitionSource: meal.source.rawValue,
            mealSlotRaw: selectedSlot.rawValue,
            mealScore: evaluation.score
        )
        // 逐样食物一并落库：编辑记录时才能按「每样」改数量并等比改营养。
        checkIn.setMealItems(items)
        context.insert(checkIn)
        // 编辑后的食物写入「常用饮食」，按名称去重累加使用次数。
        recordFrequentFoods(items)
        do {
            try context.save()
        } catch {
            return "保存失败，请稍后重试。"
        }
        let record = MealSyncRecord(
            syncID: id,
            date: mealTime,
            nutrition: total,
            source: meal.source.rawValue,
            note: note,
            kind: "meal"
        )
        Task {
            await MealCheckInSync.push(record: record, context: context)
        }
        return nil
    }

    /// 把识别到的每样（已编辑的）食物 upsert 进「常用饮食」：同名已存在则更新数量/营养并累加次数，否则新增。
    private func recordFrequentFoods(_ items: [MealItem]) {
        let existing = (try? context.fetch(FetchDescriptor<FrequentFood>())) ?? []
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if let match = existing.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
                match.portion = item.portionText
                match.nutritionJSON = encode(item.perPortion) ?? "{}"
                match.useCount += 1
                match.lastUsedAt = .now
            } else {
                context.insert(FrequentFood(name: name, portion: item.portionText, nutrition: item.perPortion))
            }
        }
    }

    /// 记录备注：用户描述 + 每样食物的「名称 数字+单位」，方便回看时核对识别是否准确。
    private func buildNote(_ meal: RecognizedMeal) -> String? {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemsText = MealNoteParts.compose(meal.items)
        var parts: [String] = []
        if !desc.isEmpty { parts.append(desc) }
        if let itemsText { parts.append(itemsText) }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private func encode(_ nutrition: IntakeNutrition) -> String? {
        guard let data = try? JSONEncoder().encode(nutrition) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 识别记录（独立页面）

    /// 识别记录从主页面移出，改为右上角「识别记录」按钮点击后弹出的独立页面，
    /// 自带 @Query 保持实时刷新，支持逐条删除（同时清理健康 App 内对应样本）。
    /// 识别记录列表也供行动页「饮食」卡片直接打开，因此不再私有。
    struct MealRecordsListView: View {
        @Environment(\.modelContext) private var context
        @Environment(\.dismiss) private var dismiss
        /// 编辑中的记录；编辑页直接修改该 SwiftData 实例并保存，列表 @Query 自动刷新。
        /// 用 item 驱动 sheet，避免「布尔开关 + 可选记录」两个状态在呈现时序上不同步、弹出空 sheet。
        @State private var editingRecord: ActionCheckIn?

        @Query(
            filter: #Predicate<ActionCheckIn> { $0.kindRaw == "meal" || $0.kindRaw == "caffeine" },
            sort: \ActionCheckIn.createdAt,
            order: .reverse
        ) private var dietRecords: [ActionCheckIn]

        var body: some View {
            NavigationStack {
                ScrollView {
                    if dietRecords.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 36))
                                .foregroundStyle(AppPalette.green.opacity(0.8))
                            Text("还没有饮食记录")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text("识别或记录咖啡饮品后会显示在这里。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(groupedByDay, id: \.key) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(group.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppPalette.ink)
                                        Spacer()
                                        Text(group.regularity.level)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(AppPalette.greenSoft)
                                            .foregroundStyle(AppPalette.greenDeep)
                                            .clipShape(Capsule())
                                    }
                                    // 规律饮食明细只作构成说明，统一饮食评分在饮食详情页头部展示。
                                    if group.regularity.score != nil {
                                        Text(group.regularity.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(group.records) { record in
                                        if record.kindRaw == SyncableCheckInKind.caffeine.rawValue {
                                            CaffeineRecordCard(record: record, onDelete: { delete(record) })
                                        } else {
                                            MealRecordCard(record: record, onDelete: { delete(record) }) {
                                                editingRecord = record
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                .background(AppScreenBackground(tone: .mint))
                .navigationTitle("饮食记录")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $editingRecord) { record in
                    MealRecordEditor(record: record)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.ink2)
                    }
                }
            }
        }

        /// 按天分组的时间轴，每组带当天的规律饮食结论。
        private struct DayGroup {
            let key: String
            let title: String
            let records: [ActionCheckIn]
            let regularity: MealRegularity
        }

        private var groupedByDay: [DayGroup] {
            let calendar = Calendar.current
            // 规律饮食只统计 meal 打卡；咖啡因饮品没有 mealSlot，天然被排除。
            let entries = dietRecords.compactMap { check -> MealEntry? in
                guard let slot = check.mealSlot else { return nil }
                return MealEntry(
                    id: check.ensureSyncID(), date: check.createdAt, slot: slot,
                    nutrition: check.nutrition, score: check.mealScore
                )
            }
            var buckets: [String: [ActionCheckIn]] = [:]
            var dates: [String: Date] = [:]
            for record in dietRecords {
                let key = DayKey.key(for: record.createdAt, calendar: calendar)
                buckets[key, default: []].append(record)
                dates[key] = record.createdAt
            }
            let keys = buckets.keys.sorted().reversed()
            return keys.compactMap { key in
                guard let day = dates[key],
                      let date = DayKey.date(from: key, calendar: calendar) else { return nil }
                // 全页统一倒序：日期分组最新在前，每组内的记录也最新在前。
                let records = (buckets[key] ?? []).sorted { $0.createdAt > $1.createdAt }
                let regularity = MealScoringEngine.regularity(entries: entries, on: date, calendar: calendar)
                let title = DayKey.key(for: .now, calendar: calendar) == key
                    ? "今天 · \(Self.dayFormatter.string(from: day))"
                    : Self.dayFormatter.string(from: day)
                return DayGroup(key: key, title: title, records: records, regularity: regularity)
            }
        }

        private static let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "M月d日"
            return f
        }()

        private func delete(_ record: ActionCheckIn) {
            let syncID = record.ensureSyncID()
            if record.kindRaw == SyncableCheckInKind.caffeine.rawValue {
                deleteCaffeine(record, syncID: syncID)
                return
            }
            context.delete(record)
            do {
                try context.save()
            } catch {
                return
            }
            // 删健康 App 里对应样本，并刷新本地汇总与评分。
            Task {
                await MealCheckInSync.remove(syncID: syncID, context: context)
            }
        }

        /// 删除咖啡因饮品：本地打卡、联动生成的喝水记录，以及健康 App 里
        /// 同 syncID 的咖啡因 / 营养 / 饮水样本一起清理，避免留下孤儿数据。
        private func deleteCaffeine(_ record: ActionCheckIn, syncID: String) {
            let linkedWaterSyncID = ActionCheckIn.linkedWaterSyncID(for: syncID)
            let allChecks = (try? context.fetch(FetchDescriptor<ActionCheckIn>())) ?? []
            let waterLocal = allChecks.first {
                $0.kindRaw == SyncableCheckInKind.water.rawValue && $0.syncID == linkedWaterSyncID
            }
            context.delete(record)
            if let waterLocal { context.delete(waterLocal) }
            do {
                try context.save()
            } catch {
                return
            }
            Task {
                // deleteCheckIn 会按 syncID 删除咖啡因主样本与 7 类营养样本。
                await WaterCheckInSync.remove(
                    syncID: syncID,
                    kind: SyncableCheckInKind.caffeine.rawValue,
                    context: context
                )
                await WaterCheckInSync.remove(
                    syncID: linkedWaterSyncID,
                    kind: SyncableCheckInKind.water.rawValue,
                    context: context
                )
            }
        }
    }
}

/// 单个营养数值小卡：图标圆底 + 数值 + 单位，按营养类型着色。
private struct NutrientStat: View {
    let icon: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
            Text(value)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppPalette.ink)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 单样食物的可编辑卡片：可删除、名称可改、数量可改（数字 + 实际单位，改数字时营养等比缩放），
/// 展开后可改苹果健康「营养摄入」全部 40 项指标。不再有「份数」这一层。
struct MealItemEditCard: View {
    @Binding var item: MealItem
    /// 删除这一样食物（由结果区按索引移除）。
    var onDelete: () -> Void = {}
    /// 其余 31 项微量营养素默认收起，避免 40 个输入框压满整页。
    @State private var showExtendedNutrition = false

    /// 数量输入绑定：改数字时走 updatePortionAmount，把营养按新/旧比例等比例缩放。
    private var amountBinding: Binding<Double> {
        Binding(
            get: { item.portionAmount },
            set: { item.updatePortionAmount(to: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FoodRemoteIcon(imageURL: item.imageURL)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("食物名称", text: $item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    // 数量按实际计量记录：数字必填，单位只允许克 / 毫升，不再出现「份」。
                    HStack(spacing: 6) {
                        Text("数量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("数量", value: amountBinding, format: .number)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(AppPalette.ink)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 62)
                            .padding(.vertical, 5)
                            .background(
                                (item.portionAmount > 0 ? Color(.secondarySystemGroupedBackground) : AppPalette.red.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        Picker("单位", selection: $item.portionUnit) {
                            Text("克").tag("g")
                            Text("毫升").tag("ml")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 116)
                        Spacer(minLength: 0)
                    }
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Color(.systemRed).opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Text(item.portionAmount > 0
                 ? "营养按这 \(item.portionText) 计算，改数量会按比例重算"
                 : "请填写实际克数或毫升数，营养按该数量记录")
                .font(.caption2)
                .foregroundStyle(item.portionAmount > 0 ? Color(.tertiaryLabel) : AppPalette.red)
            DisclosureGroup {
                nutritionGrid
            } label: {
                Text("编辑营养（当前数量）")
                    .font(.caption)
                    .foregroundStyle(AppPalette.ink2)
            }
        }
        .appCard()
    }

    private var nutritionGrid: some View {
        VStack(spacing: 6) {
            NutritionFieldsEditor(nutrition: $item.perPortion, fields: NutritionField.primaryFields)
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
                Text("官网 / 模型未提供的指标保持 0，不影响评分。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                NutritionFieldsEditor(
                    nutrition: $item.perPortion,
                    fields: NutritionField.extendedFields,
                    labelWidth: 104
                )
            }
        }
        .padding(.top, 4)
    }
}

/// 按 NutritionField 清单批量渲染营养输入框（主要指标 + 苹果健康其余指标共用）。
struct NutritionFieldsEditor: View {
    @Binding var nutrition: IntakeNutrition
    let fields: [NutritionField]
    var labelWidth: CGFloat = 64

    var body: some View {
        ForEach(fields, id: \.jsonKey) { field in
            NutrientField(
                label: field.displayName,
                unit: field.unit,
                value: Binding(
                    get: { nutrition[field] },
                    set: { nutrition[field] = $0 }
                ),
                labelWidth: labelWidth
            )
        }
    }
}

/// 单个营养数值输入框，仅接受非负数。
struct NutrientField: View {
    let label: String
    let unit: String
    @Binding var value: Double
    /// 微量营养素中文名较长，折叠区用更宽的标签列。
    var labelWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppPalette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: labelWidth, alignment: .leading)
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

/// 咖啡因饮品在饮食记录里的一行：饮品名 + 咖啡因 + 随打卡写回的营养成分，可删除。
private struct CaffeineRecordCard: View {
    let record: ActionCheckIn
    var onDelete: () -> Void = {}

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let tint = Color(red: 0.663, green: 0.455, blue: 0.310)

    private var nutrition: IntakeNutrition { record.nutrition }
    private var title: String {
        if let note = record.note, !note.isEmpty { return note }
        return "咖啡因饮品"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("咖啡因", systemImage: "mug.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Self.tint.opacity(0.14))
                        .foregroundStyle(Self.tint)
                        .clipShape(Capsule())
                    Text(Self.formatter.string(from: record.createdAt))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("本 App 打卡")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Self.tint.opacity(0.12))
                        .foregroundStyle(Self.tint)
                        .clipShape(Capsule())
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(2)
                if nutrition.hasAny {
                    Text("咖啡因 \(Int(record.amount.rounded())) mg · 热量 \(Int(nutrition.energyKcal.rounded())) 千卡 · 碳水 \(Int(nutrition.carbsG.rounded())) g · 蛋白 \(Int(nutrition.proteinG.rounded())) g · 脂肪 \(Int(nutrition.fatG.rounded())) g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("咖啡因 \(Int(record.amount.rounded())) mg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("删除时会同步删除这条饮品对应的营养记录与饮水记录。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemRed).opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .appCard(padding: 14)
    }
}

/// 单条已保存的识别记录卡：日期 + 来源 + 食物（备注）+ 合计营养，可删除。
private struct MealRecordCard: View {
    let record: ActionCheckIn
    var onDelete: () -> Void = {}
    /// 点击编辑：由列表 present 编辑页（MealRecordEditor）。
    var onEdit: () -> Void = {}

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var isAI: Bool { record.recognitionSource == "ai" }
    private var sourceLabel: String { isAI ? "AI 识别" : "本地营养库匹配" }
    private var sourceTint: Color { isAI ? AppPalette.sky : AppPalette.greenDeep }

    /// 旧记录没有存评分时按营养与推断餐次重算，保证历史记录也有评分展示。
    private var evaluation: MealEvaluation? {
        guard let slot = record.mealSlot else { return nil }
        let slotDate = record.createdAt
        if let stored = record.mealScore {
            let full = MealScoringEngine.evaluate(
                nutrition: nutrition, slot: slot, date: slotDate
            )
            return MealEvaluation(
                score: stored, isHealthy: stored >= ScoringConfig().mealHealthyThreshold && full.isHealthy,
                level: full.level, notes: full.notes
            )
        }
        return MealScoringEngine.evaluate(nutrition: nutrition, slot: slot, date: slotDate)
    }

    private var nutrition: IntakeNutrition { record.nutrition }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let slot = record.mealSlot {
                        Label(slot.title, systemImage: slot.icon)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppPalette.greenSoft)
                            .foregroundStyle(AppPalette.greenDeep)
                            .clipShape(Capsule())
                    }
                    Text(Self.formatter.string(from: record.createdAt))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(sourceLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(sourceTint.opacity(0.12))
                        .foregroundStyle(sourceTint)
                        .clipShape(Capsule())
                }
                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                }
                Text("热量 \(Int(nutrition.energyKcal.rounded())) 千卡 · 碳水 \(Int(nutrition.carbsG.rounded())) g · 蛋白 \(Int(nutrition.proteinG.rounded())) g · 脂肪 \(Int(nutrition.fatG.rounded())) g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let evaluation {
                    HStack(spacing: 6) {
                        Text("本餐 \(Int(evaluation.score.rounded())) 分")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(evaluation.isHealthy ? AppPalette.greenDeep : AppPalette.orange)
                        Text(evaluation.isHealthy ? "健康" : evaluation.level)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.ink2)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemRed).opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .appCard(padding: 14)
    }
}

/// 识别记录编辑页：修改餐次 / 用餐时间 / 食物名称与数量（数字 + 单位）/ 本餐营养，
/// 保存后写回本地 ActionCheckIn，并复用「识别保存」的同一条回写链路（MealCheckInSync.push）
/// 把 7 类膳食样本同步到健康 App（值变化时健康 App 侧样本会按 syncID 重写）。
private struct MealRecordEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// 直接持有 SwiftData 实例，编辑即改其属性，保存后 @Query 列表自动刷新。
    let record: ActionCheckIn

    @State private var slot: MealSlot
    @State private var mealTime: Date
    /// 从历史备注拆出的食物名称（旧记录里的「×N份」不再混在名称里）。
    @State private var foodName: String
    /// 可编辑的数量数值与单位，替代原「份数」。
    @State private var amountText: String
    @State private var amountUnit: String
    /// 逐样食物明细。新记录保存时一并落库，编辑时按「每样」改数量并等比缩放该样营养；
    /// 旧记录为空数组，仍走原来的聚合营养编辑（不改造既有数据）。
    @State private var items: [MealItem]
    @State private var nutrition: IntakeNutrition
    @State private var saving = false
    @State private var showExtendedNutrition = false
    /// 分项模式下展开「单项营养」编辑的食物 id。
    @State private var expandedItemID: String?
    /// 校验提示（如某样食物没填名称 / 数量）。
    @State private var validationMessage: String?

    init(record: ActionCheckIn) {
        self.record = record
        _slot = State(initialValue: record.mealSlot ?? .lunch)
        _mealTime = State(initialValue: record.createdAt)
        let parts = MealNoteParts.parse(record.note ?? "")
        _foodName = State(initialValue: parts.name)
        _amountText = State(initialValue: parts.amount)
        _amountUnit = State(initialValue: parts.unit)
        _items = State(initialValue: record.mealItems.map(\.normalizedForEditing))
        _nutrition = State(initialValue: record.nutrition)
    }

    /// 有分项数据时按每样食物编辑；旧记录没有分项数据，退回聚合编辑。
    private var usesItemEditor: Bool { !items.isEmpty }

    /// 本餐营养：分项模式由各样食物营养实时合计，旧记录用聚合输入值。
    private var effectiveNutrition: IntakeNutrition {
        usesItemEditor
            ? items.reduce(.zero) { $0 + $1.perPortion }
            : nutrition
    }

    /// 评分随餐次 / 时间 / 营养实时变化，编辑时即时预览。
    private var evaluation: MealEvaluation {
        MealScoringEngine.evaluate(nutrition: effectiveNutrition, slot: slot, date: mealTime)
    }

    /// 保存时写回的备注：名称 + 数字 + 单位，统一不再出现「份」。
    private var composedNote: String? {
        let text = MealNoteParts(name: foodName, amount: amountText, unit: amountUnit).composed
        return text.isEmpty ? nil : text
    }

    var body: some View {
        // 本页是从「识别记录」sheet 里再弹出的第二层 sheet，内层再嵌 NavigationStack
        // 会出现整页空白（双层导航容器在 iOS 27 上拿不到有效布局层级）。
        // 改为普通 VStack + 自绘顶栏：内容不再依赖导航容器，呈现时必定有视图可渲染。
        VStack(spacing: 0) {
            editorToolbar
            if let validationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(validationMessage)
                        .font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppPalette.red)
                .padding(.horizontal, AppTheme.cardMargin)
                .padding(.vertical, 8)
                .background(AppPalette.red.opacity(0.08))
            }
            ScrollView {
                VStack(spacing: 18) {
                    metaSection
                    if usesItemEditor {
                        itemsSection
                        summarySection
                    } else {
                        foodSection
                        nutritionSection
                    }
                    scoreCard
                }
                .padding(.horizontal, AppTheme.cardMargin)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppScreenBackground(tone: .mint))
        .presentationDetents([.large])
    }

    /// 顶部工具栏：取消 / 标题 / 保存。按钮加胶囊底和更大内边距，避免文字贴着屏幕边框。
    private var editorToolbar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text("编辑记录")
                .font(.headline)
                .foregroundStyle(AppPalette.ink)
            Spacer(minLength: 8)
            Button {
                saveEdit()
            } label: {
                Text("保存")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppPalette.greenDeep, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        .padding(.horizontal, AppTheme.cardMargin)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    /// 用餐信息：餐次带图标一键切换，用餐时间单独一行。
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "用餐信息", icon: "clock.fill", tint: AppPalette.orange)
            Text("餐次")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(MealSlot.allCases) { s in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { slot = s }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: s.icon)
                                .font(.system(size: 15, weight: .semibold))
                            Text(s.title)
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            slot == s ? AppPalette.greenDeep : AppPalette.greenSoft,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(slot == s ? .white : AppPalette.greenDeep)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            DatePicker(
                "用餐时间",
                selection: $mealTime,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline)
            .foregroundStyle(AppPalette.ink)
        }
        .appCard(padding: 18)
    }

    /// 食物信息：名称与「数量 + 单位」拆成独立可编辑字段，旧「份」写法在这里改成真实单位。
    private var foodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "食物与数量", icon: "fork.knife", tint: AppPalette.greenDeep)
            VStack(alignment: .leading, spacing: 6) {
                Text("名称 / 备注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("食物名称", text: $foodName, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .lineLimit(2...3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("数量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField("数字", text: $amountText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppPalette.ink)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .frame(maxWidth: 140)
                    TextField("单位", text: $amountUnit)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .frame(maxWidth: 90)
                    Spacer(minLength: 0)
                }
            }
            Text("旧记录的「份」已按数值保留，请核对并改成实际单位（如 g / ml）；营养在下方单独填写。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    /// 分项编辑：每样食物一张卡。改数量时只缩放这一样食物的营养（按 新/旧 比例），
    /// 合计与评分实时重算；单位只允许克 / 毫升，不再出现「一份」。
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                AppSectionHeader(
                    title: "食物清单（\(items.count) 样）",
                    icon: "list.bullet.rectangle.portrait.fill",
                    tint: AppPalette.greenDeep
                )
                Spacer(minLength: 8)
                Button {
                    addItem()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("添加")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppPalette.greenDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppPalette.greenSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                itemCard(index)
            }
            Text("改数量只会按比例重算这一样食物的营养；下方合计与评分实时更新。单位只记克或毫升。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    /// 单样食物的编辑卡：名称、数量（数字 + 克/毫升）、该样营养摘要，可展开逐项微调营养。
    private func itemCard(_ index: Int) -> some View {
        let item = items[index]
        let expanded = expandedItemID == item.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(AppPalette.greenDeep, in: Circle())
                TextField("食物名称", text: $items[index].name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                Button {
                    removeItem(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(items.count > 1 ? AppPalette.red : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .disabled(items.count <= 1)
            }
            HStack(spacing: 10) {
                TextField("数量", value: amountBinding(index), format: .number)
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(AppPalette.ink)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .frame(maxWidth: 96)
                Picker("单位", selection: $items[index].portionUnit) {
                    Text("克").tag("g")
                    Text("毫升").tag("ml")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
                Spacer(minLength: 0)
            }
            // 这一样食物当前数量对应的营养摘要，改数量时同步变化，方便直接核对。
            HStack(spacing: 10) {
                Text("\(Int(item.perPortion.energyKcal.rounded())) 千卡")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.orange)
                Text("碳水 \(MealItem.formatAmount(item.perPortion.carbsG))g")
                Text("蛋白 \(MealItem.formatAmount(item.perPortion.proteinG))g")
                Text("脂肪 \(MealItem.formatAmount(item.perPortion.fatG))g")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedItemID = expanded ? nil : item.id
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    Text(expanded ? "收起单项营养" : "微调单项营养")
                }
                .font(.caption2)
                .foregroundStyle(AppPalette.greenDeep)
            }
            .buttonStyle(.plain)
            if expanded {
                NutritionFieldsEditor(
                    nutrition: $items[index].perPortion,
                    fields: NutritionField.primaryFields
                )
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    /// 本餐营养合计（分项模式只读）：各样食物营养相加，随数量变化实时刷新。
    private var summarySection: some View {
        let total = effectiveNutrition
        return VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "本餐营养合计", icon: "chart.bar.fill", tint: AppPalette.lav)
            VStack(spacing: 8) {
                summaryRow("能量", value: "\(Int(total.energyKcal.rounded())) 千卡", tint: AppPalette.orange)
                summaryRow("碳水", value: MealItem.formatAmount(total.carbsG) + " g")
                summaryRow("蛋白质", value: MealItem.formatAmount(total.proteinG) + " g")
                summaryRow("脂肪", value: MealItem.formatAmount(total.fatG) + " g")
                summaryRow("膳食纤维", value: MealItem.formatAmount(total.fiberG) + " g")
                summaryRow("钠", value: MealItem.formatAmount(total.sodiumMg) + " mg")
            }
            Text("合计由各样食物的数量与营养自动相加；要改营养请在上面某一项里展开「微调单项营养」。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    private func summaryRow(_ title: String, value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint ?? AppPalette.ink)
        }
    }

    /// 数量输入绑定：写入时走 updatePortionAmount，按 新/旧 比例缩放这一样食物的营养。
    private func amountBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { items[index].portionAmount },
            set: { items[index].updatePortionAmount(to: $0) }
        )
    }

    private func addItem() {
        let newItem = MealItem(name: "", portionAmount: 100, portionUnit: "g", perPortion: .zero)
        withAnimation(.easeInOut(duration: 0.18)) {
            items.append(newItem)
        }
        expandedItemID = newItem.id
    }

    private func removeItem(at index: Int) {
        guard items.indices.contains(index), items.count > 1 else { return }
        let id = items[index].id
        withAnimation(.easeInOut(duration: 0.18)) {
            items.remove(at: index)
        }
        if expandedItemID == id { expandedItemID = nil }
    }

    /// 营养编辑区：主要指标常驻，苹果健康其余指标按需展开。
    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "本餐营养", icon: "chart.bar.fill", tint: AppPalette.lav)
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
                Text("未记录的指标保持 0，不参与评分。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                NutritionFieldsEditor(
                    nutrition: $nutrition,
                    fields: NutritionField.extendedFields,
                    labelWidth: 104
                )
            }
            Text("修改碳水 / 蛋白质 / 脂肪 / 水 / 咖啡因会更新下方评分；健康 App 回写仍按既有 7 类膳食样本，其余指标只在 App 内留档。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    /// 本餐评分：随餐次 / 时间 / 营养实时重算，给编辑提供即时反馈。
    private var scoreCard: some View {
        let tint: Color = evaluation.isHealthy
            ? AppPalette.greenDeep
            : (evaluation.score >= ScoringConfig().mealFairThreshold ? AppPalette.orange : AppPalette.red)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppSectionHeader(title: "本餐评分", icon: "heart.text.square.fill", tint: tint)
                Spacer()
                Text(slot.title)
                    .font(.caption.weight(.medium))
            }
            HStack(spacing: 12) {
                Text(String(format: "%.0f", evaluation.score))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(evaluation.level)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(evaluation.isHealthy ? "饮食健康" : "需注意")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if !evaluation.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(evaluation.notes, id: \.self) { n in
                        Label(n, systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("参考该餐次建议摄入量与用餐时段评估，为经验值，非医学建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    /// 分项模式下重拼备注：保留识别保存时写下的用户描述（「描述；食物清单」里的前半段），
    /// 只把食物清单换成编辑后的名称 + 数量，避免改一次数量就把原始描述冲掉。
    private func composedNoteKeepingDescription() -> String? {
        let itemText = MealNoteParts.compose(items)
        let original = record.note ?? ""
        let oldItemText = MealNoteParts.compose(record.mealItems.map(\.normalizedForEditing))
        let firstSegment = original
            .split(separator: "；", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let keepsDescription = !firstSegment.isEmpty && firstSegment != oldItemText
        switch (keepsDescription, itemText) {
        case (true, let item?): return firstSegment + "；" + item
        case (true, nil): return firstSegment
        case (false, let item?): return item
        case (false, nil): return nil
        }
    }

    private func saveEdit() {
        validationMessage = nil
        // 分项模式：每样食物必须有名称和大于 0 的克 / 毫升数量，否则不允许落库。
        if usesItemEditor {
            let cleaned = items.map { item -> MealItem in
                var copy = item
                copy.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.portionAmount = max(1, item.portionAmount)
                copy.portionUnit = MealItem.normalizeUnit(item.portionUnit)
                return copy
            }
            guard cleaned.allSatisfy({ !$0.name.isEmpty && $0.hasValidAmount }) else {
                validationMessage = "请给每样食物填好名称和实际数量（克 / 毫升）再保存。"
                return
            }
            items = cleaned
        }
        let total = effectiveNutrition
        // 分项模式下备注按各样食物重新拼接；旧记录沿用名称 + 数量写法。
        let note = usesItemEditor ? composedNoteKeepingDescription() : composedNote
        saving = true
        // 旧记录可能缺 syncID：先补齐并在 save 时持久化，保证健康 App 回写能定位到同一条样本。
        _ = record.ensureSyncID()
        record.note = note
        record.nutritionJSON = (try? JSONEncoder().encode(total))
            .flatMap { String(data: $0, encoding: .utf8) }
        if usesItemEditor {
            record.setMealItems(items)
        }
        record.mealSlotRaw = slot.rawValue
        record.mealScore = MealScoringEngine.evaluate(
            nutrition: total, slot: slot, date: mealTime
        ).score
        record.createdAt = mealTime
        record.dayKey = DayKey.key(for: mealTime)
        do {
            try context.save()
        } catch {
            saving = false
            return
        }
        let syncID = record.syncID ?? record.ensureSyncID()
        let syncRecord = MealSyncRecord(
            syncID: syncID,
            date: mealTime,
            nutrition: total,
            source: record.recognitionSource ?? "local",
            note: note,
            kind: "meal"
        )
        // 回写健康 App：值变化（营养 / 时间 / 餐次）时，MealSyncReconciler 会按 syncID 删旧写新；
        // push 末尾 refresh 会重算当天（及跨天后的旧天）规律饮食与汇总。
        Task { @MainActor in
            await MealCheckInSync.push(record: syncRecord, context: context)
            dismiss()
        }
    }
}
