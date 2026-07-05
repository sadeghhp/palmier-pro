import AppKit
import SwiftUI

struct ProvidersPane: View {
    @Bindable private var store = ProviderStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            header
            if store.providers.isEmpty {
                emptyState
            } else {
                ForEach(store.providers) { provider in
                    ProviderCard(provider: provider)
                    Divider().overlay(AppTheme.Border.subtleColor)
                }
            }
            addMenu
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Custom Providers")
                .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text("Bring your own chat models — local (Ollama, LM Studio) or hosted (OpenRouter, Groq). Keys are stored in your macOS Keychain.")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        Text("No custom providers yet.")
            .font(.system(size: AppTheme.FontSize.sm))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
    }

    private var addMenu: some View {
        Menu {
            ForEach(ProviderPresets.all) { preset in
                Button(preset.displayName) { store.upsert(preset.makeConfig()) }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "plus")
                Text("Add provider")
            }
            .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct ProviderCard: View {
    let provider: ProviderConfig
    private var store = ProviderStore.shared

    @State private var baseURL: String
    @State private var keyDraft: String = ""
    @State private var newModelId: String = ""
    @State private var testState: TestState = .idle
    @FocusState private var keyFocused: Bool

    init(provider: ProviderConfig) {
        self.provider = provider
        _baseURL = State(initialValue: provider.baseURL)
    }

    private enum TestState: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            titleRow
            baseURLField
            keyField
            modelsSection
            capabilitiesRow
            testRow
        }
    }

    private var titleRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(provider.displayName)
                .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(provider.kind == .anthropicCompatible ? "Anthropic-compatible" : "OpenAI-compatible")
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.mutedColor)
            Spacer()
            Toggle("", isOn: Binding(
                get: { provider.enabled },
                set: { v in update { $0.enabled = v } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            Button(action: { store.remove(id: provider.id) }) {
                Image(systemName: "trash")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }
            .buttonStyle(.plain)
            .help("Remove provider")
        }
    }

    private var baseURLField: some View {
        labeledField(label: "Base URL") {
            TextField("https://…", text: $baseURL)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .onChange(of: baseURL) { _, new in
                    update { $0.baseURL = new.trimmingCharacters(in: .whitespaces) }
                }
        }
    }

    private var keyField: some View {
        labeledField(label: "API Key") {
            HStack(spacing: AppTheme.Spacing.sm) {
                SecureField(store.hasKey(for: provider.id) ? "••••••••  (saved)" : "optional for local models", text: $keyDraft)
                    .textFieldStyle(.plain)
                    .focused($keyFocused)
                    .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .onSubmit(saveKey)
                if !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Save", action: saveKey)
                        .buttonStyle(.capsule(.prominent))
                } else if store.hasKey(for: provider.id) {
                    Button(action: { store.saveKey("", for: provider.id) }) {
                        Image(systemName: "trash").font(.system(size: AppTheme.FontSize.sm))
                    }
                    .buttonStyle(.plain)
                    .help("Remove key")
                }
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            fieldLabel("Models")
            ForEach(provider.models) { model in
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(model.id)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    Spacer()
                    Button(action: { removeModel(model.id) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.mutedColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                fieldBox {
                    TextField("model id (e.g. llama3.1)", text: $newModelId)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .onSubmit(addModel)
                }
                Button("Add", action: addModel)
                    .buttonStyle(.capsule(.secondary))
                    .disabled(newModelId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var capabilitiesRow: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Toggle("Vision", isOn: Binding(
                get: { provider.capabilities.vision },
                set: { v in update { $0.capabilities.vision = v } } ))
            Toggle("Tools", isOn: Binding(
                get: { provider.capabilities.tools },
                set: { v in update { $0.capabilities.tools = v } } ))
            Spacer()
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: AppTheme.FontSize.sm))
        .foregroundStyle(AppTheme.Text.secondaryColor)
    }

    private var testRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button(action: runTest) {
                Text(testState == .testing ? "Testing…" : "Test connection")
                    .font(.system(size: AppTheme.FontSize.sm))
            }
            .buttonStyle(.capsule(.secondary))
            .disabled(testState == .testing)

            switch testState {
            case .idle, .testing:
                EmptyView()
            case .ok(let detail):
                Label(detail, systemImage: "checkmark.circle.fill")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(msg)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
            .tracking(AppTheme.Tracking.tight)
            .foregroundStyle(AppTheme.Text.tertiaryColor)
    }

    private func labeledField<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            fieldLabel(label)
            fieldBox { content() }
        }
    }

    private func fieldBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(Color.black.opacity(AppTheme.Opacity.muted))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
            )
    }

    private func update(_ mutate: (inout ProviderConfig) -> Void) {
        var copy = provider
        mutate(&copy)
        store.upsert(copy)
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        store.saveKey(key, for: provider.id)
        keyDraft = ""
        keyFocused = false
    }

    private func addModel() {
        let id = newModelId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !provider.models.contains(where: { $0.id == id }) else { return }
        update { $0.models.append(ProviderModel(id: id)) }
        newModelId = ""
    }

    private func removeModel(_ id: String) {
        update { $0.models.removeAll { $0.id == id } }
    }

    private func runTest() {
        testState = .testing
        let config = provider
        let key = store.key(for: provider.id)
        Task {
            let result = await ProviderHealthCheck.run(config, apiKey: key)
            switch result {
            case .ok(let models):
                testState = .ok(models.isEmpty ? "Reachable" : "\(models.count) models")
            case .failed(let msg):
                testState = .failed(msg)
            }
        }
    }
}
