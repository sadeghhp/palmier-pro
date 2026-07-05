import Foundation
import Testing
@testable import PalmierPro

@Suite("OpenAI chat translation")
struct OpenAIChatTranslationTests {
    private let caps = ProviderConfig.Capabilities(vision: true, tools: true)
    private let noVision = ProviderConfig.Capabilities(vision: false, tools: true)

    private func messages(_ body: [String: Any]) -> [[String: Any]] {
        body["messages"] as! [[String: Any]]
    }

    @Test func systemBecomesLeadingMessage() {
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "be helpful",
            tools: [], messages: [], capabilities: caps
        )
        let msgs = messages(body)
        #expect(msgs.first?["role"] as? String == "system")
        #expect(msgs.first?["content"] as? String == "be helpful")
    }

    @Test func toolSchemaBecomesFunction() {
        let schema = AnthropicToolSchema(
            name: "add_clips", description: "add clips",
            inputSchema: ["type": "object", "properties": [:]]
        )
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "", tools: [schema], messages: [], capabilities: caps
        )
        let tools = body["tools"] as! [[String: Any]]
        #expect(tools.first?["type"] as? String == "function")
        let fn = tools.first?["function"] as? [String: Any]
        #expect(fn?["name"] as? String == "add_clips")
        #expect(fn?["parameters"] is [String: Any])
    }

    @Test func toolsOmittedWhenUnsupported() {
        let schema = AnthropicToolSchema(name: "x", description: "", inputSchema: [:])
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "", tools: [schema], messages: [],
            capabilities: ProviderConfig.Capabilities(vision: false, tools: false)
        )
        #expect(body["tools"] == nil)
    }

    @Test func assistantToolUseBecomesToolCalls() {
        let assistant = AnthropicMessage(role: .assistant, content: [
            ["type": "text", "text": "sure"],
            ["type": "tool_use", "id": "t1", "name": "add_clips", "input": ["count": 2]],
        ])
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "", tools: [], messages: [assistant], capabilities: caps
        )
        let msg = messages(body).first { $0["role"] as? String == "assistant" }
        #expect(msg?["content"] as? String == "sure")
        let calls = msg?["tool_calls"] as? [[String: Any]]
        #expect(calls?.first?["id"] as? String == "t1")
        let fn = calls?.first?["function"] as? [String: Any]
        #expect(fn?["name"] as? String == "add_clips")
        // arguments must be a JSON *string*
        let args = fn?["arguments"] as? String
        #expect(args?.contains("\"count\"") == true)
    }

    @Test func toolResultBecomesToolMessage() {
        let user = AnthropicMessage(role: .user, content: [
            ["type": "tool_result", "tool_use_id": "t1",
             "content": [["type": "text", "text": "done"]], "is_error": false],
        ])
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "", tools: [], messages: [user], capabilities: caps
        )
        let msg = messages(body).first { $0["role"] as? String == "tool" }
        #expect(msg?["tool_call_id"] as? String == "t1")
        #expect(msg?["content"] as? String == "done")
    }

    @Test func toolResultImageDeferredToUserTurnWhenVision() {
        let user = AnthropicMessage(role: .user, content: [
            ["type": "tool_result", "tool_use_id": "t1", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": "AAAA"]],
            ], "is_error": false],
        ])
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "", tools: [], messages: [user], capabilities: caps
        )
        let msgs = messages(body)
        // one tool message (text placeholder) + a follow-up user turn carrying the image
        #expect(msgs.contains { $0["role"] as? String == "tool" })
        let follow = msgs.last
        #expect(follow?["role"] as? String == "user")
        let parts = follow?["content"] as? [[String: Any]]
        #expect(parts?.first?["type"] as? String == "image_url")
    }

    @Test func toolResultImageOmittedWithoutVision() {
        let user = AnthropicMessage(role: .user, content: [
            ["type": "tool_result", "tool_use_id": "t1", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": "AAAA"]],
            ], "is_error": false],
        ])
        let body = OpenAIChatTranslation.build(
            model: "m", maxTokens: 100, system: "", tools: [], messages: [user], capabilities: noVision
        )
        let msgs = messages(body)
        #expect(msgs.allSatisfy { $0["role"] as? String != "user" || !($0["content"] is [[String: Any]]) })
        let tool = msgs.first { $0["role"] as? String == "tool" }
        #expect((tool?["content"] as? String)?.contains("omitted") == true)
    }
}

@Suite("ChatModelRef token parsing")
struct ChatModelRefTests {
    @Test func legacyBareAnthropicModelMapsToBuiltin() {
        // Existing users have `agentModel` == "claude-sonnet-5" with no provider prefix.
        let parsed = ChatModelRef.parse(token: "claude-sonnet-5")
        #expect(parsed?.providerId == ChatModelRef.builtin)
        #expect(parsed?.modelId == "claude-sonnet-5")
    }

    @Test func providerScopedTokenRoundTrips() {
        let ref = ChatModelRef(providerId: "abc-123", modelId: "llama3.1", displayName: "Llama")
        let parsed = ChatModelRef.parse(token: ref.token)
        #expect(parsed?.providerId == "abc-123")
        #expect(parsed?.modelId == "llama3.1")
    }

    @Test func unknownBareTokenIsRejected() {
        #expect(ChatModelRef.parse(token: "not-a-real-model") == nil)
    }
}
