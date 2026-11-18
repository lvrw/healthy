import Foundation

struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    enum Status: String, Codable, Sendable {
        /// 旧版本留下的等待态，UI 与 .thinking 同等对待。
        case pending
        /// 已发出请求、还没拿到第一句正式回答。
        case thinking
        /// 正在逐句输出，content 为当前已累积的内容。
        case streaming
        case success
        case failed
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date
    var status: Status = .success
    var errorKind: String? = nil
    var liked: Bool? = nil
}

enum ChatPromptBuilder {
    static let systemPrompt = """
    你是一名严谨的日常健康数据分析助手。你会收到一个人当天的 Apple Watch 聚合指标、28 天个人基线与本地算法算出的身体状态分 / 压力分，以及一段对话历史。只依据给出的数据回答问题，不提供医疗诊断、不推荐药物、不编造缺失数据；数据里没有的信息就直说不知道。血压或血糖明显异常时，只提示建议关注、必要时咨询医生。若数据里的 dayContext.isPartialDay 为 true，说明今天尚未结束：饮水、饮食、步数、运动、日照、正念都是只在清醒 / 日光时段增长的累计量，睡眠期间不会增长，只能与 stageTargets 中的阶段目标比较，不得用全天目标判定「今日偏低 / 不足 / 未达标」。回答用简体中文，口语化、简短（一般不超过 150 字），可以用 Markdown 列表。
    """

    static func dataMessage(payloadJSON: String) -> String {
        "以下是我今天的健康数据（JSON），请回答后续问题时只依据它：\n\(payloadJSON)"
    }

    /// 推荐问题按 dayKey 字节和稳定选取，跨启动确定，同一天始终两条且不同。
    static func recommendedQuestions(dayKey: String) -> [String] {
        let pool = [
            "我今天的精神状态适合做高强度运动吗？",
            "我的睡眠哪里最需要改进？",
            "最近压力偏高的可能原因有哪些？",
            "我的 HRV 和静息心率说明了什么？",
            "今天可以做点什么让自己恢复得快一些？",
            "和数据相比，我今天的活动量算多吗？",
        ]
        let sum = dayKey.utf8.reduce(into: 0) { $0 = ($0 + Int($1)) % 997 }
        let index = sum % pool.count
        return [pool[index], pool[(index + 1) % pool.count]]
    }

    static func trimmedHistory(_ messages: [ChatMessage], maxMessages: Int = 12) -> [ChatMessage] {
        let usable = messages.filter { $0.status == .success }
        guard maxMessages > 0 else { return [] }
        return Array(usable.suffix(maxMessages))
    }

    static func requestMessages(
        payloadJSON: String?,
        history: [ChatMessage],
        question: String
    ) -> [LLMClient.ChatMessage] {
        var result: [LLMClient.ChatMessage] = [
            LLMClient.ChatMessage(role: "system", content: systemPrompt)
        ]
        if let payloadJSON {
            result.append(LLMClient.ChatMessage(role: "user", content: dataMessage(payloadJSON: payloadJSON)))
        }
        for message in trimmedHistory(history) {
            result.append(LLMClient.ChatMessage(role: message.role.rawValue, content: message.content))
        }
        result.append(LLMClient.ChatMessage(role: "user", content: question))
        return result
    }
}

// configured by qoder