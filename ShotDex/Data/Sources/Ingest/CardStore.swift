import Foundation
import Observation

/// A memory card ShotDex has been shown once (FS-20 §4, AC-20): its folder
/// in Files, kept as a bookmark, known again by its volume when it is
/// plugged back in — no picker the second time.
struct RememberedCard: Codable, Equatable, Identifiable, Sendable {
    /// The volume UUID, or the folder's path when the volume has none.
    var id: String
    var name: String
    var bookmark: Data
}

/// The cards ShotDex remembers and which are plugged in right now (FS-20
/// §4, plan K4): while the app is active it looks every second, so a card's
/// row shows up in Sources within 2 s, without opening anything (AC-19).
@MainActor
@Observable
final class CardStore {
    private(set) var remembered: [RememberedCard] = []
    /// Plugged in and readable, by card id.
    private(set) var connected: [String: URL] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watch: Task<Void, Never>?

    static let limit = 5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: SettingsKeys.ingestCards),
           let decoded = try? JSONDecoder().decode([RememberedCard].self, from: data) {
            remembered = decoded
        }
    }

    var connectedCards: [RememberedCard] { remembered.filter { connected[$0.id] != nil } }

    /// Choose Card…: the folder picked in Files — the card's root.
    @discardableResult
    func remember(_ url: URL) throws -> RememberedCard {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        let card = try Self.card(for: url)
        remembered.removeAll { $0.id == card.id }
        remembered.insert(card, at: 0)
        if remembered.count > Self.limit { remembered.removeLast(remembered.count - Self.limit) }
        persist()
        refresh()
        return card
    }

    static func card(for url: URL) throws -> RememberedCard {
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeIsInternalKey])
        // A card is a volume of its own; a test card is a folder on this device.
        let isVolume = values?.volumeIsInternal == false
        let id = isVolume ? (values?.volumeUUIDString ?? url.standardizedFileURL.path) : url.standardizedFileURL.path
        let name = isVolume ? (values?.volumeName ?? url.lastPathComponent) : url.lastPathComponent
        return RememberedCard(id: id, name: name, bookmark: try url.bookmarkData())
    }

    /// Which remembered cards open now.
    func refresh() {
        var found: [String: URL] = [:]
        var seen: Set<String> = []
        var duplicates: [String] = []
        for card in remembered {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: card.bookmark, bookmarkDataIsStale: &isStale) else { continue }
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            guard (try? url.checkResourceIsReachable()) == true else { continue }
            // One folder picked twice (or its app container moved) is one card.
            guard seen.insert(url.standardizedFileURL.path).inserted else {
                duplicates.append(card.id)
                continue
            }
            found[card.id] = url
        }
        if !duplicates.isEmpty {
            remembered.removeAll { duplicates.contains($0.id) }
            persist()
        }
        if found != connected { connected = found }
    }

    func forget(_ card: RememberedCard) {
        remembered.removeAll { $0.id == card.id }
        connected[card.id] = nil
        persist()
    }

    /// Every second while the app is in front (plan K4).
    func startWatching() {
        guard watch == nil else { return }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatching() {
        watch?.cancel()
        watch = nil
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(remembered) else { return }
        defaults.set(data, forKey: SettingsKeys.ingestCards)
    }

    #if DEBUG
    /// `-ShotDexSeedCard EOS_DIGITAL`: remembers Documents/EOS_DIGITAL of
    /// the app's own container as a card — the pick a UI script cannot make
    /// in Files, which runs outside the app.
    static let seedArgument = "-ShotDexSeedCard"

    func seedIfAsked() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: Self.seedArgument), index + 1 < arguments.count,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent(arguments[index + 1], isDirectory: true)
        refresh()
        guard FileManager.default.fileExists(atPath: folder.path),
              !connected.values.contains(where: { $0.standardizedFileURL.path == folder.standardizedFileURL.path }) else { return }
        _ = try? remember(folder)
    }
    #endif
}

/// The card import settings, in the app's settings (FS-20 §9).
enum IngestSettingsStore {
    static func load(_ defaults: UserDefaults = .standard) -> IngestSettings {
        guard let data = defaults.data(forKey: SettingsKeys.ingestSettings),
              let settings = try? JSONDecoder().decode(IngestSettings.self, from: data) else { return IngestSettings() }
        return settings
    }

    static func save(_ settings: IngestSettings, _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: SettingsKeys.ingestSettings)
    }
}
