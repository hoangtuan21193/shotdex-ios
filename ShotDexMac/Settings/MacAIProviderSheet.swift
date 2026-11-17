import SwiftUI

/// Add or edit a home server for AI Search (FS-08.07 §3, FS-18.04 §3c,
/// board `MAC_SettingsAIProvider`): name, address, an optional key — a
/// secret field that shows only its last four characters once saved — the
/// model from the server's own list, Test, Delete.
struct MacAIProviderSheet: View {
    let editing: AIProvider?
    /// The saved row, or nil when it was deleted.
    var finished: (AIProvider?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(MacDependencies.self) private var dependencies
    @State private var name = ""
    @State private var address = ""
    @State private var key = ""
    @State private var model = ""
    @State private var models: [String] = []
    @State private var listing = Listing.idle
    @State private var test: MacAIProviderTest?
    /// The running Test; a new run or an edit cancels it, so a late answer
    /// never lands on values it did not test.
    @State private var testTask: Task<Void, Never>?
    @State private var confirmsUntestedSave = false
    @State private var confirmsDelete = false
    @State private var isSaving = false
    @State private var failure: String?

    enum Listing: Equatable { case idle, loading, failed }

    init(editing: AIProvider?, finished: @escaping (AIProvider?) -> Void) {
        self.editing = editing
        self.finished = finished
        _name = State(initialValue: editing?.name ?? "")
        _address = State(initialValue: editing?.address ?? "")
        _model = State(initialValue: editing?.model ?? "")
    }

    private var ai: MacAIProviders { dependencies.aiProviders }
    private var kind: AIProvider.Kind { editing?.kind ?? .homeServer }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 24)
            Form {
                TextField(String(localized: "Name:", comment: "Mac AI provider form row"), text: $name,
                          prompt: Text("Mac Studio", comment: "Mac AI provider form: name placeholder"))
                    .accessibilityIdentifier("ai-field-name")
                TextField(String(localized: "Address:", comment: "Mac AI provider form row"), text: $address,
                          prompt: Text(verbatim: "http://192.168.1.10:11434"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai-field-address")
                SecureField(String(localized: "API Key:", comment: "Mac AI provider form row"), text: $key, prompt: Text(keyPrompt))
                Text("Ollama listens on port 11434, LM Studio on 1234. A key is only needed if you set one up.",
                     comment: "AI provider form: home server help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                modelRow
                Divider().padding(.vertical, 4)
                LabeledContent {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Button { runTest() } label: {
                                Text("Test", comment: "AI provider form: try the provider").frame(width: 72)
                            }
                            .buttonStyle(MacPushButtonStyle(isDefault: false))
                            .accessibilityLabel(String(localized: "Test Provider", comment: "Mac Settings › AI: Test, spoken"))
                            .accessibilityIdentifier("ai-sheet-test")
                            .keyboardShortcut("t", modifiers: .command)
                            .help(String(localized: "Test (⌘T)", comment: "Mac AI provider form: Test help"))
                            .disabled(!canTest || test == .running)
                            if let test { MacAIProviderTestStatus(state: test).lineLimit(2) }
                        }
                        Text(String(localized: "Test sends one short line to \(serviceName).", comment: "AI provider form: what Test does"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    EmptyView()
                }
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 24)
            footer
        }
        // One height whatever the rows say (a model list arriving, an error
        // line): a sheet that resizes is rebuilt by AppKit under the pointer.
        .frame(width: 520, height: 456)
        .tint(MacTheme.accent)
        // A result belongs to what was tested.
        .onChange(of: [address, key, model]) {
            testTask?.cancel()
            test = nil
        }
        .onDisappear { testTask?.cancel() }
        .task(id: modelsQuery) {
            // Settle typing before asking the server.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await loadModels()
        }
        .alert(String(localized: "The test didn't work. Save anyway?", comment: "AI provider form: save after a failed test"),
               isPresented: $confirmsUntestedSave) {
            Button(String(localized: "Save Anyway", comment: "AI provider form: save after a failed test")) { save() }
            Button(String(localized: "Cancel", comment: "AI provider form: keep editing"), role: .cancel) {}
        } message: {
            if case .failed(let message) = test { Text(message) }
        }
        .alert(String(localized: "Delete \(editing?.name ?? name)?", comment: "AI provider form: delete alert title"),
               isPresented: $confirmsDelete) {
            Button(String(localized: "Delete", comment: "AI provider form: delete"), role: .destructive) { delete() }
            Button(String(localized: "Cancel", comment: "AI provider form: keep it"), role: .cancel) {}
        } message: {
            Text(editing.map { MacAIDeleteText.message(for: $0, in: ai) } ?? "")
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: MacSettingsTile.size, height: MacSettingsTile.size)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: MacSettingsTile.radius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding([.horizontal, .top], 24)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            if editing != nil {
                Button(String(localized: "Delete Provider…", comment: "AI provider form: remove it"), role: .destructive) {
                    confirmsDelete = true
                }
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(isSaving)
            }
            if let failure {
                Text(failure).foregroundStyle(MacTheme.redText).lineLimit(2)
            } else if !canSave {
                Text(missing).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(role: .cancel) { dismiss() } label: {
                Text("Cancel", comment: "Mac sheet: cancel").frame(width: 72)
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(MacPushButtonStyle(isDefault: false))
            .disabled(isSaving)
            Button {
                if case .failed = test { confirmsUntestedSave = true } else { save() }
            } label: {
                Text("Save", comment: "AI provider form: save").frame(width: 72)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
            // A running test decides whether Save asks first.
            .disabled(!canSave || isSaving || test == .running)
        }
        .padding(20)
    }

    @ViewBuilder
    private var modelRow: some View {
        if models.isEmpty {
            LabeledContent(String(localized: "Model:", comment: "Mac AI provider form row")) {
                HStack(spacing: 8) {
                    TextField(String(localized: "Model", comment: "AI provider form: model"), text: $model,
                              prompt: Text(verbatim: "qwen3:14b"))
                        .labelsHidden()
                        .autocorrectionDisabled()
                    if listing == .loading { ProgressView().controlSize(.small) }
                }
            }
            if listing == .failed {
                Text("Couldn't load the models from \(serviceName). Type the model name.",
                     comment: "Mac AI provider form: the server did not list its models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker(String(localized: "Model:", comment: "Mac AI provider form row"), selection: $model) {
                ForEach(models, id: \.self) { Text(verbatim: $0).tag($0) }
                if !model.isEmpty, !models.contains(model) {
                    Text("\(model) (not on the server)", comment: "Mac AI provider form: the saved model the server no longer lists").tag(model)
                }
            }
            .accessibilityIdentifier("ai-field-model")
        }
    }

    // MARK: Words

    private var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return editing == nil ? String(localized: "Add Provider", comment: "Mac AI provider form title")
                              : AIChoiceTitle.kindName(kind)
    }

    /// `Home server · used for AI Search` when the AI Search row names it.
    private var subtitle: String {
        let kindName = kind == .homeServer ? String(localized: "Home server", comment: "Mac AI provider form: what the provider is")
                                           : AIChoiceTitle.kindName(kind)
        guard let editing, ai.choice == .provider(editing.id) else { return kindName }
        return String(localized: "\(kindName) · used for AI Search", comment: "Mac AI provider form: the provider AI Search uses, e.g. Home server · used for AI Search")
    }

    private var serviceName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "the server", comment: "AI provider form: Test sends one short line to the server.") : trimmed
    }

    private var keyPrompt: String {
        if let editing, let suffix = ai.keySuffixes[editing.id] {
            return String(repeating: "•", count: 12) + suffix
        }
        return String(localized: "Optional", comment: "AI provider form: a home server may need no key")
    }

    // MARK: Work

    private var typedKey: String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return editing.flatMap { ai.key(for: $0.id) }
    }

    private var hasAddress: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canTest: Bool { hasAddress && !model.isEmpty }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && canTest }
    /// The address only: a half-typed key is never sent while typing.
    private var modelsQuery: String { address }

