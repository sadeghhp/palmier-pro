import Foundation

/// A user-added chat provider (BYO endpoint). The built-in Palmier proxy and
/// Anthropic-BYOK paths are NOT modeled here — they stay special-cased in AgentService.
struct ProviderConfig: Codable, Identifiable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case openAICompatible
        case anthropicCompatible
        case gemini

        var supported: Bool {
            switch self {
            case .openAICompatible, .anthropicCompatible: true
            case .gemini: false // Phase 2
            }
        }
    }

    let id: String
    var kind: Kind
    var displayName: String
    var baseURL: String
    var models: [ProviderModel]
    var enabled: Bool
    var capabilities: Capabilities

    var keychainAccount: String { "chatprovider-\(id)" }

    struct Capabilities: Codable, Sendable, Hashable {
        var vision: Bool
        var tools: Bool
    }

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        displayName: String,
        baseURL: String,
        models: [ProviderModel] = [],
        enabled: Bool = true,
        capabilities: Capabilities = .init(vision: false, tools: true)
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.models = models
        self.enabled = enabled
        self.capabilities = capabilities
    }
}

struct ProviderModel: Codable, Identifiable, Sendable, Hashable {
    let id: String
    var displayName: String

    init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

/// Unified selection reference for the chat model picker. `providerId == builtin`
/// points at the Palmier/Anthropic-BYOK path; otherwise at a `ProviderConfig`.
struct ChatModelRef: Hashable, Codable, Sendable {
    static let builtin = "builtin"

    var providerId: String
    var modelId: String
    var displayName: String

    var isBuiltin: Bool { providerId == Self.builtin }

    /// Stable token persisted in UserDefaults.
    var token: String { "\(providerId)::\(modelId)" }

    init(providerId: String, modelId: String, displayName: String) {
        self.providerId = providerId
        self.modelId = modelId
        self.displayName = displayName
    }

    static func builtin(_ model: AnthropicModel) -> ChatModelRef {
        ChatModelRef(providerId: builtin, modelId: model.rawValue, displayName: model.displayName)
    }

    /// Parse a persisted `providerId::modelId` token. A bare `AnthropicModel` raw
    /// value (legacy `agentModel` value) maps to the built-in path.
    static func parse(token: String) -> (providerId: String, modelId: String)? {
        if let range = token.range(of: "::") {
            let providerId = String(token[..<range.lowerBound])
            let modelId = String(token[range.upperBound...])
            guard !providerId.isEmpty, !modelId.isEmpty else { return nil }
            return (providerId, modelId)
        }
        if AnthropicModel(rawValue: token) != nil {
            return (builtin, token)
        }
        return nil
    }
}
