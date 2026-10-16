import SwiftUI

/// Settings › AI (FS-08.07 §3, board `PH_SettingsAI`): who helps search,
/// what the device has built in, and the home servers the user added.
struct SettingsAIScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(SettingsKeys.aiSearch) private var searchStored = ""
    @State private var providers: [AIProvider] = []
    @State private var isAdding = false
    @State private var editing: AIProvider?
    private let onDevice = OnDeviceAI.choices

    var body: some View {
        List {
            Section {
                Picker(selection: searchBinding) {
                    ForEach(AIChoice.searchOptions(providers: providers, onDevice: onDevice), id: \.self) { choice in
                        Text(title(choice)).tag(choice)
                    }
                } label: {
                    useRow(String(localized: "AI Search", comment: "Settings › AI: who helps read searches"), systemImage: "sparkle.magnifyingglass")
                }
                .settingsRowInsets()
            } header: {
                Text(String(localized: "Use For", comment: "Settings › AI: header over the choice"))
            } footer: {
                Text(String(localized: "AI Search uses only this device or a computer on your home network.", comment: "Settings › AI footer under Use For"))
            }
            .pickerStyle(.navigationLink)

            if let status = intelligenceStatus {
                Section(String(localized: "On This Device", comment: "Settings › AI: header over the built-in AI")) {
                    SettingsTileRowLabel(
                        title: String(localized: "Apple Intelligence", comment: "Built-in AI"),
                        value: status, systemImage: "cpu", tint: .gray
                    )
                    .settingsRowInsets()
                }
            }

            Section {
                ForEach(providers) { provider in
                    Button {
                        editing = provider
                    } label: {
                        HStack {
                            SettingsTileRowLabel(
                                title: provider.name, value: providerDetail(provider),
                                systemImage: provider.kind == .homeServer ? "server.rack" : "key",
                                tint: provider.kind == .homeServer ? .blue : .teal
                            )
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .tint(.primary)
                    .settingsRowInsets()
                }
                .onDelete { offsets in
                    for index in offsets { delete(providers[index]) }
                }
                Button {
                    isAdding = true
                } label: {
                    SettingsTileRowLabel(
                        title: String(localized: "Add Provider…", comment: "Settings › AI: add an AI service"),
                        value: nil, systemImage: "plus", tint: .gray, titleStyle: .action
                    )
                }
                .settingsRowInsets()
            } header: {
                Text(String(localized: "Providers", comment: "Settings › AI: header over the added services"))
            } footer: {
                Text(String(localized: "Ollama or LM Studio on a computer at home. Searches go straight from this device to it; ShotDex has no server in between.", comment: "Settings › AI footer under Providers"))
            }
        }
        .navigationTitle(String(localized: "AI", comment: "Settings › AI title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(isPresented: $isAdding, onDismiss: reload) {
            NavigationStack {
                AIProviderForm(kind: .homeServer, existing: nil) { isAdding = false }
            }
        }
        .sheet(item: $editing, onDismiss: reload) { provider in
            NavigationStack {
                AIProviderForm(kind: provider.kind, existing: provider) { editing = nil }
            }
        }
    }

    private var searchBinding: Binding<AIChoice> {
        Binding(
            get: { AIChoice.search(stored: searchStored, providers: providers, onDevice: onDevice) },
            set: { searchStored = $0.stored }
        )
    }

    private func useRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            SettingsTileIcon(systemImage: systemImage, tint: .purple)
            Text(title)
        }
        .frame(minHeight: AppTheme.Size.settingsRowMinHeight - 2 * AppTheme.Spacing.sm)
    }

    private var intelligenceStatus: String? {
        switch OnDeviceAI.intelligence {
        case .ready: String(localized: "Ready", comment: "Settings › AI: Apple Intelligence status")
        case .notEnabled: String(localized: "Turn on Apple Intelligence in the Settings app", comment: "Settings › AI: Apple Intelligence status")
        case .downloading: String(localized: "Downloading", comment: "Settings › AI: Apple Intelligence status")
        case .unsupported: nil
        }
    }

    func title(_ choice: AIChoice) -> String {
        AIChoiceTitle.title(choice, providers: providers)
    }

    /// `claude-sonnet-5-5 · Key ends in 7Qx2`, `qwen3:14b · 192.168.1.10:11434`.
    private func providerDetail(_ provider: AIProvider) -> String {
        var parts = [provider.model]
        if provider.kind == .homeServer {
            parts.append(URL(string: provider.address).map { url in
                [url.host, url.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
            } ?? provider.address)
        } else if let suffix = dependencies.aiProviders.keySuffix(for: provider.id) {
            parts.append(String(localized: "Key ends in \(suffix)", comment: "Settings › AI: the last four characters of a saved key"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func delete(_ provider: AIProvider) {
        try? dependencies.aiProviders.delete(id: provider.id)
        reload()
    }

    private func reload() {
        providers = (try? dependencies.aiProviders.providers()) ?? []
    }
}

/// The words for an AI choice, wherever one is shown.
enum AIChoiceTitle {
    static func title(_ choice: AIChoice, providers: [AIProvider]) -> String {
        switch choice {
        case .off: String(localized: "Off", comment: "AI choice: AI Search off")
        case .appleIntelligence: String(localized: "Apple Intelligence", comment: "Built-in AI")
        case .provider(let id): providers.first { $0.id == id }?.name ?? id
        }
    }

    static func kindName(_ kind: AIProvider.Kind) -> String {
        switch kind {
        case .homeServer: String(localized: "Home Server", comment: "AI provider kind: Ollama or LM Studio on the home network")
        case .claude: "Claude"
        case .chatGPT: "ChatGPT"
        case .openRouter: "OpenRouter"
        case .grok: "Grok"
        case .gemini: "Gemini"
        case .openAICompatible: String(localized: "Other OpenAI-Compatible", comment: "AI provider kind: any other service speaking the OpenAI API")
        }
    }
}
