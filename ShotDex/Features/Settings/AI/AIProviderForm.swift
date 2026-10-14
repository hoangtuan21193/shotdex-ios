import SwiftUI

/// Add or edit one AI provider (FS-08.07 §3, board `PH_SettingsAIProvider`):
/// name, address for a home or compatible server, API key (a secret field —
/// once saved only its last four characters show), model from the
/// service's own list, Test, Delete.
struct AIProviderForm: View {
    let kind: AIProvider.Kind
    let existing: AIProvider?
    let onFinish: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.appAccent) private var accent
    @State private var name = ""
    @State private var address = ""
    @State private var key = ""
    @State private var model = ""
    @State private var models: [String] = []
    @State private var test: TestState = .idle
    @State private var confirmsUntestedSave = false
    @State private var confirmsDelete = false
    @State private var hasLoaded = false

    enum TestState: Equatable {
        case idle
        case running
        case working(TimeInterval)
        case failed(String)
    }

    private let client = AIProviderClient()

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Name", comment: "AI provider form: name")) {
                    TextField(String(localized: "Name", comment: "AI provider form: name"), text: $name)
                }
                if needsAddress {
                    LabeledContent(String(localized: "Address", comment: "AI provider form: server address")) {
                        TextField(addressPrompt, text: $address)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                LabeledContent(String(localized: "API Key", comment: "AI provider form: key")) {
                    SecureField(keyPrompt, text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                modelRow
            } footer: {
                Text(keyHelp)
            }

            Section {
                Button {
                    runTest()
                } label: {
                    HStack {
                        Text(String(localized: "Test", comment: "AI provider form: try the provider"))
                            .foregroundStyle(accent)
                        Spacer()
                        testStatus
                    }
                }
                .disabled(!canTest || test == .running)
            } footer: {
                Text(String(localized: "Test sends one short line to \(serviceName).", comment: "AI provider form: what Test does"))
            }

            if existing != nil {
                Section {
                    Button(String(localized: "Delete Provider", comment: "AI provider form: remove it"), role: .destructive) {
                        confirmsDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(name.isEmpty ? AIChoiceTitle.kindName(kind) : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel", comment: "AI provider form: leave without saving"), action: onFinish)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save", comment: "AI provider form: save")) {
                    if case .failed = test { confirmsUntestedSave = true } else { save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .confirmationDialog(
            String(localized: "The test didn't work. Save anyway?", comment: "AI provider form: save after a failed test"),
            isPresented: $confirmsUntestedSave, titleVisibility: .visible
        ) {
            Button(String(localized: "Save Anyway", comment: "AI provider form: save after a failed test"), action: save)
            Button(String(localized: "Cancel", comment: "AI provider form: keep editing"), role: .cancel) {}
        }
        .alert(
            String(localized: "Delete \(name)?", comment: "AI provider form: delete alert title"),
            isPresented: $confirmsDelete
        ) {
            Button(String(localized: "Delete", comment: "AI provider form: delete"), role: .destructive) {
                if let existing { try? dependencies.aiProviders.delete(id: existing.id) }
                onFinish()
            }
            Button(String(localized: "Cancel", comment: "AI provider form: keep it"), role: .cancel) {}
        } message: {
            Text(String(localized: "Its API key is removed from this device too.", comment: "AI provider form: delete alert message"))
        }
        .onAppear(perform: load)
        .task(id: modelsQuery) {
            // Settle typing before asking the service.
            try? await Task.sleep(for: .milliseconds(600))
            await loadModels()
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var modelRow: some View {
        if models.isEmpty {
            LabeledContent(String(localized: "Model", comment: "AI provider form: model")) {
                TextField(String(localized: "Model", comment: "AI provider form: model"), text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } else {
            Picker(String(localized: "Model", comment: "AI provider form: model"), selection: $model) {
                ForEach(models, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
        case .working(let seconds):
            Label(
                String(localized: "Working · \(seconds.formatted(.number.precision(.fractionLength(1)))) s", comment: "AI provider form: test passed, with the time it took"),
                systemImage: "checkmark"
            )
            .foregroundStyle(.green)
            .font(.subheadline)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Words

    private var needsAddress: Bool { kind == .homeServer || kind == .openAICompatible }

    private var addressPrompt: String {
        kind == .homeServer ? "http://192.168.1.10:11434" : "https://"
    }

    private var keyPrompt: String {
        if let existing, let suffix = dependencies.aiProviders.keySuffix(for: existing.id) {
            return String(repeating: "•", count: 16) + suffix
        }
        return kind == .homeServer
            ? String(localized: "Optional", comment: "AI provider form: a home server may need no key")
            : String(localized: "Required", comment: "AI provider form: a cloud service needs a key")
    }

    private var serviceName: String {
        switch kind {
        case .claude: "Anthropic"
        case .chatGPT: "OpenAI"
        case .homeServer, .openAICompatible: name.isEmpty ? AIChoiceTitle.kindName(kind) : name
        default: AIChoiceTitle.kindName(kind)
        }
    }

    private var keyHelp: String {
        let keeps = String(localized: "ShotDex keeps it in this device's Keychain and never shows it again.", comment: "AI provider form: where the key goes")
        switch kind {
        case .claude: return String(localized: "Paste a key from console.anthropic.com.", comment: "AI provider form: where to get a Claude key") + " " + keeps
        case .chatGPT: return String(localized: "Paste a key from platform.openai.com.", comment: "AI provider form: where to get an OpenAI key") + " " + keeps
        case .openRouter: return String(localized: "Paste a key from openrouter.ai.", comment: "AI provider form: where to get an OpenRouter key") + " " + keeps
        case .grok: return String(localized: "Paste a key from console.x.ai.", comment: "AI provider form: where to get a Grok key") + " " + keeps
        case .gemini: return String(localized: "Paste a key from aistudio.google.com.", comment: "AI provider form: where to get a Gemini key") + " " + keeps
        case .homeServer: return String(localized: "Ollama listens on port 11434, LM Studio on 1234. A key is only needed if you set one up.", comment: "AI provider form: home server help")
        case .openAICompatible: return String(localized: "Any service that speaks the OpenAI chat API.", comment: "AI provider form: compatible service help") + " " + keeps
        }
    }

    // MARK: Work

    private var typedKey: String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return existing.flatMap { dependencies.aiProviders.key(for: $0.id) }
    }

    private var hasKey: Bool { typedKey != nil }

    private var canTest: Bool {
        !model.isEmpty && (!needsAddress || !address.isEmpty) && (kind == .homeServer || hasKey)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !model.isEmpty
            && (!needsAddress || !address.isEmpty) && (kind == .homeServer || hasKey)
    }

    private var modelsQuery: String { "\(address)|\(key.count)|\(hasLoaded)" }

    private var draft: AIProvider {
        var provider = existing ?? AIProvider(kind: kind, name: "", model: "")
        provider.name = name.trimmingCharacters(in: .whitespaces)
        provider.address = needsAddress ? address : ""
        provider.model = model
        return provider
    }

    private func load() {
        guard !hasLoaded else { return }
        if let existing {
            name = existing.name
            address = existing.address
            model = existing.model
        } else {
            // A server the user names; a known service starts with its name.
            name = needsAddress ? "" : AIChoiceTitle.kindName(kind)
            model = AIProviderClient.defaultModel(for: kind)
        }
        hasLoaded = true
    }

    private func loadModels() async {
        guard hasLoaded, !needsAddress || !address.isEmpty, kind == .homeServer || hasKey else { return }
        let found = (try? await client.models(kind: kind, address: address, key: typedKey, name: serviceName)) ?? []
        guard !found.isEmpty else { return }
        models = found
        if !found.contains(model) {
            let preferred = AIProviderClient.defaultModel(for: kind)
            model = found.contains(preferred) ? preferred : found[0]
        }
    }

    private func runTest() {
        test = .running
        let provider = draft
        let key = typedKey
        let language = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
        Task {
            do {
                let seconds = try await client.test(provider, key: key, language: language)
                test = .working(seconds)
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // nil keeps the saved key; a new one replaces it.
        try? dependencies.aiProviders.save(draft, key: trimmed.isEmpty ? nil : trimmed)
        onFinish()
    }
}
