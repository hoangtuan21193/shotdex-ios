import Foundation

@MainActor
@Observable
final class CompressionPresetStore {
    private(set) var customPresets: [ResizePreset] = []

    var allPresets: [ResizePreset] {
        ResizePreset.builtIns + customPresets
    }

    init() {
        reload()
    }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.compressionPresets),
              let decoded = try? JSONDecoder().decode([ResizePreset].self, from: data)
        else {
            customPresets = []
            return
        }
        customPresets = decoded.filter { !$0.isBuiltIn }
    }

    func upsert(_ preset: ResizePreset) {
        guard !preset.isBuiltIn else { return }
        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index] = preset
        } else {
            customPresets.append(preset)
        }
        persist()
    }

    func delete(id: UUID) {
        customPresets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(customPresets) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKeys.compressionPresets)
    }
}
