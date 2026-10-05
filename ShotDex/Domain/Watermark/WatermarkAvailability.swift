import CoreGraphics
import Foundation
import ShotDexKit

/// Whether a saved preset can be stamped today (FS-05.04 §5).
enum WatermarkAvailability: Equatable, Sendable {
    case available
    /// A logo's file is gone from the app's folder: the stamp would come out
    /// without it, so the preset cannot be chosen.
    case missingFile
    /// A typeface is gone from this device: the caption falls back within its
    /// family, as in the editor (FS-05.02 §5), and the export still runs.
    case fontUnavailable

    var isSelectable: Bool { self != .missingFile }

    /// - `imageExists`: whether a logo's file is still on disk.
    /// - `fontResolves`: whether a caption's typeface is found as saved.
    static func of(
        _ preset: SignaturePreset,
        imageExists: (UUID) -> Bool,
        fontResolves: (PhotoOverlay) -> Bool = WatermarkAvailability.fontResolves
    ) -> WatermarkAvailability {
        let visible = preset.layers.filter(\.isVisible)
        if visible.contains(where: { $0.kind == .image && !($0.imageID.map(imageExists) ?? false) }) {
            return .missingFile
        }
        if visible.contains(where: { $0.kind == .text && !$0.fontPostScriptName.isEmpty && !fontResolves($0) }) {
            return .fontUnavailable
        }
        return .available
    }

    /// The renderer's own lookup: the face named in the layer, or a fallback.
    static func fontResolves(_ layer: PhotoOverlay) -> Bool {
        !TextOverlayLayout.resolvedFont(for: layer, pointSize: 12).didSubstitute
    }
}
