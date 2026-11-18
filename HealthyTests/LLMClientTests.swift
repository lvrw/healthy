import Foundation
import Testing

struct LLMClientTests {
    @Test func returnsTrimmedContent() throws {
        let json = """
        {"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"  OK\\n"}}]}
        """
        let content = try LLMResponseParser.content(from: Data(json.utf8))
        #expect(content == "OK")
    }

    @Test func reportsReasoningOnlyResponse() {
        // DeepSeek 思考模式：content 为空、推理内容占满 token 预算
        let json = """
        {"choices":[{"finish_reason":"length","message":{"content":"","reasoning_content":"用户要求只回复 OK，我应该直接输出。"}}]}
        """
        do {
            _ = try LLMResponseParser.content(from: Data(json.utf8))
            Issue.record("推理内容不应被当作正式回答")
        } catch let error as LLMError {
            #expect(error.kind == .empty)
            #expect(error.message.contains("思考内容"))
        } catch {
            Issue.record("错误类型不符：\(error)")
        }
    }

    @Test func reportsLengthTruncation() {
        let json = """
        {"choices":[{"finish_reason":"length","message":{"content":"","reasoning_content":""}}]}
        """
        do {
            _ = try LLMResponseParser.content(from: Data(json.utf8))
            Issue.record("空内容应当抛错")
        } catch let error as LLMError {
            #expect(error.kind == .empty)
            #expect(error.message.contains("length"))
        } catch {
            Issue.record("错误类型不符：\(error)")
        }
    }

    @Test func acceptsNullContent() {
        // content 允许为 null，不应退化成“无法解析模型响应”
        let json = """
        {"choices":[{"finish_reason":"stop","message":{"content":null,"reasoning_content":null}}]}
        """
        do {
            _ = try LLMResponseParser.content(from: Data(json.utf8))
            Issue.record("null 内容应当抛空响应错误")
        } catch let error as LLMError {
            #expect(error.kind == .empty)
        } catch {
            Issue.record("错误类型不符：\(error)")
        }
    }

    @Test func rejectsNonJSONBody() {
        do {
            _ = try LLMResponseParser.content(from: Data("<html>502</html>".utf8))
            Issue.record("非 JSON 响应应当抛解析错误")
        } catch let error as LLMError {
            #expect(error.kind == .decoding)
        } catch {
            Issue.record("错误类型不符：\(error)")
        }
    }

    @Test func deepSeekUsesCurrentModelName() {
        #expect(LLMProviderID.deepSeek.defaultModel == "deepseek-flash")
        #expect(LLMProviderID.deepSeek.defaultBaseURL.contains("deepseek.com"))
    }

    // MARK: - 视觉能力判定

    @Test func deepSeekFlashSupportsVision() {
        // deepseek-flash 原生支持图片（content 片段数组）
        #expect(LLMClient.supportsVision(model: "deepseek-flash") == true)
    }

    @Test func deepSeekProIsTextOnly() {
        #expect(LLMClient.supportsVision(model: "deepseek-v4-pro") == false)
    }

    @Test func otherModelsAssumeVision() {
        #expect(LLMClient.supportsVision(model: "qwen3.8-flash") == true)
        #expect(LLMClient.supportsVision(model: "qwen-vl-max") == true)
    }

    @Test func visionSupportFollowsConfiguration() {
        let flash = LLMClient.Configuration(
            baseURL: "https://api.deepseek.com/",
            model: "deepseek-flash",
            apiKey: "k",
            provider: .deepSeek
        )
        let pro = LLMClient.Configuration(
            baseURL: "https://api.deepseek.com/",
            model: "deepseek-v4-pro",
            apiKey: "k",
            provider: .custom
        )
        #expect(LLMClient.supportsVision(flash) == true)
        #expect(LLMClient.supportsVision(pro) == false)
    }

    // MARK: - 视觉请求体结构（422 回归）

    @Test func visionRequestBodyKeepsSystemContentAsString() throws {
        let body = try LLMClient.visionRequestBody(
            configuration: .init(
                baseURL: "https://api.deepseek.com/",
                model: "deepseek-flash",
                apiKey: "k",
                provider: .deepSeek
            ),
            system: "系统提示",
            userText: "请看这张照片",
            images: [Data([0xFF, 0xD8, 0xFF, 0xE0])],
            maxTokens: 1200
        )
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]]
        #expect(messages?.count == 2)
        // system 的 content 必须是字符串：传数组会被服务端判为参数非法（422）
        #expect(messages?.first?["content"] as? String == "系统提示")

        let userContent = messages?.last?["content"] as? [[String: Any]]
        #expect(userContent?.count == 2)
        #expect(userContent?.first?["type"] as? String == "text")
        #expect(userContent?.last?["type"] as? String == "image_url")
        let imageURL = userContent?.last?["image_url"] as? [String: Any]
        #expect((imageURL?["url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(imageURL?["detail"] as? String == "high")
        // DeepSeek 思考模式默认开启，会挤占 max_tokens，必须显式关闭
        #expect((json?["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        #expect((json?["response_format"] as? [String: Any])?["type"] as? String == "json_object")
    }

    @Test func visionRequestBodyOmitsImagesWhenNoneProvided() throws {
        let body = try LLMClient.visionRequestBody(
            configuration: .init(
                baseURL: "https://api.deepseek.com/",
                model: "deepseek-flash",
                apiKey: "k",
                provider: .deepSeek
            ),
            system: "系统提示",
            userText: "一碗米饭",
            images: [],
            maxTokens: 1200
        )
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]]
        let userContent = messages?.last?["content"] as? [[String: Any]]
        #expect(userContent?.count == 1)
        #expect(userContent?.first?["type"] as? String == "text")
    }

    @Test func unprocessableEntityMapsToInvalidRequest() {
        let error = LLMClient.statusError(422, body: #"{"detail":"content must be a string"}"#)
        #expect(error.kind == .invalidRequest)
        #expect(error.message.contains("422"))
        // 服务端 detail 要带出来，否则只能看到裸状态码
        #expect(error.message.contains("content must be a string"))
    }
}
