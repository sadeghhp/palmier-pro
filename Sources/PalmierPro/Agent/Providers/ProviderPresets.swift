import Foundation

/// Templates for adding a chat provider. "Add provider" instantiates a fresh
/// `ProviderConfig` (new id) from one of these.
struct ProviderPreset: Identifiable, Sendable {
    let id: String
    let displayName: String
    let kind: ProviderConfig.Kind
    let baseURL: String
    let needsKey: Bool
    let keyURL: String?
    let suggestedModels: [ProviderModel]
    let capabilities: ProviderConfig.Capabilities

    func makeConfig() -> ProviderConfig {
        ProviderConfig(
            kind: kind,
            displayName: displayName,
            baseURL: baseURL,
            models: suggestedModels,
            enabled: true,
            capabilities: capabilities
        )
    }
}

enum ProviderPresets {
    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "openrouter",
            displayName: "OpenRouter",
            kind: .openAICompatible,
            baseURL: "https://openrouter.ai/api/v1",
            needsKey: true,
            keyURL: "https://openrouter.ai/keys",
            suggestedModels: [
                ProviderModel(id: "anthropic/claude-sonnet-4.5", displayName: "Claude Sonnet 4.5"),
                ProviderModel(id: "openai/gpt-4o", displayName: "GPT-4o"),
            ],
            capabilities: .init(vision: true, tools: true)
        ),
        ProviderPreset(
            id: "ollama",
            displayName: "Ollama",
            kind: .openAICompatible,
            baseURL: "http://localhost:11434/v1",
            needsKey: false,
            keyURL: "https://ollama.com/library",
            suggestedModels: [
                ProviderModel(id: "qwen2.5", displayName: "Qwen 2.5"),
                ProviderModel(id: "llama3.1", displayName: "Llama 3.1"),
            ],
            capabilities: .init(vision: false, tools: true)
        ),
        ProviderPreset(
            id: "lmstudio",
            displayName: "LM Studio",
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            needsKey: false,
            keyURL: nil,
            suggestedModels: [],
            capabilities: .init(vision: false, tools: true)
        ),
        ProviderPreset(
            id: "vllm",
            displayName: "vLLM",
            kind: .openAICompatible,
            baseURL: "http://localhost:8000/v1",
            needsKey: false,
            keyURL: nil,
            suggestedModels: [],
            capabilities: .init(vision: false, tools: true)
        ),
        ProviderPreset(
            id: "groq",
            displayName: "Groq",
            kind: .openAICompatible,
            baseURL: "https://api.groq.com/openai/v1",
            needsKey: true,
            keyURL: "https://console.groq.com/keys",
            suggestedModels: [
                ProviderModel(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B"),
            ],
            capabilities: .init(vision: false, tools: true)
        ),
        ProviderPreset(
            id: "together",
            displayName: "Together AI",
            kind: .openAICompatible,
            baseURL: "https://api.together.xyz/v1",
            needsKey: true,
            keyURL: "https://api.together.ai/settings/api-keys",
            suggestedModels: [],
            capabilities: .init(vision: false, tools: true)
        ),
        ProviderPreset(
            id: "custom-openai",
            displayName: "OpenAI-compatible",
            kind: .openAICompatible,
            baseURL: "http://localhost:8080/v1",
            needsKey: false,
            keyURL: nil,
            suggestedModels: [],
            capabilities: .init(vision: false, tools: true)
        ),
        ProviderPreset(
            id: "anthropic-compatible",
            displayName: "Anthropic-compatible",
            kind: .anthropicCompatible,
            baseURL: "https://api.anthropic.com",
            needsKey: true,
            keyURL: nil,
            suggestedModels: [
                ProviderModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
            ],
            capabilities: .init(vision: true, tools: true)
        ),
    ]
}
