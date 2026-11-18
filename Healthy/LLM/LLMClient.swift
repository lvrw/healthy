import Foundation

enum LLMErrorKind: String, Sendable, Codable {
    case notConfigured
    case invalidURL
    case invalidRequest
    case unauthorized
    case notFound
    case rateLimited
    case server
    case timeout
    case offline
    case decoding
    case empty
    case insufficientData
    case cancelled
    case unknown
}

struct LLMError: LocalizedError, Sendable {
    let kind: LLMErrorKind
    let message: String

    var errorDescription: String? { message }
}

actor LLMClient {
    struct ChatMessage: Sendable {
        let role: String
        let content: String
    }

    struct Configuration: Sendable {
        var baseURL: String
        var model: String
        var apiKey: String
        var provider: LLMProviderID = .custom
    }

    struct TestResult: Sendable {
        var latency: TimeInterval
        var model: String
        var reply: String
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    func testConnection(configuration: Configuration) async throws -> TestResult {
        let started = Date()
        let reply = try await complete(
            configuration: configuration,
            messages: [ChatMessage(role: "user", content: "请只回复 OK")],
            // DeepSeek 等模型的思考模式会先消耗 token 预算，8 个 token 时正式回答会被挤空
            maxTokens: 32,
            jsonMode: false
        )
        return TestResult(
            latency: Date().timeIntervalSince(started),
            model: configuration.model,
            reply: reply
        )
    }

    func complete(
        configuration: Configuration,
        messages: [ChatMessage],
        maxTokens: Int,
        jsonMode: Bool
    ) async throws -> String {
        let chatMessages = messages.map { Message(role: $0.role, content: $0.content) }
        do {
            return try await send(
                configuration: configuration,
                body: makeBody(
                    configuration: configuration,
                    messages: chatMessages,
                    maxTokens: maxTokens,
                    jsonMode: jsonMode
                )
            )
        } catch let error as LLMError where jsonMode && error.kind == .invalidRequest {
            return try await send(
                configuration: configuration,
                body: makeBody(
                    configuration: configuration,
                    messages: chatMessages,
                    maxTokens: maxTokens,
                    jsonMode: false
                )
            )
        }
    }

    private func makeBody(
        configuration: Configuration,
        messages: [Message],
        maxTokens: Int,
        jsonMode: Bool,
        stream: Bool = false
    ) -> ChatRequest {
        ChatRequest(
            model: configuration.model,
            messages: messages,
            temperature: 0.3,
            max_tokens: maxTokens,
            response_format: jsonMode ? ResponseFormat(type: "json_object") : nil,
            thinking: Self.thinkingControl(configuration),
            stream: stream ? true : nil
        )
    }

    private func makeRequest(
        configuration: Configuration,
        body: some Encodable,
        acceptsStream: Bool = false
    ) throws -> URLRequest {
        try makeRequest(
            configuration: configuration,
            bodyData: try JSONEncoder().encode(body),
            acceptsStream: acceptsStream
        )
    }

    private func makeRequest(
        configuration: Configuration,
        bodyData: Data,
        acceptsStream: Bool = false
    ) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        if acceptsStream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.timeoutInterval = 120
        request.httpBody = bodyData
        return request
    }

    /// DeepSeek V4 系列默认开启思考模式（effort 默认 high），推理内容同样计入 max_tokens。
    /// 小预算请求会被推理占满、只返回空的 content，因此显式关闭思考模式。
    private static func thinkingControl(_ configuration: Configuration) -> ThinkingControl? {
        let isDeepSeek = configuration.provider == .deepSeek
            || configuration.baseURL.lowercased().contains("deepseek")
        return isDeepSeek ? ThinkingControl(type: "disabled") : nil
    }

    /// 当前配置的模型是否接受图片输入。
    /// DeepSeek 的 `deepseek-flash` 原生支持图片（Chat Completions 的 content 片段数组），
    /// `deepseek-v4-pro` 等型号仍是纯文本；自定义服务商无法枚举能力，按模型名判断。
    static func supportsVision(_ configuration: Configuration) -> Bool {
        supportsVision(model: configuration.model)
    }

    /// 按模型名判断视觉能力，UI 侧（不持有 Key）也能直接调用。
    static func supportsVision(model: String) -> Bool {
        let name = model.lowercased()
        guard name.contains("deepseek") else { return true }
        return name.contains("flash") || name.contains("vision")
    }

    private func send(configuration: Configuration, body: some Encodable) async throws -> String {
        try await send(configuration: configuration, bodyData: try JSONEncoder().encode(body))
    }

    private func send(configuration: Configuration, bodyData: Data) async throws -> String {
        let request = try makeRequest(configuration: configuration, bodyData: bodyData)
        // 所有非流式 LLM 请求（对话 / 简报 / 食物识别）的耗时都汇聚在这里，
        // 统一记录模型名，便于在性能面板里区分是哪个模型慢。
        let perfToken = PerformanceTrace.shared.begin(
            "LLM 请求 · \(configuration.model)",
            category: .api,
            detail: "baseURL=\(configuration.baseURL)"
        )
        defer { PerformanceTrace.shared.end(perfToken) }
        let (data, _) = try await perform(request)
        return try LLMResponseParser.content(from: data)
    }

    /// OpenAI 兼容的 SSE 流式请求：逐块产出正式回答增量。
    /// 思考模型的 reasoning_content 不展示，只用来让 UI 停留在「深度思考中」。
    /// 服务端不支持 stream（返回普通 JSON）时不会产出任何块，调用方回退到 complete。
    func stream(
        configuration: Configuration,
        messages: [ChatMessage],
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        let request: URLRequest
        do {
            request = try makeRequest(
                configuration: configuration,
                body: makeBody(
                    configuration: configuration,
                    messages: messages.map { Message(role: $0.role, content: $0.content) },
                    maxTokens: maxTokens,
                    jsonMode: false,
                    stream: true
                ),
                acceptsStream: true
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let session = self.session
        let modelName = configuration.model
        return AsyncThrowingStream { continuation in
            let task = Task {
                // 两个独立埋点：首字节延迟（用户感知的「等多久才开始出字」）与整段总耗时。
                let totalToken = PerformanceTrace.shared.begin(
                    "LLM 流式 · \(modelName) · 总耗时", category: .api
                )
                let firstByteToken = PerformanceTrace.shared.begin(
                    "LLM 流式 · \(modelName) · 首字节", category: .api
                )
                var didRecordFirstByte = false
                defer {
                    PerformanceTrace.shared.end(totalToken)
                }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError(kind: .unknown, message: "无效的服务器响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        throw LLMClient.statusError(http.statusCode, body: bodyText)
                    }
                    var didYield = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        switch LLMStreamParser.parse(line: line) {
                        case .text(let delta):
                            if !didRecordFirstByte {
                                // 首个可见文本块到达：记录 TTFT，这是聊天页卡顿的关键指标。
                                PerformanceTrace.shared.end(firstByteToken)
                                didRecordFirstByte = true
                            }
                            didYield = true
                            continuation.yield(delta)
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            break
                        }
                    }
                    if !didYield {
                        // 对端可能忽略了 stream 参数直接返回整段 JSON。
                        throw LLMError(kind: .decoding, message: "服务端未返回流式数据")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// 多模态食物识别：把（可选的）照片与文字描述发给视觉模型，要求返回 JSON。
    /// 请求体必须符合 DeepSeek / OpenAI 兼容 schema：system 消息的 content 只能是字符串，
    /// 只有 user 消息可以用 content 片段数组（text 在前、image_url 在后）。
    func analyzeFood(
        configuration: Configuration,
        system: String,
        userText: String,
        images: [Data],
        maxTokens: Int
    ) async throws -> String {
        if !images.isEmpty, !LLMClient.supportsVision(configuration) {
            throw LLMError(
                kind: .invalidRequest,
                message: "当前模型（\(configuration.model)）不支持图片输入，请改用支持视觉的模型"
            )
        }
        let bodyData = try LLMClient.visionRequestBody(
            configuration: configuration,
            system: system,
            userText: userText,
            images: images,
            maxTokens: maxTokens
        )
        return try await send(configuration: configuration, bodyData: bodyData)
    }

    /// 构造视觉请求体（JSON Data）。抽成纯函数便于单测断言结构：
    /// system 的 content 必须是字符串、user 的 content 是片段数组（text 在前、image_url 在后），
    /// 否则 DeepSeek 会以 422 拒绝。
    static func visionRequestBody(
        configuration: Configuration,
        system: String,
        userText: String,
        images: [Data],
        maxTokens: Int
    ) throws -> Data {
        let userParts: [VisionContent] = [VisionContent.text(userText)] + images.map { VisionContent.image($0) }
        let messages: [VisionMessage] = [
            VisionMessage(role: "system", text: system),
            VisionMessage(role: "user", parts: userParts),
        ]
        let body = VisionRequest(
            model: configuration.model,
            messages: messages,
            temperature: 0.3,
            max_tokens: maxTokens,
            response_format: ResponseFormat(type: "json_object"),
            thinking: Self.thinkingControl(configuration),
            stream: nil
        )
        return try JSONEncoder().encode(body)
    }

    private func endpoint(_ baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            throw LLMError(kind: .invalidURL, message: "Base URL 不合法")
        }
        guard components.scheme?.lowercased() == "https" else {
            throw LLMError(kind: .invalidURL, message: "Base URL 必须使用 https")
        }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/chat/completions"
        guard let url = components.url else {
            throw LLMError(kind: .invalidURL, message: "Base URL 不合法")
        }
        return url
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var didRetry = false
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw LLMError(kind: .unknown, message: "无效的服务器响应")
                }
                if (200..<300).contains(http.statusCode) {
                    return (data, http)
                }
                if !didRetry, http.statusCode == 429 {
                    didRetry = true
                    try await Task.sleep(for: .milliseconds(700))
                    continue
                }
                throw LLMClient.statusError(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            } catch let error as LLMError {
                throw error
            } catch is CancellationError {
                throw LLMError(kind: .cancelled, message: "请求已取消")
            } catch let error as URLError {
                // 超时/连接中断时请求可能已在服务端完成并计费，重试会重复扣费
                if !didRetry, error.code == .cannotConnectToHost {
                    didRetry = true
                    try await Task.sleep(for: .milliseconds(700))
                    continue
                }
                throw urlError(error)
            } catch {
                throw LLMError(kind: .unknown, message: error.localizedDescription)
            }
        }
    }

    static func statusError(_ status: Int, body: String = "") -> LLMError {
        let detail = body.isEmpty ? "" : " · \(String(body.prefix(120)))"
        switch status {
        case 400:
            return LLMError(kind: .invalidRequest, message: "请求参数不被支持（400），请检查模型能力\(detail)")
        case 422:
            // 服务端参数校验失败：消息结构（system content 必须是字符串）、
            // 模型能力（是否支持图片 / JSON 模式）都可能落到这里
            return LLMError(kind: .invalidRequest, message: "请求参数校验失败（422），请检查模型是否支持图片与 JSON 模式\(detail)")
        case 401, 403:
            return LLMError(kind: .unauthorized, message: "API Key 无效或没有权限（\(status)）")
        case 404:
            return LLMError(kind: .notFound, message: "接口或模型不存在（404），请检查 Base URL 与模型名")
        case 429:
            return LLMError(kind: .rateLimited, message: "请求过于频繁（429），请稍后再试")
        case 500..<600:
            return LLMError(kind: .server, message: "服务端错误（\(status)）")
        default:
            return LLMError(kind: .unknown, message: "请求失败（\(status)）")
        }
    }

    private func urlError(_ error: URLError) -> LLMError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return LLMError(kind: .offline, message: "网络不可用，请检查连接")
        case .timedOut:
            return LLMError(kind: .timeout, message: "请求超时，请稍后重试")
        default:
            return LLMError(kind: .unknown, message: "网络错误：\(error.localizedDescription)")
        }
    }
}

