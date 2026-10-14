import SwiftUI

/// Settings › AI (FS-08.07 §3, board `PH_SettingsAI`): who translates
/// subtitles and who helps search, what the device has built in, and the
/// providers the user added with their own keys.
struct SettingsAIScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(SettingsKeys.aiSubtitleTranslation) private var translationStored = ""
    @AppStorage(SettingsKeys.aiSearch) private var searchStored = ""
    @State private var providers: [AIProvider] = []
    @State private var isAdding = false
    @State private var editing: AIProvider?
    private let onDevice = OnDeviceAI.choices

    var body: some View {
        List {
            Section {
                Picker(selection: translationBinding) {
                    ForEach(AIChoice.translationOptions(providers: providers, onDevice: onDevice), id: \.self) { choice in
                        Text(title(choice)).tag(choice)
                    }
                } label: {
                    useRow(String(localized: "Subtitle Translation", comment: "Settings › AI: who translates subtitles"), systemImage: "translate")
                }
                .settingsRowInsets()
                Picker(selection: searchBinding) {
                    ForEach(AIChoice.searchOptions(providers: providers, onDevice: onDevice), id: \.self) { choice in
                        Text(title(choice)).tag(choice)
                    }
                } label: {
                    useRow(String(localized: "AI Search", comment: "Settings › AI: who helps read searches"), systemImage: "sparkle.magnifyingglass")
                }
                .settingsRowInsets()
            } header: {
                Text(String(localized: "Use For", comment: "Settings › AI: header over the two choices"))
            } footer: {
                Text(String(localized: "AI Search uses only this device or a computer on your home network.", comment: "Settings › AI footer under Use For"))
            }
            .pickerStyle(.navigationLink)

            Section(String(localized: "On This Device", comment: "Settings › AI: header over the built-in AI")) {
                if OnDeviceAI.hasAppleTranslation {
                    SettingsTileRowLabel(
                        title: String(localized: "Apple Translation", comment: "Built-in translation"),
                        value: String(localized: "Languages download when first used", comment: "Settings › AI: Apple Translation status"),
                        systemImage: "character.book.closed", tint: .gray
                    )
                    .settingsRowInsets()
                }
                if let status = intelligenceStatus {
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
                Text(String(localized: "Requests go straight from this device to the service with your key. ShotDex has no server in between.", comment: "Settings › AI footer under Providers"))
            }
        }
        .navigationTitle(String(localized: "AI", comment: "Settings › AI title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(isPresented: $isAdding, onDismiss: reload) {
            AIProviderKindPicker()
        }
        .sheet(item: $editing, onDismiss: reload) { provider in
            NavigationStack {
                AIProviderForm(kind: provider.kind, existing: provider) { editing = nil }
            }
        }
    }

    private var translationBinding: Binding<AIChoice> {
        Binding(
            get: { AIChoice.translation(stored: translationStored, providers: providers, onDevice: onDevice) },
            set: { translationStored = $0.stored }
        )
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
        case .askEachTime: String(localized: "Ask Each Time", comment: "AI choice: the Translate sheet asks")
        case .off: String(localized: "Off", comment: "AI choice: AI Search off")
        case .appleTranslation: String(localized: "Apple Translation", comment: "Built-in translation")
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

/// Add Provider…: which kind of service, then its form.
private struct AIProviderKindPicker: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(AIChoiceTitle.kindName(.homeServer)) { AIProviderForm(kind: .homeServer, existing: nil) { dismiss() } }
                } footer: {
                    Text(String(localized: "Ollama or LM Studio on a computer at home. Works for subtitles and AI Search.", comment: "Add Provider: home server footer"))
                }
                Section {
                    ForEach([AIProvider.Kind.claude, .chatGPT, .openRouter, .grok, .gemini, .openAICompatible], id: \.self) { kind in
                        NavigationLink(AIChoiceTitle.kindName(kind)) { AIProviderForm(kind: kind, existing: nil) { dismiss() } }
                    }
                } footer: {
                    Text(String(localized: "Cloud services translate subtitles with your own API key. They are never used for AI Search.", comment: "Add Provider: cloud footer"))
                }
            }
            .navigationTitle(String(localized: "Add Provider", comment: "Add Provider sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Add Provider: close")) { dismiss() }
                }
            }
        }
    }
}
