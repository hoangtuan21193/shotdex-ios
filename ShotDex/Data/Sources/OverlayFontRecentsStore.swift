import Foundation

/// The typefaces most recently used on a text layer.
///
/// Same shape as `CompressionPresetStore`. It exists because the font picker lists
/// every family installed on the device: finding the same face again for the next
/// photo is the slow part of the job, not choosing it the first time.
@MainActor
@Observable
final class OverlayFontRecentsStore {
    private(set) var recents: [OverlayFontChoice] = []

    /// One row of chips at the top of the picker, and no more — a long recents list
    /// is just a second font list to search.
    private static let capacity = 6

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: SettingsKeys.overlayRecentFonts),
              let decoded = try? JSONDecoder().decode([OverlayFontChoice].self, from: data)
        else {
            recents = []
            return
        }
        recents = decoded
    }

    /// Most recent first, deduplicated by face.
    func remember(_ choice: OverlayFontChoice) {
        guard !choice.postScriptName.isEmpty else { return }
        recents.removeAll { $0.postScriptName == choice.postScriptName }
        recents.insert(choice, at: 0)
        if recents.count > Self.capacity {
            recents.removeLast(recents.count - Self.capacity)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        defaults.set(data, forKey: SettingsKeys.overlayRecentFonts)
    }
}
