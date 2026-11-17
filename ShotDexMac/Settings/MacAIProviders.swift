import Foundation
import Observation

/// The AI providers and the AI Search choice on the Mac (FS-08.07, FS-18.04
/// §3c): the rows and their keys read once off the main actor and kept here,
/// so Settings › AI draws and the search field asks its model without a
/// database or Keychain read on a click.
@MainActor
@Observable
final class MacAIProviders {
    private(set) var providers: [AIProvider] = []
    /// The last four characters of each saved key (`Key ends in 7Qx2`).
    private(set) var keySuffixes: [String: String] = [:]
    /// The AI Search row; set through `choose`.
    private(set) var stored: String?
    private(set) var hasLoaded = false

    @ObservationIgnored let store: AIProviderStore
    @ObservationIgnored private let defaults: UserDefaults
    /// The keys, for the search model; never drawn.
    @ObservationIgnored private var keys: [String: String] = [:]
    /// The newest `reload`: an older read that lands after a save is dropped.
    @ObservationIgnored private var generation = 0
    /// One Apple Intelligence session for the app's life, made only on a Mac that has it.
    @ObservationIgnored private lazy var appleSearch: (any SearchModel)? = {
        if #available(macOS 26.0, *), AISearchTranslator.isAvailable() {
            return AppleIntelligenceSearchModel(translator: AISearchTranslator())
        }
        return nil
    }()

    init(store: AIProviderStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        stored = defaults.string(forKey: SettingsKeys.aiSearch)
    }

    var onDevice: AIChoice.OnDevice { OnDeviceAI.choices }

    var choice: AIChoice {
        AIChoice.search(stored: stored, providers: providers, onDevice: onDevice)
    }

    var options: [AIChoice] {
        AIChoice.searchOptions(providers: providers, onDevice: onDevice)
    }

    func choose(_ choice: AIChoice) {
        stored = choice.stored
        defaults.set(choice.stored, forKey: SettingsKeys.aiSearch)
    }

    func title(_ choice: AIChoice) -> String {
        AIChoiceTitle.title(choice, providers: providers)
    }

    /// The model the search field asks on Return (FS-08.07 §5); nil for Off.
    func searchModel() -> (any SearchModel)? {
        // Before the rows are read the stored home server is not among the
        // options yet; asking nobody beats asking the wrong model.
        guard hasLoaded else { return nil }
        return SearchModelFactory.make(choice: choice, providers: providers, key: { [keys] in keys[$0] }) { appleSearch }
    }

    /// Rows and keys, read off the main actor.
    func reload() async {
        generation += 1
        let mine = generation
        let store = store
        let (rows, keys) = await Task.detached(priority: .userInitiated) { () -> ([AIProvider], [String: String]) in
            let rows = (try? store.providers()) ?? []
            var keys: [String: String] = [:]
            for row in rows { if let key = store.key(for: row.id), !key.isEmpty { keys[row.id] = key } }
            return (rows, keys)
        }.value
        guard mine == generation else { return }
        providers = rows
        self.keys = keys
        // A key this short would be shown whole.
        keySuffixes = keys.filter { $0.value.count >= 8 }.mapValues { String($0.suffix(4)) }
        hasLoaded = true
    }

    /// The saved key, for Test and the model list; nil when there is none.
    func key(for id: String) -> String? { keys[id] }

    /// Saves the row and, when given, the key (nil keeps the saved one).
    func save(_ provider: AIProvider, key: String?) async throws {
        let store = store
        do {
            try await Task.detached(priority: .userInitiated) { try store.save(provider, key: key) }.value
        } catch {
            // The row may be on disk even when its key was not.
            await reload()
            throw error
        }
        await reload()
    }

    /// Removes the row and its key; the AI Search row goes back to its
    /// default if it named this provider (AC-5).
    func delete(_ provider: AIProvider) async throws {
        let store = store, id = provider.id
        do {
            try await Task.detached(priority: .userInitiated) { try store.delete(id: id) }.value
        } catch {
            await reload()
            throw error
        }
        if stored == AIChoice.provider(id).stored {
            stored = nil
            defaults.removeObject(forKey: SettingsKeys.aiSearch)
        }
        await reload()
    }

    /// `qwen3:14b`'s neighbour column: `192.168.1.10:11434`, or `Key ends in 7Qx2`
    /// for a cloud row an old database still holds.
    func addressOrKey(_ provider: AIProvider) -> String {
        if provider.kind == .homeServer || provider.kind == .openAICompatible {
            guard let url = URL(string: provider.address), let host = url.host else { return provider.address }
            return [host, url.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
        }
        guard let suffix = keySuffixes[provider.id] else { return "" }
        return String(localized: "Key ends in \(suffix)", comment: "Settings › AI: the last four characters of a saved key")
    }
}