    /// Why Save is off, said next to it.
    private var missing: String {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Add a name.", comment: "Mac AI provider form: why Save is off")
        }
        if !hasAddress { return String(localized: "Add the server's address.", comment: "Mac AI provider form: why Save is off") }
        return String(localized: "Choose a model.", comment: "Mac AI provider form: why Save is off")
    }

    /// A host to ask: not while `http://192.168.1.` is still being typed.
    private var isPlausibleAddress: Bool {
        guard let url = AIProviderClient.baseURL(kind: kind, address: address), let host = url.host, !host.hasSuffix(".") else { return false }
        return host.contains(".") || host == "localhost" || url.port != nil
    }

    private var draft: AIProvider {
        var provider = editing ?? AIProvider(kind: .homeServer, name: "", model: "")
        provider.name = name.trimmingCharacters(in: .whitespaces)
        // Never a key in the user part or query, not even in a log line.
        provider.address = AIProviderStore.normalizedAddress(address)
        provider.model = model
        return provider
    }

    private func loadModels() async {
        guard isPlausibleAddress else {
            models = []
            listing = .idle
            return
        }
        listing = .loading
        let found = (try? await AIProviderClient().models(kind: kind, address: AIProviderStore.normalizedAddress(address),
                                                          key: typedKey, name: serviceName)) ?? []
        guard !Task.isCancelled else { return }
        listing = found.isEmpty ? .failed : .idle
        models = found
        // A saved model the server no longer lists stays, named in the menu;
        // an embedding model cannot answer, so it is never the first pick.
        if model.isEmpty, let first = found.first(where: { !$0.localizedCaseInsensitiveContains("embed") }) ?? found.first {
            model = first
        }
    }

    private func runTest() {
        testTask?.cancel()
        test = .running
        let provider = draft, key = typedKey
        testTask = Task {
            let result = await MacAIProviderTest.run(provider, key: key)
            guard !Task.isCancelled else { return }
            test = result
        }
    }

    private func save() {
        isSaving = true
        failure = nil
        let provider = draft
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                // nil keeps the saved key; a new one replaces it.
                try await ai.save(provider, key: trimmed.isEmpty ? nil : trimmed)
                finished(provider)
                dismiss()
            } catch {
                failure = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func delete() {
        guard let editing, !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await ai.delete(editing)
                finished(nil)
                dismiss()
            } catch {
                failure = error.localizedDescription
                isSaving = false
            }
        }
    }
}