private struct Message: Codable {
    let role: String
    let content: String
}

/// 多模态（视觉）消息的内容片段：文本或 base64 图片，对应 OpenAI 兼容的
/// `image_url` 格式。食材照片识别走这条链路。
private enum VisionContent: Encodable {
    case text(String)
    case image(Data)

    private enum Kind: String, Encodable {
        case text
        case imageURL = "image_url"
    }
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        // 必须显式映射：Swift 的 case 名是 imageURL，JSON 键必须是 image_url
        case imageURL = "image_url"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data):
            try container.encode(Kind.imageURL, forKey: .type)
            let base64 = data.base64EncodedString()
            // image_url 是对象：{url, detail}；detail 用 high 保证食物细节不被降采样
            try container.encode(
                ["url": "data:image/jpeg;base64,\(base64)", "detail": "high"],
                forKey: .imageURL
            )
        }
    }
}

/// 一条多模态消息。system 用字符串 content、user 用片段数组，
/// 两种形态在编码时分别处理，避免把 system 的 content 编成数组（服务端会 422）。
private struct VisionMessage: Encodable {
    let role: String
    private let text: String?
    private let parts: [VisionContent]?

    init(role: String, text: String) {
        self.role = role
        self.text = text
        self.parts = nil
    }

    init(role: String, parts: [VisionContent]) {
        self.role = role
        self.text = nil
        self.parts = parts
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let text {
            try container.encode(text, forKey: .content)
        } else {
            try container.encode(parts ?? [], forKey: .content)
        }
    }
}

