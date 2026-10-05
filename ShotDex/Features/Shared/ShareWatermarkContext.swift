import Foundation
import Photos
import ShotDexKit

/// Where every way into Share learns its watermark (FS-05.04 §4): the
/// preset Settings → Watermark When Sharing names, placed as the export forms
/// remember, with each photo's tokens from the index and the photos whose
/// edit already carries it. One per app, owned by `AppDependencies`, reached
/// through `OriginalDownloadModel` — the Share modal every share site
/// already passes — and by drags.
@MainActor
final class ShareWatermarkContext {
    let settings: WatermarkSettingsStore
    let presets: SignaturePresetStore
    private let libraryQueries: LibraryQueries?
    private let editing: PhotoEditingService?
    private let imageExists: (UUID) -> Bool

    init(
        settings: WatermarkSettingsStore,
        presets: SignaturePresetStore,
        libraryQueries: LibraryQueries?,
        editing: PhotoEditingService?,
        imageExists: @escaping (UUID) -> Bool
    ) {
        self.settings = settings
        self.presets = presets
        self.libraryQueries = libraryQueries
        self.editing = editing
        self.imageExists = imageExists
    }

    var hasPresets: Bool { !presets.presets.isEmpty }

    private func usable(_ preset: SignaturePreset) -> Bool {
        WatermarkAvailability.of(preset, imageExists: imageExists).isSelectable
    }

    /// Watermark When Sharing's preset, if it still exists and can be stamped.
    var settingsPreset: SignaturePreset? {
        guard let id = settings.sharingPresetID,
              let preset = presets.presets.first(where: { $0.id == id }), usable(preset)
        else { return nil }
        return preset
    }

    /// The preset one share stamps. `override` is the share sheet's one-off
    /// row: true — Share With Watermark: Settings' preset, else the one last
    /// used on a form, else the newest (FS-05.04 §4); false — none; nil —
    /// Settings.
    func preset(override: Bool?) -> SignaturePreset? {
        switch override {
        case false?: return nil
        case nil: return settingsPreset
        case true?:
            return settingsPreset
                ?? settings.formPreset(in: presets.presets, isSelectable: usable)
                ?? presets.presets.first(where: usable)
        }
    }

    /// What a share of `sources` stamps, decided before the sheet opens.
    func watermark(for sources: [ShareSource], override: Bool? = nil) async -> ShareWatermark? {
        guard let preset = preset(override: override) else { return nil }
        return await watermark(preset: preset, ids: sources.filter { $0.kind != .video }.map(\.id))
    }

    /// What a form stamps on `ids` — the remembered configuration, on or
    /// off (Export to Files, FS-05.04 §4).
    func formWatermark(ids: [String]) async -> ShareWatermark? {
        guard settings.settings.isEnabled,
              let preset = settings.formPreset(in: presets.presets, isSelectable: usable)
        else { return nil }
        return await watermark(preset: preset, ids: ids)
    }

    private func watermark(preset: SignaturePreset, ids: [String]) async -> ShareWatermark {
        var watermark = ShareWatermark(template: WatermarkStamp(preset: preset, placement: settings.settings.placement))
        if let libraryQueries, let rows = try? libraryQueries.metadata(assetIds: ids) {
            for (id, row) in rows { watermark.tokens[id] = OverlayTokenValues(metadata: row) }
        }
        if let editing {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var list: [PHAsset] = []
            assets.enumerateObjects { asset, _, _ in list.append(asset) }
            for asset in list {
                let saved = await editing.savedRecipe(of: asset, allowNetwork: false)
                if WatermarkPlan.alreadyStamped(savedLayers: saved?.overlays, presetID: preset.id) {
                    watermark.alreadyStamped.insert(asset.localIdentifier)
                }
            }
        }
        return watermark
    }
}
