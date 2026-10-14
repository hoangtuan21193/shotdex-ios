import Foundation

/// Who can translate a subtitle and what each means for the user's text
/// (FS-23.04 §1): the Using list, its default, and the line that says where
/// the words go.
struct TranslationService: Sendable {
    let providers: AIProviderStore
    var defaults: UserDefaults = .standard
    var onDevice: AIChoice.OnDevice = OnDeviceAI.choices

    static let lastUsingKey = "ai.lastTranslationUsing"

    private var installed: [AIProvider] { (try? providers.providers()) ?? [] }

    /// On the device first, then home servers, then cloud services.
    func usingOptions() -> [AIChoice] {
        let all = installed
        var options: [AIChoice] = []
        if onDevice.appleTranslation { options.append(.appleTranslation) }
        if onDevice.appleIntelligence { options.append(.appleIntelligence) }
        options += all.filter { $0.kind == .homeServer }.map { .provider($0.id) }
        options += all.filter { $0.kind != .homeServer }.map { .provider($0.id) }
        return options
    }

    /// The one used last time, else Settings › AI's choice, else the first.
    func defaultUsing() -> AIChoice? {
        let options = usingOptions()
        if let last = defaults.string(forKey: Self.lastUsingKey).flatMap(AIChoice.init(stored:)), options.contains(last) { return last }
        let chosen = AIChoice.translation(stored: defaults.string(forKey: SettingsKeys.aiSubtitleTranslation), providers: installed, onDevice: onDevice)
        if chosen != .askEachTime, options.contains(chosen) { return chosen }
        return options.first
    }

    func rememberUsing(_ choice: AIChoice) {
        defaults.set(choice.stored, forKey: Self.lastUsingKey)
    }

    func provider(_ choice: AIChoice) -> AIProvider? {
        guard case .provider(let id) = choice else { return nil }
        return try? providers.provider(id: id)
    }

    /// A row's name: `Claude`, `Mac Studio`, `Apple Translation`.
    func title(of choice: AIChoice) -> String {
        switch choice {
        case .appleTranslation: String(localized: "Apple Translation", comment: "Built-in translation")
        case .appleIntelligence: String(localized: "Apple Intelligence", comment: "Built-in AI")
        case .provider: provider(choice)?.name ?? ""
        case .askEachTime, .off: ""
        }
    }

    /// For `Translated (Claude)`; nil once the provider is gone.
    func name(of stored: String) -> String? {
        guard let choice = AIChoice(stored: stored) else { return nil }
        let title = title(of: choice)
        return title.isEmpty ? nil : title
    }

    /// Who the words go to, for the note and the errors: the company for a
    /// cloud service, the computer's name for a home server.
    func serviceName(of choice: AIChoice) -> String {
        guard let provider = provider(choice) else { return title(of: choice) }
        switch provider.kind {
        case .claude: return "Anthropic"
        case .chatGPT: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .grok: return "xAI"
        case .gemini: return "Google"
        case .homeServer, .openAICompatible: return provider.name
        }
    }

    /// FS-23.04 §1: where the text goes.
    func note(for choice: AIChoice, lines: Int) -> String {
        switch provider(choice)?.kind {
        case .homeServer?:
            return String(localized: "Sent to \(serviceName(of: choice)) on your network. Timing stays as it is.", comment: "Translate note: a home server")
        case .some:
            return String(localized: "\(lines.formatted()) lines of subtitle text will be sent to \(serviceName(of: choice)) with your API key. Timing stays as it is.", comment: "Translate note: a cloud service, e.g. 1,380 lines of subtitle text will be sent to Anthropic…")
        case nil:
            return String(localized: "Stays on this device. Timing stays as it is.", comment: "Translate note: on-device translation")
        }
    }

    /// The engine for a model choice; Apple Translation runs from the view
    /// that holds its session.
    func engine(for choice: AIChoice) -> (any SubtitleTranslationEngine)? {
        switch choice {
        case .provider:
            guard let provider = provider(choice) else { return nil }
            return ModelTranslationEngine(provider: provider, key: providers.key(for: provider.id))
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) { return AppleIntelligenceTranslationEngine() }
            #endif
            return nil
        case .appleTranslation, .askEachTime, .off:
            return nil
        }
    }
}
