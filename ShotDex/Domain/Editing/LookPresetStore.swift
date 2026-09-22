import Foundation
import Observation
import ShotDexKit

/// One saved look: a named edit the user can put on any photo.
///
/// Stores a **look-only** recipe — tone, colour, curve, film look — never the
/// crop, masks, markup or drawing. Same cut `EditClipboard` makes and for the
/// same reason it documents: a preset carrying one photo's face mask and 4:5
/// crop would wreck every photo it touched.
struct LookPreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var recipe: PhotoEditRecipe
    var createdAt: Date

    init(id: UUID = UUID(), name: String, recipe: PhotoEditRecipe, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.recipe = EditorSyncScope.look.apply(recipe, onto: .identity)
        self.createdAt = createdAt
    }
}

/// The user's own looks.
///
/// The 48 film looks are a fixed enum; this is the shelf beside them. Without
/// it, Sync is the only way to reuse an edit and the edit dies with the session
/// — which is why "save this as a preset" is the feature photographers ask for
/// first and the one that makes a shoot's second day faster than its first.
///
/// Modelled on `SignaturePresetStore`: `@Observable`, JSON in `UserDefaults`,
/// held in `AppDependencies`. Looks are small — a few hundred bytes of numbers
/// — so there is no file store here the way signatures need one for images.
@MainActor
@Observable
final class LookPresetStore {
    private(set) var presets: [LookPreset] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: SettingsKeys.lookPresets),
              // One preset this build cannot read is dropped on its own; it
              // used to empty the whole list.
              let decoded = try? JSONDecoder().decode(LossyArray<LookPreset>.self, from: data).elements
        else {
            presets = []
            return
        }
        presets = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves a look under `name`. A name already in use is overwritten rather
    /// than duplicated: "Golden Hour" twice in a strip is two tiles the user
    /// cannot tell apart.
    @discardableResult
    func save(_ recipe: PhotoEditRecipe, name: String) -> LookPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let look = EditorSyncScope.look.apply(recipe, onto: .identity)
        // An identity look is a preset that does nothing; offering it would be
        // a tile that appears to fail.
        guard !look.isIdentity else { return nil }

        var preset = LookPreset(name: trimmed, recipe: look)
        if let existing = presets.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // Keeps its identity, takes a new timestamp: re-saving a look *is*
            // the newest thing the user did to their looks, and the old date
            // made the strip re-order itself on the next launch for no action
            // the user took.
            preset.id = existing.id
            presets.removeAll { $0.id == existing.id }
        }
        presets.insert(preset, at: 0)
        persist()
        return preset
    }

    func rename(_ preset: LookPreset, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }
        presets[index].name = trimmed
        persist()
    }

    func delete(_ preset: LookPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    /// What a new preset is called before the user types anything. Numbered so
    /// two saves in a row do not collide in the overwrite rule above.
    func suggestedName() -> String {
        var index = presets.count + 1
        var candidate = "Look \(index)"
        while presets.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            index += 1
            candidate = "Look \(index)"
        }
        return candidate
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(presets), forKey: SettingsKeys.lookPresets)
    }
}
