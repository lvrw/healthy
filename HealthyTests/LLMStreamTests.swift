import Foundation
import Testing

struct LLMStreamTests {
    @Test func parsesDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"今天的睡眠偏短"},"finish_reason":null}]}"#
        #expect(LLMStreamParser.parse(line: line) == .text("今天的睡眠偏短"))
    }

    @Test func doneAndHeartbeatsAreHandled() {
        #expect(LLMStreamParser.parse(line: "data: [DONE]") == .done)
        #expect(LLMStreamParser.parse(line: ": ping") == .ignore)
        #expect(LLMStreamParser.parse(line: "") == .ignore)
        #expect(LLMStreamParser.parse(line: "event: message") == .ignore)
    }

    @Test func reasoningOnlyChunksStayInThinkingState() {
        let line = #"data: {"choices":[{"delta":{"reasoning_content":"先算一下基线"}}]}"#
        #expect(LLMStreamParser.parse(line: line) == .ignore)
    }

    @Test func usageOnlyAndMalformedChunksAreIgnored() {
        #expect(LLMStreamParser.parse(line: #"data: {"choices":[],"usage":{"total_tokens":10}}"#) == .ignore)
        #expect(LLMStreamParser.parse(line: "data: {not json") == .ignore)
        #expect(LLMStreamParser.parse(line: #"data: {"choices":[{"delta":{"content":""}}]}"#) == .ignore)
    }

    @Test func splitKeepsPunctuation() {
        #expect(SentenceSplitter.split("第一句。第二句！第三句？") == [
            "第一句。", "第二句！", "第三句？",
        ])
    }

    @Test func splitHandlesNewlinesAndUnterminatedText() {
        #expect(SentenceSplitter.split("建议一\n建议二\n还有半句") == [
            "建议一\n", "建议二\n", "还有半句",
        ])
        #expect(SentenceSplitter.split("没有标点的整段回答") == ["没有标点的整段回答"])
        #expect(SentenceSplitter.split("  \n ") == [])
    }

    @Test func endsSentenceDrivesFlush() {
        #expect(SentenceSplitter.endsSentence("。"))
        #expect(SentenceSplitter.endsSentence("好的\n"))
        #expect(!SentenceSplitter.endsSentence("还在写"))
        #expect(!SentenceSplitter.endsSentence(""))
    }
}
