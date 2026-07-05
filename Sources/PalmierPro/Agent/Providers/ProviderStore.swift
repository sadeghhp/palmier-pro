import Foundation

extension Notification.Name {
    static let chatProvidersChanged = Notification.Name("chatProvidersChanged")
}

@Observable
@MainActor
final class ProviderStore {
    static let shared = ProviderStore()

    private static let defaultsKey = "chatProviders"

    private(set) var providers: [ProviderConfig]
    @ObservationIgnored private var keys: [String: String] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providers = decoded
        } else {
            providers = []
        }
        reloadKeys()
    }

    var enabledProviders: [ProviderConfig] {
        providers.filter { $0.enabled && $0.kind.supported }
    }

    func provider(id: String) -> ProviderConfig? {
        providers.first { $0.id == id }
    }

    func key(for providerId: String) -> String {
        keys[providerId] ?? ""
    }

    // MARK: - Mutation

    func upsert(_ config: ProviderConfig) {
        if let idx = providers.firstIndex(where: { $0.id == config.id }) {
            providers[idx] = config
        } else {
            providers.append(config)
        }
        persist()
    }

    func remove(id: String) {
        guard let config = provider(id: id) else { return }
        providers.removeAll { $0.id == id }
        keys[id] = nil
        let account = config.keychainAccount
        Task.detached(priority: .userInitiated) {
            KeychainStore.delete(account: account)
        }
        persist()
    }

    func saveKey(_ key: String, for providerId: String) {
        guard let config = provider(id: providerId) else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keys[providerId] = trimmed
        let account = config.keychainAccount
        Task.detached(priority: .userInitiated) {
            if trimmed.isEmpty {
                KeychainStore.delete(account: account)
            } else {
                KeychainStore.save(trimmed, account: account)
            }
        }
        notifyChanged()
    }

    func hasKey(for providerId: String) -> Bool {
        !(keys[providerId] ?? "").isEmpty
    }

    // MARK: - Internals

    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .chatProvidersChanged, object: nil)
    }

    private func reloadKeys() {
        let accounts = providers.map { ($0.id, $0.keychainAccount) }
        Task { [weak self] in
            var loaded: [String: String] = [:]
            for (id, account) in accounts {
                let value = await Task.detached(priority: .utility) {
                    KeychainStore.load(account: account) ?? ""
                }.value
                if !value.isEmpty { loaded[id] = value }
            }
            self?.keys = loaded
        }
    }
}
