import Foundation

/// What a library thumbnail says over its picture (Mac Settings › General ›
/// Thumbnails, FS-18.04 §3 AC-67, AC-68): the file-type badge, which fields
/// the info line carries, and whether focal lengths are full-frame
/// equivalents. The fields the iOS grid also has use its keys and defaults;
/// File Name and Capture Time are the Mac's own so far.
struct ThumbnailInfoFields: Equatable {
    enum Field: String, CaseIterable, Identifiable {
        case fileName, captureTime, iso, aperture, shutterSpeed, focalLength, megapixels, fileSize

        var id: Self { self }

        var key: String {
            switch self {
            case .fileName: "display.showFileName"
            case .captureTime: "display.showCaptureTime"
            case .iso: "display.showISO"
            case .aperture: "display.showAperture"
            case .shutterSpeed: "display.showShutter"
            case .focalLength: "display.showFocal"
            case .megapixels: "display.showMegapixels"
            case .fileSize: "display.showFileSize"
            }
        }

        /// The iOS grid's defaults; File Name and Capture Time are new and off.
        var isShownByDefault: Bool { self == .iso || self == .aperture || self == .focalLength }

        var title: String {
            switch self {
            case .fileName: String(localized: "File Name", comment: "Settings › Info on Thumbnails field")
            case .captureTime: String(localized: "Capture Time", comment: "Settings › Info on Thumbnails field")
            case .iso: String(localized: "ISO", comment: "Settings › Info on Thumbnails field")
            case .aperture: String(localized: "Aperture", comment: "Settings › Info on Thumbnails field")
            case .shutterSpeed: String(localized: "Shutter Speed", comment: "Settings › Info on Thumbnails field")
            case .focalLength: String(localized: "Focal Length", comment: "Settings › Info on Thumbnails field")
            case .megapixels: String(localized: "Megapixels", comment: "Settings › Info on Thumbnails field")
            case .fileSize: String(localized: "File Size", comment: "Settings › Info on Thumbnails field")
            }
        }
    }

    static let fileTypeBadgeKey = SettingsKeys.showFileTypeBadge
    static let equivalentFocalLengthKey = "display.focalStyleEquivalent"

    var shown: Set<Field>
    var showsFileTypeBadge: Bool
    var showsEquivalentFocalLength: Bool

    static func load(from defaults: UserDefaults = .standard) -> ThumbnailInfoFields {
        // `bool(forKey:)`, not `as? Bool`: a value from the arguments domain is a string ("YES").
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        return ThumbnailInfoFields(
            shown: Set(Field.allCases.filter { flag($0.key, $0.isShownByDefault) }),
            showsFileTypeBadge: flag(fileTypeBadgeKey, true),
            showsEquivalentFocalLength: flag(equivalentFocalLengthKey, false))
    }

    /// The exposure line, in the iOS grid's order: `ISO 400 · 35mm · f/1.8`.
    /// Only real values — a field the photo lacks is left out, not shown as `--`.
    func exposureFragments(for item: some PhotoGridDisplayable) -> [String] {
        let focal = showsEquivalentFocalLength ? (item.equivalentFocalLength ?? item.focalLength) : item.focalLength
        return [
            shown.contains(.iso) ? item.iso.flatMap(MetadataFormatter.iso) : nil,
            shown.contains(.focalLength) ? focal.flatMap(MetadataFormatter.focalLength) : nil,
            shown.contains(.aperture) ? item.aperture.flatMap(MetadataFormatter.aperture) : nil,
            shown.contains(.shutterSpeed) ? item.shutterSpeedDisplay : nil,
            shown.contains(.megapixels) ? item.megapixels.flatMap(MetadataFormatter.megapixels) : nil,
            shown.contains(.fileSize) ? item.fileSize.flatMap(MetadataFormatter.fileSize) : nil,
        ].compactMap { $0 }
    }

    /// The line above it: `DSC04218.ARW · 6:42 PM` — the time in the user's
    /// locale and clock; the day is the section's.
    func caption(for item: some PhotoGridDisplayable) -> String? {
        let parts = [
            shown.contains(.fileName) ? item.originalFilename : nil,
            shown.contains(.captureTime) ? item.creationDateValue?.formatted(date: .omitted, time: .shortened) : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Width a tile gives its exposure line: 8pt in from each edge, and clear
    /// of the server glyph (`glyphWidth`, 4pt gap) when it shows.
    static func room(side: Double, glyphWidth: Double?) -> Double {
        side - 16 - (glyphWidth.map { $0 + 4 } ?? 0)
    }

    /// Trailing fields drop off whole until the line fits, so a tile shows
    /// `ISO 400 · 35mm` rather than `ISO 400 · 35m…` — a cut value reads as a
    /// wrong one. The first field always stays.
    static func fitted(_ fragments: [String], width: (String) -> Double, within limit: Double) -> String {
        var kept = fragments
        while kept.count > 1, width(kept.joined(separator: " · ")) > limit { kept.removeLast() }
        return kept.joined(separator: " · ")
    }
}
