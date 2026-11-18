import Foundation

/// 食物识别服务：按设置走「AI 识别」或「本地营养库匹配」，统一产出可编辑的营养结果。
///
/// - AI 识别：把照片（可选）与文字描述发给「设置 → AI 服务」里配置的视觉模型，
///   解析回结构化的每样食物营养。
/// - 本地营养库匹配：关闭 AI 时，用本地营养库按名称 / 关键词匹配文字描述，回填营养。
enum FoodRecognitionService {
    /// 给视觉模型的系统提示：只输出一个 JSON 对象，字段覆盖苹果健康「营养摄入」全部 40 项。
    /// 模板与单位说明都由 NutritionField 单一数据源生成，避免漏项 / 单位写错。
    static let systemPrompt = """
    你是一个食物营养识别助手。用户会提供一张食物照片（可能没有）和/或一句文字描述。
    请识别其中的食物，并估算每一项的营养成分。只依据可见/描述的内容，不要编造。
    用简体中文输出一个 JSON 对象（不要 Markdown 代码块），结构严格如下：
    \(NutritionField.aiJSONTemplate)
    每一项食物都必须包含上面全部 \(NutritionField.allCases.count) 个数值字段；无法判断、
    或该食物不含某项时一律填 0，禁止省略字段、写 null 或写字符串。
    字段单位：\(NutritionField.aiUnitDescription)。数值均为该份量（portion）的含量。
    portion 只写「数字 + 实际单位」，单位按食物实际形态来：固体用 g（如 150g、300g）、饮品用 ml（如 330ml、500ml）、大瓶装可用 L；不要写「1 碗」「1 份」这类数量词，也不要把 ml 写成 g。
    若没有任何可识别食物，返回 {"items":[]}。
    """

    /// 统一入口：根据开关决定走 AI 还是本地匹配。
    /// - parameter custom: 用户自定义 / 分组 / 常用食物（来自本地营养库）。AI 模式下用于「本地优先校准」，
    ///   本地匹配模式下用于文字匹配。
    static func recognize(image: Data?, description: String, custom: [FoodItem] = []) async throws -> RecognizedMeal {
        if FoodRecognitionSettings.isAIEnabled {
            return try await recognizeWithAI(image: image, description: description, custom: custom)
        }
        return recognizeLocal(text: description, custom: custom)
    }

    /// 本地营养库匹配：内置库 + 用户自定义食物一起按文字匹配。拍照在此模式下只作参考，不参与识别。
    static func recognizeLocal(text: String, custom: [FoodItem] = []) -> RecognizedMeal {
        let items = FoodDatabase.match(text, custom: custom).map { food -> MealItem in
            let portion = FoodDatabase.parsePortion(from: food.portion)
            return MealItem(
                name: food.name,
                portionAmount: portion.amount,
                portionUnit: portion.unit,
                perPortion: food.nutrition,
                imageURL: food.imageURL
            )
        }
        return RecognizedMeal(items: items, source: .local, rawDescription: text)
    }

    /// AI 识别：调用配置好的视觉模型。
    /// - parameter custom: 本地营养库（自定义 / 分组 / 常用）。识别完成后，凡能在本地库按名称/关键词命中的食物，
    ///   其营养与份量一律以本地库为准（本地优先），保证用户维护数据的权威性。
    static func recognizeWithAI(image: Data?, description: String, custom: [FoodItem] = []) async throws -> RecognizedMeal {
        let settings = LLMSettingsStore.load()
        guard let key = KeychainStore().read(account: settings.provider.rawValue), !key.isEmpty else {
            throw FoodRecognitionError.noAPIKey
        }
        let configuration = LLMClient.Configuration(
            baseURL: settings.baseURL,
            model: settings.model,
            apiKey: key,
            provider: settings.provider
        )
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        // 纯文本模型（如 deepseek-v4-pro）不接受多模态 content，
        // 有文字描述时降级为纯文字估算，只有照片时明确报错，避免发出必然失败的请求。
        let supportsVision = LLMClient.supportsVision(configuration)
        let usableImage = supportsVision ? image : nil
        if image != nil, !supportsVision, trimmedDescription.isEmpty {
            throw FoodRecognitionError.notSupported
        }
        let notice = (image != nil && !supportsVision)
            ? "当前模型（\(settings.model)）不支持图片输入，本次仅按文字描述估算。"
            : nil

        let userText: String
        switch (usableImage, trimmedDescription.isEmpty) {
        case (.some, true):
            userText = "请识别这张图片中的食物并估算营养成分。"
        case (.some, false):
            userText = "请根据图片和文字描述识别食物并估算营养成分。用户描述：\(trimmedDescription)"
        case (.none, _):
            userText = trimmedDescription.isEmpty
                ? "请识别这张图片中的食物并估算营养成分。"
                : "请根据文字描述识别食物并估算营养成分。用户描述：\(trimmedDescription)"
        }

        let content = try await LLMClient().analyzeFood(
            configuration: configuration,
            system: systemPrompt,
            userText: userText,
            images: usableImage.map { [$0] } ?? [],
            maxTokens: 3000
        )
        let items = try parseAIResponse(content)
        // 本地营养库优先：命中的食物以本地数据校准（营养 + 份量）。
        let (calibrated, overridden) = FoodRecognitionService.applyLocalAuthority(to: items, custom: custom)
        var finalNotice = notice
        if overridden > 0 {
            let msg = "已用本地营养库校准 \(overridden) 项食物的营养数据。"
            finalNotice = finalNotice.map { $0 + " " + msg } ?? msg
        }
        return RecognizedMeal(
            items: calibrated,
            source: .ai,
            rawDescription: description,
            notice: finalNotice
        )
    }

