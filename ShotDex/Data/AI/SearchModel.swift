import Foundation

/// A model AI Search can ask (FS-08.07 §5): Apple Intelligence on the
/// device, or a home server. There is no cloud implementation, by design —
/// the prompt carries the library's place names.
protocol SearchModel: Sendable {
    /// After this the parser's answer is used, with no error shown.
    var timeout: Duration { get }
    func prewarm(vocabulary: FilterSuggestionCatalog) async
    func translate(_ query: String, vocabulary: FilterSuggestionCatalog) async -> [SmartAlbumRule]?
}

extension SearchModel {
    func prewarm(vocabulary: FilterSuggestionCatalog) async {}
}

@available(iOS 26.0, macOS 26.0, *)
struct AppleIntelligenceSearchModel: SearchModel {
    let translator: AISearchTranslator
    var timeout: Duration { .seconds(2) }

    func prewarm(vocabulary: FilterSuggestionCatalog) async {
        await translator.prewarm(vocabulary: vocabulary)
    }

    func translate(_ query: String, vocabulary: FilterSuggestionCatalog) async -> [SmartAlbumRule]? {
        await translator.translate(query, vocabulary: vocabulary)
    }
}

/// Ollama or LM Studio at home: the same instructions, answered as JSON.
struct HomeServerSearchModel: SearchModel {
    let provider: AIProvider
    let key: String?
    var client = AIProviderClient()
    var timeout: Duration = .seconds(8)

    func translate(_ query: String, vocabulary: FilterSuggestionCatalog) async -> [SmartAlbumRule]? {
        guard provider.kind.servesAISearch else { return nil }
        let system = SearchModelPrompt.instructions(vocabulary: vocabulary) + "\n\n" + SearchModelPrompt.jsonShape
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        guard let answer = try? await client.complete(provider, key: key, system: system, prompt: SearchModelPrompt.prompt(for: query), timeout: seconds),
              let conditions = SearchModelPrompt.conditions(fromJSON: answer) else { return nil }
        let rules = SearchIntentMapper.rules(from: conditions)
        return rules.isEmpty ? nil : rules
    }
}

enum SearchModelFactory {
    /// The model for the AI Search row; nil for Off, for anything that is
    /// not on the device or at home, and when the device cannot.
    @MainActor
    static func make(choice: AIChoice, providers: [AIProvider], key: (String) -> String?, appleIntelligence: () -> (any SearchModel)?) -> (any SearchModel)? {
        switch choice {
        case .appleIntelligence:
            return appleIntelligence()
        case .provider(let id):
            guard let provider = providers.first(where: { $0.id == id }), provider.kind.servesAISearch else { return nil }
            return HomeServerSearchModel(provider: provider, key: key(provider.id))
        case .off:
            return nil
        }
    }
}
