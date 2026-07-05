import Foundation

/// OpenAI `chat/completions`-compatible client. Covers OpenRouter, Ollama,
/// LM Studio, vLLM, Groq, Together, LocalAI, and any generic compatible endpoint.
struct OpenAICompatibleClient: AgentClient {
    let baseURL: String
    let apiKey: String
    let modelId: String
    let capabilities: ProviderConfig.Capabilities
    var maxTokens: Int = 8192

    private var endpoint: URL? {
        URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")
    }

    func stream(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage]
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, tools: tools, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage],
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        guard let endpoint else { throw AnthropicClientError.streamError("Invalid base URL: \(baseURL)") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: OpenAIChatTranslation.build(
                model: modelId,
                maxTokens: maxTokens,
                system: system,
                tools: tools,
                messages: messages,
                capabilities: capabilities
            )
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = ""
            for try await line in bytes.lines { body += line + "\n" }
            throw AnthropicClientError.httpError(status: http.statusCode, body: body)
        }

        try await OpenAIChatTranslation.parse(bytes: bytes, continuation: continuation)
    }
}
