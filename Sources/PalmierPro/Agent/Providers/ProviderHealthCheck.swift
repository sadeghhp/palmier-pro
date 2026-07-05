import Foundation

/// Read-only reachability/auth test for a configured provider.
enum ProviderHealthCheck {
    enum Result: Sendable {
        case ok(models: [String])
        case failed(String)
    }

    static func run(_ config: ProviderConfig, apiKey: String) async -> Result {
        switch config.kind {
        case .openAICompatible:
            return await listModels(
                url: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models",
                bearer: apiKey.isEmpty ? nil : apiKey
            )
        case .anthropicCompatible:
            return await anthropicPing(config, apiKey: apiKey)
        case .gemini:
            return .failed("Gemini support is coming soon.")
        }
    }

    private static func listModels(url: String, bearer: String?) async -> Result {
        guard let endpoint = URL(string: url) else { return .failed("Invalid base URL.") }
        var request = URLRequest(url: endpoint)
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("No response.") }
            guard http.statusCode < 400 else {
                return .failed("HTTP \(http.statusCode): \(bodyPreview(data))")
            }
            let ids = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["data"] as? [[String: Any]] }?
                .compactMap { $0["id"] as? String } ?? []
            return .ok(models: ids)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func anthropicPing(_ config: ProviderConfig, apiKey: String) async -> Result {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: base + "/v1/messages") else { return .failed("Invalid base URL.") }
        let model = config.models.first?.id ?? "claude-sonnet-4-5"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]],
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("No response.") }
            // 200 or a model/validation-level 400 both prove reachability + auth.
            if http.statusCode == 401 || http.statusCode == 403 {
                return .failed("Authentication failed (HTTP \(http.statusCode)).")
            }
            if http.statusCode >= 500 { return .failed("HTTP \(http.statusCode): \(bodyPreview(data))") }
            return .ok(models: config.models.map(\.id))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func bodyPreview(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
