import Foundation

/// User-saved collage looks (§8), persisted as JSON in `UserDefaults`. Same
/// shape as `CompressionPresetStore` / `OverlayFontRecentsStore`: an observable
/// list the collage screen reads, mutated through save / rename / delete.
///
/// A preset holds the frame and style only — never the photos or the text — so
/// it can be stamped onto any collage of the matching photo count.
@MainActor
@Observable
final class CollagePresetStore {
    private(set) var presets: [CollagePreset] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: SettingsKeys.collagePresets),
              let decoded = try? JSONDecoder().decode([CollagePreset].self, from: data)
        else {
            presets = []
            return
        }
        presets = decoded
    }

    /// Newest first, so a freshly saved preset leads the strip.
    func save(_ preset: CollagePreset) {
        presets.insert(preset, at: 0)
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: SettingsKeys.collagePresets)
    }
}
