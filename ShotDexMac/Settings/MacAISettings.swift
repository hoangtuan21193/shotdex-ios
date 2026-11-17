import SwiftUI

/// Settings › AI (FS-08.07 §3, FS-18.04 §3c, board `MAC_SettingsAI`): who
/// reads a search sentence — Apple Intelligence on this Mac, a computer at
/// home, or nobody — what the Mac has built in, and the home servers added.
struct MacAISettings: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var selection: String?
    @State private var form: FormRequest?
    @State private var deleting: AIProvider?
    /// Kept apart from `deleting`, which the alert clears while it closes.
    @State private var deleteTitle = ""
    @State private var failure: String?
    @State private var test: (id: String, state: MacAIProviderTest)?
    @State private var testTask: Task<Void, Never>?
    @State private var deleteMessage = ""

    struct FormRequest: Identifiable {
        let id = UUID()
        var editing: AIProvider?
    }

    private var ai: MacAIProviders { dependencies.aiProviders }
    private var selected: AIProvider? { ai.providers.first { $0.id == selection } }

    var body: some View {
        Form {
            useForSection
            if let status = intelligenceStatus { onThisMacSection(status) }
            providersSection
        }
        .formStyle(.grouped)
        .task { await ai.reload() }
        // The sheet tests on its own; a verdict under it would be about other values.
        .onChange(of: form?.id) {
            testTask?.cancel()
            test = nil
        }
        .sheet(item: $form) { request in
            MacAIProviderSheet(editing: request.editing) { saved in
                testTask?.cancel()
                test = nil
                guard let saved else { return }
                selection = saved.id
                // A server added while AI Search is Off is what the user wants it to use.
                if request.editing == nil, ai.choice == .off { ai.choose(.provider(saved.id)) }
            }
        }
        .alert(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { provider in
            Button(String(localized: "Delete", comment: "Mac Settings › AI: confirm deleting a provider"), role: .destructive) {
                delete(provider)
            }
            Button(String(localized: "Cancel", comment: "Mac Settings › AI: keep the provider"), role: .cancel) {}
        } message: { _ in
            Text(deleteMessage)
        }
        .alert(String(localized: "The Provider Was Not Deleted", comment: "Mac Settings › AI: delete failed"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Settings › AI: dismiss an error"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Sections

    private var useForSection: some View {
        Section {
            Picker(selection: Binding(get: { ai.choice }, set: { ai.choose($0) })) {
                ForEach(ai.options, id: \.self) { Text(ai.title($0)).tag($0) }
            } label: {
                MacSettingsTileLabel(title: String(localized: "AI Search", comment: "Mac Settings › AI row"),
                                     systemImage: "sparkles", tint: .purple)
            }
            .accessibilityIdentifier("ai-search-choice")
        } header: {
            Text("Use For", comment: "Mac Settings › AI group")
        } footer: {
            Text("AI Search uses only this Mac or a computer on your home network.", comment: "Mac Settings › AI footer")
                .foregroundStyle(.secondary)
        }
    }

    private func onThisMacSection(_ status: (text: String, isReady: Bool)) -> some View {
        Section {
            MacSettingsTileLabel(title: String(localized: "Apple Intelligence", comment: "Mac Settings › AI: the built-in model"),
                                 systemImage: "cpu", tint: .gray) {
                HStack(spacing: 5) {
                    Circle().fill(status.isReady ? Color.green : .orange).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(status.text)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("On This Mac", comment: "Mac Settings › AI group")
        }
    }

    private var providersSection: some View {
        Section {
            VStack(spacing: 6) {
                Table(ai.providers, selection: $selection) {
                    TableColumn(String(localized: "Name", comment: "Mac Settings › AI column")) { provider in
                        Label(provider.name, systemImage: provider.kind == .homeServer ? "server.rack" : "key").lineLimit(1)
                    }
                    .width(150)
                    TableColumn(String(localized: "Model", comment: "Mac Settings › AI column")) { provider in
                        Text(provider.model).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    .width(140)
                    TableColumn(String(localized: "Address or Key", comment: "Mac Settings › AI column")) { provider in
                        Text(ai.addressOrKey(provider)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .alternatingRowBackgrounds()
                .frame(height: CGFloat(28 + max(ai.providers.count, 2) * 24))
                .overlay {
                    if ai.hasLoaded, ai.providers.isEmpty {
                        Text("No Providers. Click + to add Ollama or LM Studio.", comment: "Mac Settings › AI: the providers table is empty")
                            .foregroundStyle(.secondary).padding(.top, 24)
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let provider = ai.providers.first(where: { $0.id == id }) {
                        Button(String(localized: "Test", comment: "Mac Settings › AI: test a provider")) { runTest(provider) }
                            .disabled(!provider.kind.servesAISearch)
                        Button(String(localized: "Edit…", comment: "Mac Settings › AI: edit a provider")) { form = FormRequest(editing: provider) }
                        Divider()
                        Button(String(localized: "Delete…", comment: "Mac Settings › AI: delete a provider"), role: .destructive) { askDelete(provider) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let provider = ai.providers.first(where: { $0.id == id }) { form = FormRequest(editing: provider) }
                }
                .onDeleteCommand { askDelete(selected) }
                buttonBar
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Providers", comment: "Mac Settings › AI group")
                Spacer()
                Text(verbatim: "Ollama · LM Studio").font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Ollama or LM Studio on a computer at home. Searches go straight from this Mac to it; ShotDex has no server in between.",
                 comment: "Mac Settings › AI footer")
                .foregroundStyle(.secondary)
        }
    }

    private var buttonBar: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Add Provider…", comment: "Mac Settings › AI: + adds a home server"), systemImage: "plus") {
                form = FormRequest(editing: nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(String(localized: "Add Provider…", comment: "Mac Settings › AI: + help"))
            Button(String(localized: "Delete Provider", comment: "Mac Settings › AI: − deletes the selected provider"), systemImage: "minus") {
                askDelete(selected)
            }
            .labelStyle(.iconOnly)
            .disabled(selected == nil)
            .buttonStyle(.borderless)
            .help(String(localized: "Delete Provider", comment: "Mac Settings › AI: − help"))
            Spacer()
            if let test, test.id == selection { MacAIProviderTestStatus(state: test.state).lineLimit(2) }
            Button(String(localized: "Test", comment: "Mac Settings › AI: test the selected provider")) {
                if let selected { runTest(selected) }
            }
            .accessibilityLabel(String(localized: "Test Provider", comment: "Mac Settings › AI: Test, spoken"))
            .disabled(selected == nil || selected?.kind.servesAISearch == false || test?.state == .running)
            Button(String(localized: "Edit…", comment: "Mac Settings › AI: edit the selected provider")) {
                form = FormRequest(editing: selected)
            }
            .accessibilityLabel(String(localized: "Edit Provider", comment: "Mac Settings › AI: Edit…, spoken"))
            .disabled(selected == nil)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Words

    private func askDelete(_ provider: AIProvider?) {
        guard let provider else { return }
        deleteTitle = String(localized: "Delete \(provider.name)?", comment: "Mac Settings › AI: delete alert title, e.g. Delete Mac Studio?")
        deleteMessage = MacAIDeleteText.message(for: provider, in: ai)
        deleting = provider
    }

    /// Ready / not on / downloading; nil hides the group on a Mac that cannot run it.
    private var intelligenceStatus: (text: String, isReady: Bool)? {
        switch OnDeviceAI.intelligence {
        case .ready: (String(localized: "Ready", comment: "Settings › AI: Apple Intelligence status"), true)
        case .notEnabled: (String(localized: "Turn on Apple Intelligence in System Settings", comment: "Mac Settings › AI: Apple Intelligence status"), false)
        case .downloading: (String(localized: "Downloading", comment: "Settings › AI: Apple Intelligence status"), false)
        case .unsupported: nil
        }
    }

    // MARK: Work

    private func runTest(_ provider: AIProvider) {
        testTask?.cancel()
        test = (provider.id, .running)
        let key = ai.key(for: provider.id)
        testTask = Task {
            let state = await MacAIProviderTest.run(provider, key: key)
            guard !Task.isCancelled, test?.id == provider.id else { return }
            test = (provider.id, state)
        }
    }

    private func delete(_ provider: AIProvider) {
        Task {
            do {
                try await ai.delete(provider)
                if selection == provider.id { selection = nil }
                if test?.id == provider.id { test = nil }
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// A row title after a small coloured tile, as System Settings draws its
/// rows; an optional second line under the title.
struct MacSettingsTileLabel<Detail: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: MacSettingsTile.size, height: MacSettingsTile.size)
                .background(tint, in: RoundedRectangle(cornerRadius: MacSettingsTile.radius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                detail
            }
        }
    }
}

/// A Settings row's icon tile (boards `MAC_SettingsAI*`): 28 square,
/// radius 8, a flat system colour, a white 16pt glyph — the one place a
/// colour other than amber fills a shape, because it names a kind of thing
/// the way System Settings does (MAC_STYLE §Settings tiles).
enum MacSettingsTile {
    static let size: CGFloat = 28
    static let radius: CGFloat = 8
}

extension MacSettingsTileLabel where Detail == EmptyView {
    init(title: String, systemImage: String, tint: Color) {
        self.init(title: title, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

/// The delete alert's message: the key goes, and AI Search goes back to
/// its default when it named this provider.
enum MacAIDeleteText {
    @MainActor
    static func message(for provider: AIProvider, in ai: MacAIProviders) -> String {
        let key = String(localized: "Its API key is removed from this Mac too.", comment: "Mac Settings › AI: delete alert message")
        guard ai.choice == .provider(provider.id) else { return key }
        let after = ai.onDevice.appleIntelligence
            ? String(localized: "AI Search will go back to Apple Intelligence.", comment: "Mac Settings › AI: deleting the provider AI Search uses")
            : String(localized: "AI Search will turn off.", comment: "Mac Settings › AI: deleting the provider AI Search uses")
        return key + " " + after
    }
}

/// What Test said about a provider.
enum MacAIProviderTest: Equatable {
    case running
    case working(TimeInterval)
    case failed(String)

    /// One short line to the provider, never on the main actor.
    static func run(_ provider: AIProvider, key: String?) async -> MacAIProviderTest {
        let language = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
        do {
            return .working(try await AIProviderClient().test(provider, key: key, language: language))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// `✓ Working · 0.8 s`, a spinner, or the provider's own words in red.
struct MacAIProviderTestStatus: View {
    let state: MacAIProviderTest

    var body: some View {
        switch state {
        case .running:
            ProgressView().controlSize(.small)
                .accessibilityLabel(String(localized: "Testing", comment: "Mac Settings › AI: a test is running"))
        case .working(let seconds):
            Label(String(localized: "Working · \(seconds.formatted(.number.precision(.fractionLength(1)))) s",
                         comment: "AI provider form: test passed, with the time it took"),
                  systemImage: "checkmark")
                .foregroundStyle(MacTheme.greenText)
                .accessibilityIdentifier("ai-test-working")
        case .failed(let message):
            Text(message).foregroundStyle(MacTheme.redText)
                .help(message)
                .textSelection(.enabled)
                .accessibilityIdentifier("ai-test-failed")
        }
    }
}
