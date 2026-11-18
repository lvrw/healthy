import Foundation
import SwiftData

@MainActor
final class ChatService {
    private let context: ModelContext
    private let client: LLMClient
    private let keychain: KeychainStore
    private var isInFlight = false
    /// 流式输出期间把最新消息数组推送给 ChatView；每次订阅替换上一个订阅者。
    private var updatesContinuation: AsyncStream<[ChatMessage]>.Continuation?

    init(
        context: ModelContext,
        client: LLMClient = LLMClient(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.context = context
        self.client = client
        self.keychain = keychain
    }

    static func isConfigured() -> Bool {
        BriefingService.isConfigured()
    }

    static func settingsSummary() -> String {
        BriefingService.settingsSummary()
    }

    func session(for dayKey: String) -> ChatSession {
        let all = (try? context.fetch(FetchDescriptor<ChatSession>())) ?? []
        if let existing = all.first(where: { $0.dayKey == dayKey }) {
            return existing
        }
        let row = ChatSession(dayKey: dayKey)
        context.insert(row)
        try? context.save()
        return row
    }

    func referencePayload(dayKey: String) -> String? {
        try? BriefingService(context: context).previewPayload(dayKey: dayKey)
    }

    /// View 订阅消息变化：等待思考、逐句追加、完成、失败都会推送完整数组。
    func messageUpdates() -> AsyncStream<[ChatMessage]> {
        let (stream, continuation) = AsyncStream<[ChatMessage]>.makeStream()
        updatesContinuation = continuation
        return stream
    }

    /// 每条手动发送 = 一次计费调用；发送中拒绝新请求，失败不自动重试。
    func send(dayKey: String, text: String) async {
        guard !isInFlight else { return }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let row = session(for: dayKey)
        let history = row.messages
        let userMessage = ChatMessage(role: .user, content: question, createdAt: .now)
        let reply = ChatMessage(role: .assistant, content: "", createdAt: .now, status: .thinking)
        let updated = history + [userMessage, reply]
        row.messages = updated
        try? context.save()
        publish(updated)
        await request(row: row, dayKey: dayKey, question: question, history: history, replyID: reply.id)
    }

    /// 手动重试：删除上一条回答，用同一问题重新发起（一次新的计费调用）。
    func retry(dayKey: String) async {
        guard !isInFlight else { return }
        let row = session(for: dayKey)
        var messages = row.messages
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return }
        let question = messages[lastUserIndex].content
        messages = Array(messages[..<messages.index(after: lastUserIndex)])
        let history = Array(messages.dropLast())
        let reply = ChatMessage(role: .assistant, content: "", createdAt: .now, status: .thinking)
        messages.append(reply)
        row.messages = messages
        try? context.save()
        publish(messages)
        await request(row: row, dayKey: dayKey, question: question, history: history, replyID: reply.id)
    }

    func toggleLike(dayKey: String, messageID: UUID, liked: Bool) {
        let row = session(for: dayKey)
        update(row, messageID: messageID) { message in
            message.liked = message.liked == liked ? nil : liked
        }
    }

    // MARK: - 请求与逐句输出

    private func request(
        row: ChatSession,
        dayKey: String,
        question: String,
        history: [ChatMessage],
        replyID: UUID
    ) async {
        isInFlight = true
        defer { isInFlight = false }
        do {
            let settings = LLMSettingsStore.load()
            guard let apiKey = keychain.read(account: settings.provider.rawValue), !apiKey.isEmpty else {
                throw LLMError(kind: .notConfigured, message: "请先在设置中填写 API Key")
            }
            let configuration = LLMClient.Configuration(
                baseURL: settings.baseURL,
                model: settings.model,
                apiKey: apiKey,
                provider: settings.provider
            )
            let messages = ChatPromptBuilder.requestMessages(
                payloadJSON: referencePayload(dayKey: dayKey),
                history: history,
                question: question
            )

            var accumulated = ""
            var needsFallback = false
            do {
                let stream = await client.stream(
                    configuration: configuration,
                    messages: messages,
                    maxTokens: 600
                )
                var lastFlush = Date.distantPast
                for try await delta in stream {
                    accumulated += delta
                    let now = Date.now
                    // 按句末标点或 120ms 节流刷新，避免每个 token 都写一次 SwiftData。
                    if SentenceSplitter.endsSentence(delta)
                        || now.timeIntervalSince(lastFlush) >= 0.12 {
                        flush(accumulated, row: row, replyID: replyID, status: .streaming)
                        lastFlush = now
                    }
                }
                if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    needsFallback = true
                }
            } catch is CancellationError {
                // 页面退出导致取消时也要收尾，否则气泡会永远停在「深度思考中」。
                markError(
                    row: row,
                    replyID: replyID,
                    error: LLMError(kind: .cancelled, message: "请求已取消"),
                    preserveContent: !accumulated.isEmpty
                )
                return
            } catch {
                if accumulated.isEmpty {
                    // 服务端不支持 SSE / 只返回了思考内容：改用一次性请求回放。
                    needsFallback = true
                } else {
                    // 已有内容时不再发起第二次计费请求，保留已生成部分。
                    flush(accumulated, row: row, replyID: replyID, status: .failed)
                    markError(row: row, replyID: replyID, error: error, preserveContent: true)
                    return
                }
            }

            if needsFallback {
                let content = try await client.complete(
                    configuration: configuration,
                    messages: messages,
                    maxTokens: 600,
                    jsonMode: false
                )
                // 一次性回复按句逐条追加，保证视觉上仍是「逐句生成」。
                for sentence in SentenceSplitter.split(content) {
                    accumulated += sentence
                    flush(accumulated, row: row, replyID: replyID, status: .streaming)
                    try? await Task.sleep(for: .milliseconds(160))
                }
            }

            update(row, messageID: replyID) { message in
                message.content = accumulated
                message.status = .success
                message.errorKind = nil
            }
        } catch {
            markError(row: row, replyID: replyID, error: error, preserveContent: false)
        }
    }

    private func flush(
        _ content: String,
        row: ChatSession,
        replyID: UUID,
        status: ChatMessage.Status
    ) {
        update(row, messageID: replyID) { message in
            message.content = content
            message.status = status
        }
    }

    private func markError(
        row: ChatSession,
        replyID: UUID,
        error: Error,
        preserveContent: Bool
    ) {
        update(row, messageID: replyID) { message in
            if !preserveContent || message.content.isEmpty {
                message.content = error.localizedDescription
            }
            message.status = .failed
            message.errorKind = (error as? LLMError)?.kind.rawValue ?? LLMErrorKind.unknown.rawValue
        }
    }

    private func update(_ row: ChatSession, messageID: UUID, transform: (inout ChatMessage) -> Void) {
        var messages = row.messages
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        transform(&messages[index])
        row.messages = messages
        try? context.save()
        publish(messages)
    }

    private func publish(_ messages: [ChatMessage]) {
        updatesContinuation?.yield(messages)
    }
}

// configured by qoder
