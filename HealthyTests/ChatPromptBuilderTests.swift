import Foundation
import Testing

struct ChatPromptBuilderTests {
    private func message(
        _ role: ChatMessage.Role,
        _ content: String,
        status: ChatMessage.Status = .success,
        at date: Date = Date(timeIntervalSince1970: 0)
    ) -> ChatMessage {
        ChatMessage(role: role, content: content, createdAt: date, status: status)
    }

    @Test func systemPromptCarriesSafetyConstraints() {
        #expect(ChatPromptBuilder.systemPrompt.contains("只依据"))
        #expect(ChatPromptBuilder.systemPrompt.contains("不提供医疗诊断"))
        #expect(ChatPromptBuilder.systemPrompt.contains("简体中文"))
    }

    @Test func recommendedQuestionsAreDeterministicPairs() {
        let first = ChatPromptBuilder.recommendedQuestions(dayKey: "2026-11-08")
        let second = ChatPromptBuilder.recommendedQuestions(dayKey: "2026-11-08")
        #expect(first.count == 2)
        #expect(first == second)
        #expect(first[0] != first[1])
        #expect(first.allSatisfy { !$0.isEmpty })
    }

    @Test func trimmedHistoryDropsFailedAndCapsCount() {
        let history: [ChatMessage] = [
            message(.user, "u1"),
            message(.assistant, "a1", status: .failed),
            message(.assistant, "a2"),
            message(.user, "u3"),
            message(.assistant, "pending", status: .pending),
            message(.user, "u4"),
        ]
        let trimmed = ChatPromptBuilder.trimmedHistory(history, maxMessages: 3)
        #expect(trimmed.map(\.content) == ["a2", "u3", "u4"])
        // pending 与 failed 不参与请求，避免模型看到空/错误内容
        let all = ChatPromptBuilder.trimmedHistory(history, maxMessages: 100)
        #expect(all.map(\.content) == ["u1", "a2", "u3", "u4"])
    }

    @Test func requestMessagesOrderAndContext() {
        let history = [message(.user, "u1"), message(.assistant, "a1")]
        let request = ChatPromptBuilder.requestMessages(
            payloadJSON: "{\"date\":\"2026-11-08\"}",
            history: history,
            question: "今天状态怎么样？"
        )
        #expect(request.first?.role == "system")
        #expect(request[1].role == "user")
        #expect(request[1].content.contains("2026-11-08"))
        #expect(request.map(\.role) == ["system", "user", "user", "assistant", "user"])
        #expect(request.last?.content == "今天状态怎么样？")
    }

    @Test func requestMessagesWithoutPayloadSkipsContext() {
        let request = ChatPromptBuilder.requestMessages(payloadJSON: nil, history: [], question: "你好")
        #expect(request.map(\.role) == ["system", "user"])
    }

    @Test func chatMessageJSONRoundTrip() throws {
        let original = ChatMessage(
            role: .assistant,
            content: "回复",
            createdAt: Date(timeIntervalSince1970: 1_730_000_000),
            status: .failed,
            errorKind: "timeout",
            liked: false
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: data)
        #expect(decoded == [original])
        #expect(decoded[0].id == original.id)
    }
}

// configured by qoder