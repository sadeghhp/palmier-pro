import Foundation

/// Translates PalmierPro's Anthropic-shaped agent types to/from the OpenAI
/// `chat/completions` wire format. Does not reuse `AnthropicRequestBody` — no
/// `cache_control`, different message/tool shapes.
enum OpenAIChatTranslation {

    // MARK: - Request

    static func build(
        model: String,
        maxTokens: Int,
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage],
        capabilities: ProviderConfig.Capabilities
    ) -> [String: Any] {
        var out: [[String: Any]] = []
        if !system.isEmpty {
            out.append(["role": "system", "content": system])
        }
        for message in messages {
            out.append(contentsOf: translate(message: message, vision: capabilities.vision))
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": out,
        ]
        if capabilities.tools, !tools.isEmpty {
            body["tools"] = tools.map { schema in
                [
                    "type": "function",
                    "function": [
                        "name": schema.name,
                        "description": schema.description,
                        "parameters": schema.inputSchema,
                    ],
                ]
            }
        }
        return body
    }

    private static func translate(message: AnthropicMessage, vision: Bool) -> [[String: Any]] {
        switch message.role {
        case .assistant:
            return [translateAssistant(content: message.content)]
        case .user:
            return translateUser(content: message.content, vision: vision)
        }
    }

    private static func translateAssistant(content: [[String: Any]]) -> [String: Any] {
        var text = ""
        var toolCalls: [[String: Any]] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                text += block["text"] as? String ?? ""
            case "tool_use":
                let args = block["input"].flatMap { jsonString(from: $0) } ?? "{}"
                toolCalls.append([
                    "id": block["id"] as? String ?? "",
                    "type": "function",
                    "function": [
                        "name": block["name"] as? String ?? "",
                        "arguments": args,
                    ],
                ])
            default: break
            }
        }
        var msg: [String: Any] = ["role": "assistant"]
        msg["content"] = text.isEmpty ? NSNull() : text
        if !toolCalls.isEmpty { msg["tool_calls"] = toolCalls }
        return msg
    }

    private static func translateUser(content: [[String: Any]], vision: Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var parts: [[String: Any]] = []
        var deferredImages: [[String: Any]] = []

        for block in content {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String {
                    parts.append(["type": "text", "text": text])
                }
            case "image":
                if let url = imageURL(from: block) {
                    if vision {
                        parts.append(["type": "image_url", "image_url": ["url": url]])
                    } else {
                        parts.append(["type": "text", "text": "[image omitted: model has no vision]"])
                    }
                }
            case "tool_result":
                let (message, images) = translateToolResult(block, vision: vision)
                out.append(message)
                deferredImages.append(contentsOf: images)
            default: break
            }
        }

        if !parts.isEmpty {
            out.append(["role": "user", "content": parts])
        }
        // OpenAI tool messages are text-only; surface tool-result images as a
        // follow-up user turn (vision providers only).
        if vision, !deferredImages.isEmpty {
            out.append(["role": "user", "content": deferredImages])
        }
        return out
    }

    private static func translateToolResult(
        _ block: [String: Any], vision: Bool
    ) -> (message: [String: Any], images: [[String: Any]]) {
        let toolCallId = block["tool_use_id"] as? String ?? ""
        var text = ""
        var images: [[String: Any]] = []
        for entry in block["content"] as? [[String: Any]] ?? [] {
            switch entry["type"] as? String {
            case "text":
                text += entry["text"] as? String ?? ""
            case "image":
                if vision, let url = imageURL(from: entry) {
                    images.append(["type": "image_url", "image_url": ["url": url]])
                    text += text.isEmpty ? "[image attached below]" : "\n[image attached below]"
                } else {
                    text += text.isEmpty ? "[image omitted: model has no vision]"
                        : "\n[image omitted: model has no vision]"
                }
            default: break
            }
        }
        return (["role": "tool", "tool_call_id": toolCallId, "content": text.isEmpty ? "(no output)" : text], images)
    }

    private static func imageURL(from block: [String: Any]) -> String? {
        guard let source = block["source"] as? [String: Any],
              let mime = source["media_type"] as? String,
              let data = source["data"] as? String else { return nil }
        return "data:\(mime);base64,\(data)"
    }

    private static func jsonString(from value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return "{}" }
            return (try? JSONSerialization.data(withJSONObject: dict))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        if let str = value as? String { return str }
        return nil
    }

    // MARK: - Response (SSE)

    static func parse(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        // Tool calls arrive as fragments indexed by position; buffer like input_json_delta.
        var pendingTools: [Int: (id: String, name: String, args: String)] = [:]
        var finish: AnthropicStopReason?

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            if let delta = choice["delta"] as? [String: Any] {
                if let text = delta["content"] as? String, !text.isEmpty {
                    continuation.yield(.textDelta(text))
                }
                if let calls = delta["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        let index = call["index"] as? Int ?? 0
                        var acc = pendingTools[index] ?? ("", "", "")
                        if let id = call["id"] as? String, !id.isEmpty { acc.id = id }
                        if let fn = call["function"] as? [String: Any] {
                            if let name = fn["name"] as? String, !name.isEmpty { acc.name = name }
                            if let args = fn["arguments"] as? String { acc.args += args }
                        }
                        pendingTools[index] = acc
                    }
                }
            }

            if let reason = choice["finish_reason"] as? String {
                finish = stopReason(from: reason)
            }
        }

        for (index, tool) in pendingTools.sorted(by: { $0.key < $1.key }) {
            let json = tool.args.isEmpty ? "{}" : tool.args
            // Some compatible servers omit tool-call ids; synthesize one so the
            // tool_use → tool_result round-trip stays correlated.
            let id = tool.id.isEmpty ? "call_\(UUID().uuidString.prefix(8))_\(index)" : tool.id
            continuation.yield(.toolUseComplete(id: id, name: tool.name, inputJSON: json))
        }
        // A buffered tool call always means we must run tools, even if the server
        // reported finish_reason "stop" instead of "tool_calls".
        let stop = pendingTools.isEmpty ? (finish ?? .endTurn) : .toolUse
        continuation.yield(.messageStop(stopReason: stop))
    }

    private static func stopReason(from raw: String) -> AnthropicStopReason {
        switch raw {
        case "tool_calls": .toolUse
        case "stop": .endTurn
        case "length": .maxTokens
        default: .other
        }
    }
}