private struct VisionRequest: Encodable {
    let model: String
    let messages: [VisionMessage]
    let temperature: Double
    let max_tokens: Int
    let response_format: ResponseFormat?
    let thinking: ThinkingControl?
    let stream: Bool?
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ThinkingControl: Encodable {
    let type: String
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
    let response_format: ResponseFormat?
    let thinking: ThinkingControl?
    /// 只有流式请求才带 stream=true；非流式保持旧请求体不变。
    let stream: Bool?
}

/// Chat Completions 响应。因需按 finish_reason / reasoning_content 区分“真空”与“思考占满预算”，
/// 结构与解析独立出来便于单测。
struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct ResponseMessage: Decodable {
            let content: String?
            let reasoning_content: String?
        }

        let message: ResponseMessage
        let finish_reason: String?
    }

    let choices: [Choice]
}

/// SSE 单行解析结果。
enum LLMStreamEvent: Equatable, Sendable {
    case text(String)
    case done
    case ignore
}

/// 解析 OpenAI 兼容的 `data: {...}` 行；心跳、usage-only 块、思考内容都忽略。
enum LLMStreamParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    static func parse(line: String) -> LLMStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" { return .done }
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let content = chunk.choices.first?.delta.content,
              !content.isEmpty
        else { return .ignore }
        return .text(content)
    }
}

enum LLMResponseParser {
    /// 从响应体取出正式回答，空内容时给出可定位的失败原因
    static func content(from data: Data) throws -> String {
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw LLMError(kind: .decoding, message: "无法解析模型响应")
        }
        guard let choice = decoded.choices.first else {
            throw LLMError(kind: .empty, message: "模型没有返回任何结果（choices 为空）")
        }
        let finish = choice.finish_reason ?? "unknown"
        let content = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !content.isEmpty {
            return content
        }
        let reasoning = choice.message.reasoning_content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reasoning.isEmpty {
            throw LLMError(
                kind: .empty,
                message: "模型只输出了思考内容，没有正式回答（finish_reason=\(finish)），token 预算可能被推理占满"
            )
        }
        switch finish {
        case "length":
            throw LLMError(kind: .empty, message: "输出被 max_tokens 截断（finish_reason=length）")
        case "content_filter":
            throw LLMError(kind: .empty, message: "输出被内容过滤器拦截（finish_reason=content_filter）")
        default:
            throw LLMError(kind: .empty, message: "模型返回为空（finish_reason=\(finish)）")
        }
    }
}