    /// AI 识别后，用本地营养库（内置 + 自定义/分组/常用）校准：若某样食物在本地库能按名称/关键词命中，
    /// 则该项营养与份量一律以本地库为准（本地优先，保证用户维护的数据权威性）。
    /// 返回校准后的条目与命中数量。纯函数，便于单测。
    static func applyLocalAuthority(to items: [MealItem], custom: [FoodItem]) -> (items: [MealItem], overridden: Int) {
        var overridden = 0
        let result = items.map { item -> MealItem in
            guard let hit = localHit(for: item.name, custom: custom) else { return item }
            overridden += 1
            let portion = FoodDatabase.parsePortion(from: hit.portion)
            return MealItem(
                name: hit.name,
                portionAmount: portion.amount,
                portionUnit: portion.unit,
                perPortion: hit.nutrition,
                imageURL: hit.imageURL
            )
        }
        return (result, overridden)
    }

    /// 在本地库中按名称/关键词查找与 query 最匹配的 FoodItem：优先用户自定义/分组，其次内置库。
    /// 同一来源内取「命中片段最长」的一条：营养库里同时存在「拿铁」和「生椰拿铁」等
    /// 互相包含的名称时，避免因为 SwiftData 查询顺序不确定而误校准成短名称那条。
    private static func localHit(for name: String, custom: [FoodItem]) -> FoodItem? {
        let lowered = name.lowercased()
        func matchLength(_ food: FoodItem) -> Int {
            var best = 0
            let itemName = food.name.lowercased()
            if !itemName.isEmpty, lowered.contains(itemName) { best = itemName.count }
            for keyword in food.keywords where !keyword.isEmpty {
                let key = keyword.lowercased()
                if lowered.contains(key) { best = max(best, key.count) }
            }
            return best
        }
        if let hit = custom.filter({ matchLength($0) > 0 })
            .max(by: { matchLength($0) < matchLength($1) }) { return hit }
        return nil
    }

    /// 把模型返回的 JSON 解析成可编辑的 MealItem 列表；容错去除可能的 ```json 包裹。
    /// internal 而非 private：单测要直接验证「40 项指标缺失即 0」的容错行为。
    static func parseAIResponse(_ content: String) throws -> [MealItem] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonText = String(trimmed[start...end])
        } else {
            throw FoodRecognitionError.invalidResponse
        }

        struct Payload: Decodable {
            struct Item: Decodable {
                let name: String
                let portion: String?
                /// 苹果健康营养摄入全指标；缺失 / 类型不符的字段按 0 处理，不会让整条结果解析失败。
                let nutrition: IntakeNutrition

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: NutritionCodingKey.self)
                    name = (try? container.decode(String.self, forKey: NutritionCodingKey("name"))) ?? "未命名食物"
                    portion = try? container.decode(String.self, forKey: NutritionCodingKey("portion"))
                    var values = IntakeNutrition()
                    for field in NutritionField.allCases {
                        let key = NutritionCodingKey(field.jsonKey)
                        if let number = try? container.decode(Double.self, forKey: key) {
                            values[field] = number
                        } else if let text = try? container.decode(String.self, forKey: key),
                                  let number = Double(text.trimmingCharacters(in: .whitespaces)) {
                            // 部分模型会把数值包成字符串，能解析就按数值收下。
                            values[field] = number
                        } else {
                            values[field] = 0
                        }
                    }
                    nutrition = values
                }
            }
            let items: [Item]
        }

        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw FoodRecognitionError.invalidResponse
        }

        return payload.items.map { item -> MealItem in
            let portion = FoodDatabase.parsePortion(from: item.portion ?? "100g")
            return MealItem(
                name: item.name,
                portionAmount: portion.amount,
                portionUnit: portion.unit,
                perPortion: item.nutrition
            )
        }
    }
}
