import SwiftUI
import SwiftData
import UIKit
import PhotosUI

/// 食物识别主界面：拍照 / 相册选图 + 文字描述，按设置走 AI 或本地营养库匹配，
/// 结果可逐项编辑营养与数量（数字 + 单位），保存后写入本 App 记录并回写健康 App。
struct FoodRecognitionView: View {
    /// 用餐时间，默认沿用行动页选中的日期（用户可在行动页改日期后进入）。
    let date: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 待识别的食物照片（JPEG 压缩数据），支持一次选择/拍摄多张。拍照每次追加，相册可多选。
    @State private var imageDatas: [Data] = []
    /// 相册多选（PhotosPicker）的中间结果：选中项在 onChange 里转成 Data 追加到 imageDatas。
    @State private var photoPickers: [PhotosPickerItem] = []
    @State private var showPhotoLibraryPicker = false
    @State private var description = ""
    @State private var showSourcePicker = false
    @State private var pickerSource: CameraImagePicker.Source = .photoLibrary
    @State private var showPicker = false
    @State private var isRecognizing = false
    @State private var recognized: RecognizedMeal?
    /// 识别结果里用户手动勾选「保存」的食物行 id；默认空，未勾选的行不写入「常用饮食」营养库。
    /// 用 MealItem.id 而不是行下标关联，增删行后勾选状态仍对应原食物。
    @State private var librarySelectedIDs: Set<String> = []
    /// 直接从营养库补充进来的行 id：这些食物本就在库里，不再展示「勾选后写入营养库」。
    @State private var libraryProvidedIDs: Set<String> = []
    @State private var errorMessage: String?
    /// 保存校验收到的提示（如某样食物没填数量），就近显示在「记录饮食」按钮上方。
    @State private var saveMessage: String?
    /// 识别记录改为右上角按钮点击后弹出独立页面，避免主页面铺满历史记录显得杂乱。
    @State private var showRecords = false
    /// 识别结果区的锚点：识别开始后收起键盘并滚动到这里，让用户直接看到结果。
    @State private var scrollToResult = false
    /// 补充食材面板：在识别结果上追加遗漏食物（营养库 / 拍照识别 / 手动）。
    @State private var showSupplement = false

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
        return !description.isEmpty || !imageDatas.isEmpty
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
            .confirmationDialog("添加食物照片", isPresented: $showSourcePicker) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照") {
                        pickerSource = .camera
                        showPicker = true
                    }
                }
                Button("从相册选择（可多选）") {
                    showPhotoLibraryPicker = true
                }
                Button("取消", role: .cancel) {}
            }
            // 拍照：一次一张，追加到已选列表，可反复拍照凑齐多张。
            .sheet(isPresented: $showPicker) {
                CameraImagePicker(source: pickerSource) { picked in
                    if let data = picked.jpegData(compressionQuality: 0.7) {
                        imageDatas.append(data)
                    }
                }
            }
            // 相册：系统原生多选（最多 9 张），选中项异步转成 JPEG 数据后追加。
            .photosPicker(
                isPresented: $showPhotoLibraryPicker,
                selection: $photoPickers,
                maxSelectionCount: 9,
                matching: .images
            )
            .onChange(of: photoPickers) { _, items in
                Task { @MainActor in
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let jpeg = image.jpegData(compressionQuality: 0.7) {
                            imageDatas.append(jpeg)
                        }
                    }
                    photoPickers = []
                }
            }
            .sheet(isPresented: $showRecords) {
                MealRecordsListView(date: date)
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
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(imageDatas.indices, id: \.self) { index in
                    if let uiImage = UIImage(data: imageDatas[index]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 104, height: 104)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    imageDatas.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 19))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                            }
                    }
                }
                Button {
                    showSourcePicker = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                        Text(imageDatas.isEmpty ? "添加照片" : "继续添加")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(AppPalette.greenDeep)
                    .frame(width: 104, height: 104)
                    .background(AppPalette.greenSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppPalette.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Text(aiEnabled
                 ? (visionSupported
                    ? "可拍照或一次多选相册照片（最多 9 张），AI 会一起分析。"
                    : "当前 AI 模型不支持图片，照片不会发送，请用文字描述。")
                 : "照片仅作参考，识别以文字描述为准。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        librarySelectedIDs.removeAll()
        libraryProvidedIDs.removeAll()
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
                images: imageDatas,
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
                    let itemID = value.items[index].id
                    MealItemEditCard(
                        item: meal.items[index],
                        // 本地匹配 / 营养库补充的食物已经在库里，不再让用户勾选保存。
                        showsLibrarySave: isAI && !libraryProvidedIDs.contains(itemID),
                        saveToLibrary: Binding(
                            get: { librarySelectedIDs.contains(itemID) },
                            set: { selected in
                                if selected {
                                    librarySelectedIDs.insert(itemID)
                                } else {
                                    librarySelectedIDs.remove(itemID)
                                }
                            }
                        ),
                        onDelete: {
                            // 删除行时同步清掉该行的勾选 / 营养库来源标记，避免残留 id 影响后续同批结果。
                            librarySelectedIDs.remove(itemID)
                            libraryProvidedIDs.remove(itemID)
                            meal.wrappedValue.items.removeAll { $0.id == itemID }
                        }
                    )
                }
                // 在识别结果上补充遗漏食材：营养库多选 / 拍照识别 / 手动新增。
                Button {
                    showSupplement = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("补充食材")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.greenDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppPalette.greenSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSupplement) {
                    IngredientSupplementSheet { added, fromLibrary in
                        // 补充进来的饮品同样补水 / 咖啡因，避免新加的一杯咖啡没算水量。
                        let items = DrinkIntakeEstimator.applying(to: added)
                        if fromLibrary {
                            libraryProvidedIDs.formUnion(items.map(\.id))
                        }
                        meal.wrappedValue.items.append(contentsOf: items)
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

    /// 保存识别结果为本机记录并回写健康 App；只有手动勾选「保存」的行才写入「常用饮食」营养库。
    /// 本地营养库匹配 / 营养库补充的行不展示勾选，因此也不会重复写入库。
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
        // 饮品的水量与咖啡因在这里再兜底一次：用户在识别结果里改过份量后，
        // 水量要跟着新容量重算（估算器只在字段为 0 时补，不会覆盖已有真实值）。
        let normalizedMeal = RecognizedMeal(
            items: DrinkIntakeEstimator.applying(to: items),
            source: meal.source,
            rawDescription: meal.rawDescription,
            notice: meal.notice
        )
        let total = normalizedMeal.total
        // 只有含水量的记录（一瓶矿泉水、一杯无糖美式）也算有效：
        // 饮品的含水量现在会并入当日饮水总量，不再要求必须有热量或三大营养素。
        guard total.hasAny || total.waterMl > 0 else {
            return "这一餐的营养全部为 0，请编辑营养后再记录。"
        }
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
            mealScore: evaluation.score,
            photoData: imageDatas.first.flatMap { Self.persistablePhoto($0) },
            photoDataList: imageDatas.compactMap { Self.persistablePhoto($0) }
        )
        // 逐样食物一并落库：编辑记录时才能按「每样」改数量并等比改营养。
        // 用补齐过水量 / 咖啡因的清单，保证分项之和与整餐汇总一致。
        checkIn.setMealItems(normalizedMeal.items)
        context.insert(checkIn)
        // 只把用户逐行勾选的食物写入「常用饮食」；未勾选 / 取消勾选的行只进本餐记录，不进营养库。
        // 按当前行 id 过滤，删除过的行不会因残留 id 被误写入。
        let selected = normalizedMeal.items.filter { librarySelectedIDs.contains($0.id) }
        recordFrequentFoods(selected)
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

    /// 把用户勾选的（已编辑的）食物 upsert 进「常用饮食」：同名已存在则更新数量/营养并累加次数，否则新增。
    /// 同一次保存里也按名称去重，避免两条同名识别行各插一条重复营养库记录。
    private func recordFrequentFoods(_ items: [MealItem]) {
        let existing = (try? context.fetch(FetchDescriptor<FrequentFood>())) ?? []
        var byName: [String: FrequentFood] = [:]
        for food in existing {
            let key = food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, byName[key] == nil else { continue }
            byName[key] = food
        }
        var handledThisSave: Set<String> = []
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard handledThisSave.insert(key).inserted else { continue }
            if let match = byName[key] {
                match.portion = item.portionText
                match.nutritionJSON = encode(item.perPortion) ?? "{}"
                match.useCount += 1
                match.lastUsedAt = .now
            } else {
                let food = FrequentFood(name: name, portion: item.portionText, nutrition: item.perPortion)
                byName[key] = food
                context.insert(food)
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

    /// 落库照片：限制长边 1600pt 后以 JPEG 0.7 压缩，避免整张原图撑大 SwiftData 库。
    /// 已在采集端压缩过一次，这里再归一化上限，保证详情页足够清晰且体积可控。
    static func persistablePhoto(_ data: Data?) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let imageToSave: UIImage
        if longest > maxSide {
            let scale = maxSide / longest
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            imageToSave = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        } else {
            imageToSave = image
        }
        return imageToSave.jpegData(compressionQuality: 0.7)
    }

    // MARK: - 识别记录（独立页面）

    /// 识别记录从主页面移出，改为右上角「识别记录」按钮点击后弹出的独立页面，
    /// 自带 @Query 保持实时刷新，支持逐条删除（同时清理健康 App 内对应样本）。
    /// 识别记录列表也供行动页「饮食」卡片直接打开，因此不再私有。
    struct MealRecordsListView: View {
        /// 页面外部当前选择的日期：列表只展示这一天的记录，日期变化时同步刷新。
        let date: Date

        @Environment(\.modelContext) private var context
        @Environment(\.dismiss) private var dismiss
        /// 详情中的记录：整卡点击进入详情页（图片 / 食材 / 营养 / 评分）。
        @State private var detailRecord: ActionCheckIn?
        /// 编辑中的记录；编辑页直接修改该 SwiftData 实例并保存，列表 @Query 自动刷新。
        /// 用 item 驱动 sheet，避免「布尔开关 + 可选记录」两个状态在呈现时序上不同步、弹出空 sheet。
        @State private var editingRecord: ActionCheckIn?

        @Query(
            filter: #Predicate<ActionCheckIn> { $0.kindRaw == "meal" || $0.kindRaw == "caffeine" },
            sort: \ActionCheckIn.createdAt,
            order: .reverse
        ) private var dietRecords: [ActionCheckIn]

        /// 外部选中日期对应的 DayKey，作为唯一的过滤依据。
        private var selectedDayKey: String { DayKey.key(for: date) }

        /// 只看选中当天的记录（最新在前）；@Query 仍拉全量，供规律评分取近 7 天数据。
        private var dayRecords: [ActionCheckIn] {
            dietRecords.filter { DayKey.key(for: $0.createdAt) == selectedDayKey }
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    if let group = dayGroup {
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
                                        detailRecord = record
                                    }
                                }
                            }
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 36))
                                .foregroundStyle(AppPalette.green.opacity(0.8))
                            Text("这一天还没有饮食记录")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text("切换到有记录的日期，或识别 / 记录咖啡饮品后再来查看。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                }
                .background(AppScreenBackground(tone: .mint))
                .navigationTitle("饮食记录")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $detailRecord) { record in
                    MealRecordDetailView(record: record)
                }
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

        /// 只构造外部选中日期这一天的分组：无记录时返回 nil，列表走空态。
        /// 规律评分的 entries 仍取全量近 7 天数据，保证「近 7 天稳定性」不因只看当天而失真。
        private var dayGroup: DayGroup? {
            let calendar = Calendar.current
            let records = dayRecords.sorted { $0.createdAt > $1.createdAt }
            guard !records.isEmpty else { return nil }
            // 规律饮食只统计 meal 打卡；咖啡因饮品没有 mealSlot，天然被排除。
            let entries = dietRecords.compactMap { check -> MealEntry? in
                guard let slot = check.mealSlot else { return nil }
                return MealEntry(
                    id: check.ensureSyncID(), date: check.createdAt, slot: slot,
                    nutrition: check.nutrition, score: check.mealScore
                )
            }
            let targetDate = DayKey.startOfDay(date, calendar: calendar)
            let regularity = MealScoringEngine.regularity(entries: entries, on: targetDate, calendar: calendar)
            let title = DayKey.key(for: .now, calendar: calendar) == selectedDayKey
                ? "今天 · \(Self.dayFormatter.string(from: targetDate))"
                : Self.dayFormatter.string(from: targetDate)
            return DayGroup(key: selectedDayKey, title: title, records: records, regularity: regularity)
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
    /// 是否展示「勾选后写入营养库」：本地营养库匹配 / 营养库补充的行本身已在库里，不再展示。
    var showsLibrarySave: Bool = true
    /// 是否把这一行手动保存到「常用饮食」营养库；由父视图按食物 id 绑定，默认未勾选。
    @Binding var saveToLibrary: Bool
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
            if showsLibrarySave {
                HStack(spacing: 8) {
                    Button {
                        saveToLibrary.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: saveToLibrary ? "checkmark.square.fill" : "square")
                                .foregroundStyle(saveToLibrary ? AppPalette.greenDeep : Color(.secondaryLabel))
                            Text("保存")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppPalette.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存")
                    .accessibilityValue(saveToLibrary ? "已勾选" : "未勾选")
                    Text("勾选后写入营养库")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
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
    /// 点击整卡进入详情页（图片 / 食材清单 / 营养 / 评分）。
    var onTap: () -> Void = {}

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

    /// 备注按「用户描述；食物清单」拆开：标题只留核心记录名称，用户描述降级为下方弱化小字。
    private var titleAndRemark: (title: String, remark: String?) {
        MealNoteParts.splitTitleAndRemark(record.note)
    }

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
                let split = titleAndRemark
                if !split.title.isEmpty {
                    Text(split.title)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                }
                if let remark = split.remark {
                    Text(remark)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
                // 详情入口指示：整卡可点，chevron 只是视觉提示，点击同样进详情。
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 32)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// 补充食材面板：给识别结果 / 编辑页的现有食材清单追加遗漏项。
/// 三个来源：① 从本地营养库（常用 / 我的食物 / 预置分组）多选；② 拍照后 AI 识别追加；③ 手动新增空白项。
/// 只产出选中的 `[MealItem]` 通过 `onAdd` 回传，不直接改调用方的清单，便于多处复用。
private struct IngredientSupplementSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 补充来源分段。
    private enum Source: String, CaseIterable {
        case library = "营养库"
        case photo = "拍照识别"
        case manual = "手动添加"
    }

    /// 把补充结果交给调用方追加到现有 items；第二个参数标记这批食物是否直接取自营养库。
    let onAdd: ([MealItem], Bool) -> Void

    @Query(sort: \FrequentFood.lastUsedAt, order: .reverse) private var frequentFoods: [FrequentFood]
    @Query(sort: \CustomFood.name, order: .forward) private var customFoods: [CustomFood]

    @State private var source: Source = .library
    @State private var searchText = ""
    /// 营养库里勾选待补的食物 id。
    @State private var selectedIDs: Set<String> = []

    // 拍照识别来源
    @State private var photoDatas: [Data] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showSourcePicker = false
    @State private var showPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var pickerSource: CameraImagePicker.Source = .camera
    @State private var photoDescription = ""
    @State private var isRecognizing = false
    @State private var recognizeMessage: String?
    @State private var recognizedItems: [MealItem] = []

    /// 营养库可选食物：内置 + 自定义 + 常用（去重），与识别服务口径一致。
    private var libraryFoods: [FoodItem] {
        let custom = customFoods.map(\.foodItem)
        let known = Set((FoodDatabase.all + custom).map { $0.name.lowercased() })
        let extraFrequent = frequentFoods.map(\.foodItem).filter { !known.contains($0.name.lowercased()) }
        return FoodDatabase.all + custom + extraFrequent
    }

    private var matchedFoods: [FoodItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return libraryFoods }
        return libraryFoods.filter {
            $0.name.lowercased().contains(q) || $0.keywords.contains { $0.lowercased().contains(q) }
        }
    }

    private var selectedFoods: [FoodItem] {
        libraryFoods.filter { selectedIDs.contains($0.id) }
    }

    private var canRecognize: Bool {
        !isRecognizing && (!photoDatas.isEmpty || !photoDescription.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Picker("补充来源", selection: $source) {
                ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.cardMargin)
            .padding(.bottom, 8)

            ScrollView {
                switch source {
                case .library: libraryPane
                case .photo: photoPane
                case .manual: manualPane
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppScreenBackground(tone: .mint))
        .presentationDetents([.large])
        .confirmationDialog("添加识别照片", isPresented: $showSourcePicker) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照") { pickerSource = .camera; showPicker = true }
            }
            Button("从相册选择（可多选）") { showPhotoLibraryPicker = true }
            Button("取消", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("取消").font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.ink2)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text("补充食材").font(.headline).foregroundStyle(AppPalette.ink)
            Spacer(minLength: 8)
            Button(action: confirmAdd) {
                Text(confirmTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(canConfirm ? AppPalette.greenDeep : AppPalette.ink4, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
        }
        .padding(.horizontal, AppTheme.cardMargin)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var confirmTitle: String {
        switch source {
        case .library: return selectedFoods.isEmpty ? "添加" : "添加 \(selectedFoods.count) 项"
        case .photo: return "补充识别结果"
        case .manual: return "新增空白项"
        }
    }

    private var canConfirm: Bool {
        switch source {
        case .library: return !selectedFoods.isEmpty
        case .photo: return false // 拍照来源需先识别，结果区自带「添加识别结果」按钮。
        case .manual: return true
        }
    }

    private func confirmAdd() {
        switch source {
        case .library:
            onAdd(selectedFoods.map { Self.mealItem(from: $0) }, true)
            dismiss()
        case .photo:
            break
        case .manual:
            onAdd([MealItem(name: "", portionAmount: 100, portionUnit: "g", perPortion: .zero)], false)
            dismiss()
        }
    }

    /// FoodItem → MealItem：份量解析成数值 + 单位，营养按该份量记。
    static func mealItem(from food: FoodItem) -> MealItem {
        let portion = FoodDatabase.parsePortion(from: food.portion)
        return MealItem(
            name: food.name,
            portionAmount: portion.amount,
            portionUnit: portion.unit,
            perPortion: food.nutrition,
            imageURL: food.imageURL
        )
    }

    // MARK: - 营养库来源

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索食物名称或关键词", text: $searchText)
                .font(.subheadline)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if matchedFoods.isEmpty {
                Text("营养库没有匹配的食物，可切到「手动添加」自己录入。")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(matchedFoods) { food in
                        Button {
                            if selectedIDs.contains(food.id) { selectedIDs.remove(food.id) }
                            else { selectedIDs.insert(food.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedIDs.contains(food.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(selectedIDs.contains(food.id) ? AppPalette.greenDeep : AppPalette.ink4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.ink)
                                    Text("\(food.portion) · \(Int(food.nutrition.energyKcal.rounded())) 千卡")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppTheme.cardMargin)
    }

    // MARK: - 拍照识别来源

    private var photoPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("拍下要补充的食物，识别结果会追加到现有食材清单，不影响已有项。")
                .font(.caption).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(photoDatas.indices, id: \.self) { index in
                    if let uiImage = UIImage(data: photoDatas[index]) {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(width: 104, height: 104).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { photoDatas.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 19))
                                        .foregroundStyle(.white).shadow(radius: 2)
                                }.buttonStyle(.plain).padding(5)
                            }
                    }
                }
                Button { showSourcePicker = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                        Text(photoDatas.isEmpty ? "添加照片" : "继续添加").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(AppPalette.greenDeep).frame(width: 104, height: 104)
                    .background(AppPalette.greenSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            TextField("补充描述（可选，如：一杯拿铁）", text: $photoDescription, axis: .vertical)
                .font(.subheadline).padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .lineLimit(1...3)

            Button {
                Task { await recognize() }
            } label: {
                HStack(spacing: 8) {
                    if isRecognizing { ProgressView() } else { Image(systemName: "sparkles") }
                    Text(isRecognizing ? "识别中…" : "识别照片")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(canRecognize ? AppPalette.greenDeep : AppPalette.ink4,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain).disabled(!canRecognize)

            if let recognizeMessage {
                Text(recognizeMessage).font(.footnote).foregroundStyle(.orange)
            }

            if !recognizedItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("识别到 \(recognizedItems.count) 样，可删掉不需要的再补充：")
                        .font(.caption.weight(.medium)).foregroundStyle(AppPalette.ink)
                    ForEach(recognizedItems.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Image(systemName: "fork.knife").font(.caption).foregroundStyle(AppPalette.greenDeep)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(recognizedItems[index].name.isEmpty ? "未命名食物" : recognizedItems[index].name)
                                    .font(.subheadline).foregroundStyle(AppPalette.ink)
                                Text(recognizedItems[index].portionText)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { recognizedItems.remove(at: index) } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Button {
                        onAdd(recognizedItems, false)
                        dismiss()
                    } label: {
                        Text("补充这 \(recognizedItems.count) 样").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(AppPalette.greenDeep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.cardMargin)
        .sheet(isPresented: $showPicker) {
            CameraImagePicker(source: pickerSource) { picked in
                if let data = picked.jpegData(compressionQuality: 0.7) { photoDatas.append(data) }
            }
        }
        .photosPicker(isPresented: $showPhotoLibraryPicker, selection: $photoItems, maxSelectionCount: 9, matching: .images)
        .onChange(of: photoItems) { _, items in
            Task { @MainActor in
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = image.jpegData(compressionQuality: 0.7) {
                        photoDatas.append(jpeg)
                    }
                }
                photoItems = []
            }
        }
    }

    private func recognize() async {
        guard canRecognize else { return }
        isRecognizing = true
        recognizeMessage = nil
        recognizedItems = []
        defer { isRecognizing = false }
        do {
            let custom = customFoods.map(\.foodItem)
            let known = Set((FoodDatabase.all + custom).map { $0.name.lowercased() })
            let extraFrequent = frequentFoods.map(\.foodItem).filter { !known.contains($0.name.lowercased()) }
            let result = try await FoodRecognitionService.recognize(
                images: photoDatas,
                description: photoDescription,
                custom: custom + extraFrequent
            )
            recognizedItems = result.items
            if result.items.isEmpty {
                recognizeMessage = "没有识别出食物，补充文字描述或改用营养库选择。"
            } else if let notice = result.notice {
                recognizeMessage = notice
            }
        } catch {
            recognizeMessage = "识别失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 手动来源

    private var manualPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新增一个空白食材项，补充后到食材清单里逐项填写名称、数量和营养。")
                .font(.caption).foregroundStyle(.secondary)
            Button(action: confirmAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("新增空白食材项")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.greenDeep)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(AppPalette.greenSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.cardMargin)
    }
}

/// 单条饮食记录详情页：照片 + 放大突出的本餐评分 + 食材清单（参考识别结果展示）+ 合计营养 + 备注。
/// 由记录卡点击进入，用自绘顶栏避免多层 NavigationStack 空白；点「编辑」再弹编辑页。
private struct MealRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    /// 直接持有 SwiftData 实例，编辑页保存后本页随 @Query / 实例刷新。
    let record: ActionCheckIn
    /// 编辑页用 item 驱动，避免布尔 + 可选记录时序不同步。
    @State private var editing = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    private var nutrition: IntakeNutrition { record.nutrition }
    private var items: [MealItem] { record.mealItemsForDisplay }
    private var isAI: Bool { record.recognitionSource == "ai" }
    private var sourceLabel: String { isAI ? "AI 识别" : "本地营养库匹配" }
    private var sourceTint: Color { isAI ? AppPalette.sky : AppPalette.greenDeep }

    /// 评分沿用列表 / 时间轴口径：优先用保存值，旧记录按营养与餐次重算。
    private var evaluation: MealEvaluation {
        let slot = record.mealSlot ?? .lunch
        let full = MealScoringEngine.evaluate(nutrition: nutrition, slot: slot, date: record.createdAt)
        if let stored = record.mealScore {
            return MealEvaluation(
                score: stored,
                isHealthy: stored >= ScoringConfig().mealHealthyThreshold && full.isHealthy,
                level: full.level,
                notes: full.notes
            )
        }
        return full
    }

    private var scoreTint: Color {
        evaluation.isHealthy
            ? AppPalette.greenDeep
            : (evaluation.score >= ScoringConfig().mealFairThreshold ? AppPalette.orange : AppPalette.red)
    }

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar
            ScrollView {
                VStack(spacing: 18) {
                    photoSection
                    scoreHero
                    metaSection
                    ingredientsSection
                    totalSection
                    remarkSection
                }
                .padding(.horizontal, AppTheme.cardMargin)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppScreenBackground(tone: .mint))
        .presentationDetents([.large])
        .sheet(isPresented: $editing) {
            MealRecordEditor(record: record)
        }
    }

    /// 顶栏：完成 / 标题 / 编辑。
    private var detailToolbar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text("饮食详情")
                .font(.headline)
                .foregroundStyle(AppPalette.ink)
            Spacer(minLength: 8)
            Button {
                editing = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("编辑")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppPalette.greenDeep, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.cardMargin)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    /// 食物照片：多张横向分页展示（可左右滑动），兼容旧的单张记录；无图给弱占位。
    private var photoSection: some View {
        let photos = record.displayPhotos.compactMap { UIImage(data: $0) }
        return Group {
            if photos.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(AppPalette.greenDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("这条记录没有照片")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppPalette.ink)
                        Text("文字识别或早期记录不含图片，可在编辑中补充说明。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AppPalette.greenSoft.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                TabView {
                    ForEach(photos.indices, id: \.self) { index in
                        Image(uiImage: photos[index])
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            }
        }
    }

    /// 本餐评分：大字号 + 着色 + 胶囊等级，作为详情最突出的信息块。
    private var scoreHero: some View {
        VStack(spacing: 10) {
            HStack {
                Label("本餐评分", systemImage: "heart.text.square.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.mealSlot?.title ?? "餐次未定")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppPalette.greenSoft)
                    .foregroundStyle(AppPalette.greenDeep)
                    .clipShape(Capsule())
            }
            .foregroundStyle(scoreTint)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(evaluation.score.rounded()))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreTint)
                Text("/ 100")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(evaluation.isHealthy ? "健康" : evaluation.level)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(scoreTint.opacity(0.14))
                    .foregroundStyle(scoreTint)
                    .clipShape(Capsule())
            }
            if !evaluation.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(evaluation.notes, id: \.self) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(scoreTint.opacity(0.6)).frame(width: 5, height: 5)
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            Text("参考该餐次建议摄入量与用餐时段评估，为经验值，非医学建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appCard(padding: 18)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "记录信息", icon: "info.circle.fill", tint: AppPalette.lav)
            HStack {
                Text("用餐时间").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(Self.dateFormatter.string(from: record.createdAt))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(AppPalette.ink)
            }
            HStack {
                Text("识别来源").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(sourceLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(sourceTint.opacity(0.12))
                    .foregroundStyle(sourceTint)
                    .clipShape(Capsule())
            }
        }
        .appCard(padding: 18)
    }

    /// 食材清单：结构参考 AI 识别后的列表（图标 + 名称 + 数量 + 该样营养摘要），只读展示。
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "食材清单（\(items.count) 样）",
                icon: "list.bullet.rectangle.portrait.fill",
                tint: AppPalette.greenDeep
            )
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    FoodRemoteIcon(imageURL: item.imageURL)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name.isEmpty ? "未命名食材" : item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.ink)
                        Text("数量 \(MealItem.formatAmount(item.portionAmount))\(item.portionUnit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(item.perPortion.energyKcal.rounded())) 千卡 · 碳水 \(MealItem.formatAmount(item.perPortion.carbsG))g · 蛋白 \(MealItem.formatAmount(item.perPortion.proteinG))g · 脂肪 \(MealItem.formatAmount(item.perPortion.fatG))g")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            Text("完整营养值可在编辑中逐项查看与修正。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    /// 合计营养：与识别结果区一致的营养小卡网格。
    private var totalSection: some View {
        let t = nutrition
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
            AppSectionHeader(title: "合计营养", icon: "chart.bar.fill", tint: AppPalette.lav)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(stats, id: \.unit) { stat in
                    NutrientStat(icon: stat.icon, value: stat.value, unit: stat.unit, tint: stat.tint)
                }
            }
            Text("按苹果健康「营养摄入」\(NutritionField.allCases.count) 项留档，未记录项记 0。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 18)
    }

    /// 备注：拆分后的用户描述弱化展示，没有则不占空间。
    @ViewBuilder
    private var remarkSection: some View {
        let split = MealNoteParts.splitTitleAndRemark(record.note)
        if let remark = split.remark {
            VStack(alignment: .leading, spacing: 8) {
                AppSectionHeader(title: "备注", icon: "text.bubble.fill", tint: AppPalette.lav)
                Text(remark)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(padding: 18)
        }
    }
}

/// 识别记录编辑页：修改餐次 / 用餐时间 / 食物名称与数量（数字 + 单位）/ 本餐营养，
/// 保存后写回本地 ActionCheckIn，并复用「识别保存」的同一条回写链路（MealCheckInSync.push）
/// 把 9 类样本（7 类膳食 + 水 + 咖啡因）同步到健康 App（值变化时健康 App 侧样本会按 syncID 重写）。
private struct MealRecordEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// 直接持有 SwiftData 实例，编辑即改其属性，保存后 @Query 列表自动刷新。
    let record: ActionCheckIn

    @State private var slot: MealSlot
    @State private var mealTime: Date
    /// 食材清单：所有记录（含旧记录）统一按「每样食物」编辑，可在识别结果上补充遗漏项或修正。
    /// 旧记录无分项数据时由 `mealItemsForDisplay` 生成占位项，保存后即升级为正式分项数据。
    @State private var items: [MealItem]
    @State private var saving = false
    /// 展开「单项营养」编辑的食物 id。
    @State private var expandedItemID: String?
    /// 校验提示（如某样食物没填名称 / 数量）。
    @State private var validationMessage: String?
    /// 补充食材面板：营养库 / 拍照识别 / 手动，追加到当前食材清单。
    @State private var showSupplement = false

    init(record: ActionCheckIn) {
        self.record = record
        _slot = State(initialValue: record.mealSlot ?? .lunch)
        _mealTime = State(initialValue: record.createdAt)
        _items = State(initialValue: record.mealItemsForDisplay.map(\.normalizedForEditing))
    }

    /// 本餐营养：由各样食物营养实时合计。
    private var effectiveNutrition: IntakeNutrition {
        items.reduce(.zero) { $0 + $1.perPortion }
    }

    /// 评分随餐次 / 时间 / 营养实时变化，编辑时即时预览。
    private var evaluation: MealEvaluation {
        MealScoringEngine.evaluate(nutrition: effectiveNutrition, slot: slot, date: mealTime)
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
                    itemsSection
                    summarySection
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
                    showSupplement = true
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
        .sheet(isPresented: $showSupplement) {
            IngredientSupplementSheet { added, _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    // 编辑页补充的饮品同样补水 / 咖啡因，保存时随整餐汇总一起回写。
                    items.append(contentsOf: DrinkIntakeEstimator.applying(to: added))
                }
            }
        }
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

    /// 重拼备注：保留原记录里的用户描述（「描述；食物清单」的前半段），
    /// 把食物清单换成编辑后的名称 + 数量，避免改一次食材就把原始描述冲掉。
    private func composedNoteKeepingDescription() -> String? {
        let itemText = MealNoteParts.compose(items)
        let remark = MealNoteParts.splitTitleAndRemark(record.note).remark
        switch (remark, itemText) {
        case (let remark?, let item?): return remark + "；" + item
        case (let remark?, nil): return remark
        case (nil, let item?): return item
        case (nil, nil): return nil
        }
    }

    private func saveEdit() {
        validationMessage = nil
        // 每样食物必须有名称和大于 0 的克 / 毫升数量，否则不允许落库。
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
        // 保存前再补一次饮品水量 / 咖啡因：编辑页新增或改过份量的饮品要带上这两项，
        // 它们会随整餐一起写回健康 App（水、咖啡因各一条样本）。
        items = DrinkIntakeEstimator.applying(to: cleaned)
        let total = effectiveNutrition
        let note = composedNoteKeepingDescription()
        saving = true
        // 旧记录可能缺 syncID：先补齐并在 save 时持久化，保证健康 App 回写能定位到同一条样本。
        _ = record.ensureSyncID()
        record.note = note
        record.nutritionJSON = (try? JSONEncoder().encode(total))
            .flatMap { String(data: $0, encoding: .utf8) }
        // 统一落库为食材清单：编辑后详情 / 再次编辑都按逐样数据展示（含由旧记录升级而来的项）。
        record.setMealItems(items)
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
