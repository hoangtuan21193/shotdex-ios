import Foundation
import ShotDexKit

/// The watermark choice the export forms remember (FS-05.04 §5): which
/// preset, where it goes, and whether it is on. One configuration, shared by
/// Resize, Export to Files and the server export sheet.
struct WatermarkSettings: Codable, Equatable {
    /// The preset last chosen on a form; nil before any.
    var presetID: UUID?
    var isEnabled = false
    var placement = WatermarkPlacement()

    init(presetID: UUID? = nil, isEnabled: Bool = false, placement: WatermarkPlacement = WatermarkPlacement()) {
        self.presetID = presetID
        self.isEnabled = isEnabled
        self.placement = placement
    }

    private enum CodingKeys: String, CodingKey {
        case presetID, isEnabled, placement
    }

    /// Lenient: a field this build cannot read falls back alone.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presetID = (try? container.decodeIfPresent(UUID.self, forKey: .presetID)) ?? nil
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        placement = (try? container.decodeIfPresent(WatermarkPlacement.self, forKey: .placement)) ?? WatermarkPlacement()
    }
}

/// Where the watermark choices live: the app's settings, beside the presets —
/// never the database (FS-05.04 §6). `UserDefaults` JSON, like
/// `CompressionPresetStore`.
@MainActor
@Observable
final class WatermarkSettingsStore {
    /// The forms' configuration.
    private(set) var settings: WatermarkSettings
    /// Settings → Watermark When Sharing: a preset id, or nil for Off.
    private(set) var sharingPresetID: UUID?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: SettingsKeys.watermarkExport),
           let decoded = try? JSONDecoder().decode(WatermarkSettings.self, from: data) {
            settings = decoded
        } else {
            settings = WatermarkSettings()
        }
        sharingPresetID = defaults.string(forKey: SettingsKeys.watermarkSharing).flatMap(UUID.init(uuidString:))
    }

    func update(_ change: (inout WatermarkSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        guard let data = try? JSONEncoder().encode(copy) else { return }
        defaults.set(data, forKey: SettingsKeys.watermarkExport)
    }

    func setSharingPreset(_ id: UUID?) {
        sharingPresetID = id
        if let id {
            defaults.set(id.uuidString, forKey: SettingsKeys.watermarkSharing)
        } else {
            defaults.removeObject(forKey: SettingsKeys.watermarkSharing)
        }
    }

    /// The preset the forms point at, if it still exists and can be stamped.
    /// A preset deleted since, or whose logo file is gone, is no preset — the
    /// row reads Off, never a silent substitute (FS-05.04 §5).
    func formPreset(
        in presets: [SignaturePreset],
        isSelectable: (SignaturePreset) -> Bool = { _ in true }
    ) -> SignaturePreset? {
        guard let id = settings.presetID, let preset = presets.first(where: { $0.id == id }),
              isSelectable(preset)
        else { return nil }
        return preset
    }

    /// What a form stamps, before tokens: nil when the watermark is off or its
    /// preset is gone or unusable.
    func formStamp(
        in presets: [SignaturePreset],
        isSelectable: (SignaturePreset) -> Bool = { _ in true }
    ) -> WatermarkStamp? {
        guard settings.isEnabled, let preset = formPreset(in: presets, isSelectable: isSelectable) else { return nil }
        return WatermarkStamp(preset: preset, placement: settings.placement)
    }
}
