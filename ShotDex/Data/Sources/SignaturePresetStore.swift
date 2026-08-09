import Foundation

/// Saved overlay layer sets, reusable across photos — the Lightroom signature.
///
/// `UserDefaults` JSON rather than a GRDB table, following
/// `CompressionPresetStore`: this is a handful of small records the user manages by
/// hand, never something queried, aggregated or sorted in SQL. The images the
/// layers reference are files, and `OverlayImageStore` owns them.
@MainActor
@Observable
final class SignaturePresetStore {
    private(set) var presets: [SignaturePreset] = []

    private let defaults: UserDefaults
    private let images: OverlayImageStore

    init(defaults: UserDefaults = .standard, images: OverlayImageStore = OverlayImageStore()) {
        self.defaults = defaults
        self.images = images
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: SettingsKeys.overlaySignatures),
              let decoded = try? JSONDecoder().decode([SignaturePreset].self, from: data)
        else {
            presets = []
            return
        }
        presets = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func upsert(_ preset: SignaturePreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.insert(preset, at: 0)
        }
        persist()
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == id })
        else { return }
        presets[index].name = trimmed
        persist()
    }

    /// Deleting a signature also deletes the images only it used.
    ///
    /// Only those: an image can be referenced by another preset, and — the reason
    /// this is a check rather than a sweep — by a recipe already written into a
    /// photo's adjustment data, which this store cannot see. Files kept in error
    /// cost kilobytes; files deleted in error cost the watermark on a saved photo.
    func delete(id: UUID) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let removed = presets.remove(at: index)
        persist()
        let stillReferenced = Set(
            presets.flatMap(\.layers).compactMap(\.imageID)
        )
        for imageID in Set(removed.layers.compactMap(\.imageID))
        where !stillReferenced.contains(imageID) {
            images.remove(id: imageID)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: SettingsKeys.overlaySignatures)
    }
}
