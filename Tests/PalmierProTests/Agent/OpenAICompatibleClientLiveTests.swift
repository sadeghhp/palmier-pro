import Foundation
import Testing
@testable import PalmierPro

/// Live end-to-end exercise of `OpenAICompatibleClient` against a local Ollama server.
/// Gated behind an env var so it never runs in normal CI.
///
/// Run with:
///   ollama serve &
///   ollama pull qwen2.5
///   PALMIER_LIVE_OLLAMA=1 swift test --filter OpenAICompatibleClientLive
@Suite("OpenAICompatibleClient — live (Ollama)")
struct OpenAICompatibleClientLiveTests {

    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["PALMIER_LIVE_OLLAMA"] != nil
    }

    private var model: String {
        ProcessInfo.processInfo.environment["PALMIER_OLLAMA_MODEL"] ?? "qwen2.5"
    }

    private func client() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            baseURL: "http://localhost:11434/v1",
            apiKey: "",
            modelId: model,
            capabilities: .init(vision: false, tools: true)
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<AnthropicStreamEvent, Error>
    ) async throws -> [AnthropicStreamEvent] {
        var events: [AnthropicStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(2)))
    func streamsPlainText() async throws {
        let stream = client().stream(
            system: "You are a terse assistant.",
            tools: [],
            messages: [AnthropicMessage(role: .user, content: [
                ["type": "text", "text": "Reply with exactly the word: pong"],
            ])]
        )
        let events = try await collect(stream)

        let text = events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
        #expect(!text.isEmpty)
        #expect(events.contains { if case .messageStop = $0 { return true } else { return false } })
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(2)))
    func performsToolRoundTrip() async throws {
        let tool = AnthropicToolSchema(
            name: "add_text_clip",
            description: "Add a text clip to the timeline with the given text.",
            inputSchema: [
                "type": "object",
                "properties": ["text": ["type": "string", "description": "The text to display"]],
                "required": ["text"],
            ]
        )
        let stream = client().stream(
            system: "You are a video editor. To add text, you MUST call the add_text_clip tool. Do not answer in prose.",
            tools: [tool],
            messages: [AnthropicMessage(role: .user, content: [
                ["type": "text", "text": "Add a text clip that says hello world."],
            ])]
        )
        let events = try await collect(stream)

        let toolCalls = events.compactMap { event -> (id: String, name: String, json: String)? in
            if case .toolUseComplete(let id, let name, let json) = event { return (id, name, json) }
            return nil
        }
        let call = try #require(toolCalls.first, "model did not call the tool")
        #expect(call.name == "add_text_clip")
        #expect(!call.id.isEmpty)
        // inputJSON must be valid JSON (proves arg-fragment buffering assembled correctly).
        let parsed = try JSONSerialization.jsonObject(with: Data(call.json.utf8)) as? [String: Any]
        #expect(parsed != nil)

        // A buffered tool call must terminate the turn as .toolUse so the agent loop continues.
        let stops = events.compactMap { if case .messageStop(let r) = $0 { return r } else { return nil } }
        #expect(stops.last == .toolUse)
    }
}
