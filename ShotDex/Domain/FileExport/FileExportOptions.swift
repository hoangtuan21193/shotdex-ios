import CoreGraphics
import Foundation
import ShotDexKit

/// What Export… writes (FS-03.07b §3) — Photos' own two words.
enum FileExportMode: String, Codable, CaseIterable, Sendable {
    /// Each photo rendered once at a Resize preset; videos as they are.
    case currentVersion
    /// Every original file of the asset, byte for byte.
    case unmodifiedOriginal
}

/// Which pixels Current Version renders from, for a photo edited in Photos.
enum FileExportVersion: String, Codable, CaseIterable, Sendable {
    /// The version Photos shows — the edit included.
    case edited
    /// The file as shot: the RAW when the decoder reads it, else its JPEG.
    case original
}

/// If a File Exists (FS-03.07b §6).
enum FileExportConflictPolicy: String, Codable, CaseIterable, Sendable {
    case keepBoth
    case replace
    case skip
}

/// Color Space (FS-03.07b §3a): the profile Current Version writes. The
/// four the app's ImageIO writers carry in both JPEG and HEIC, under the Mac
/// popup's names (FS-18 D17).
enum ExportColorSpace: String, Codable, CaseIterable, Sendable {
    /// The photo's own profile, as the renderer keeps it today: Display P3
    /// or Adobe RGB when the file says so, RAW as Display P3, else sRGB.
    case original
    case sRGB
    case displayP3
    case adobeRGB

    /// The profile to convert to; nil keeps the photo's own.
    var cgColorSpace: CGColorSpace? {
        switch self {
        case .original: nil
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)
        case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)
        }
    }
}

/// The choices the sheet remembers for next time (FS-03.07b §3). Metadata and
/// Version are deliberately not here: Metadata always starts at the Settings
/// level (FS-08.06 §4), Version always at Edited.
struct FileExportSettings: Codable, Equatable, Sendable {
    var dateFolders = false
    var mode: FileExportMode = .currentVersion
    /// The Resize preset, by id; one that is gone falls back to Original.
    var presetId: UUID = ResizePreset.original.id
    var format: PhotoOutputFormat = .preserve
    var colorSpace: ExportColorSpace = .original
    /// 0.1…1, as Resize.
    var quality = FileExportQuality.defaultValue
    /// The file name template, in tokens (FS-03.07b §5).
    var nameTemplate = FileNameTemplate.originalName.pattern
    /// What was last typed under Custom, kept while a built-in is in use.
    var customNameTemplate = FileNameTemplate.dateCameraNumber.pattern
    var conflictPolicy: FileExportConflictPolicy = .keepBoth
    var includesLivePhotoVideo = true

    init() {}

    /// Lossy: a field this build no longer reads, or one it cannot decode,
    /// falls back to its default instead of losing every other choice.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FileExportSettings()
        dateFolders = (try? container.decode(Bool.self, forKey: .dateFolders)) ?? defaults.dateFolders
        mode = (try? container.decode(FileExportMode.self, forKey: .mode)) ?? defaults.mode
        presetId = (try? container.decode(UUID.self, forKey: .presetId)) ?? defaults.presetId
        format = (try? container.decode(PhotoOutputFormat.self, forKey: .format)) ?? defaults.format
        colorSpace = (try? container.decode(ExportColorSpace.self, forKey: .colorSpace)) ?? defaults.colorSpace
        quality = FileExportQuality.clamped((try? container.decode(Double.self, forKey: .quality)) ?? defaults.quality)
        nameTemplate = (try? container.decode(String.self, forKey: .nameTemplate)) ?? defaults.nameTemplate
        customNameTemplate = (try? container.decode(String.self, forKey: .customNameTemplate)) ?? defaults.customNameTemplate
        conflictPolicy = (try? container.decode(FileExportConflictPolicy.self, forKey: .conflictPolicy)) ?? defaults.conflictPolicy
        includesLivePhotoVideo = (try? container.decode(Bool.self, forKey: .includesLivePhotoVideo)) ?? defaults.includesLivePhotoVideo
    }
}

/// The Quality row (FS-03.07b §3a): Resize's slider and Settings → Resize
/// Presets' — 10…100% in steps of 1%, 80% to start.
enum FileExportQuality {
    static let range: ClosedRange<Double> = 0.1...1
    static let step = 0.01
    static let defaultValue = 0.8

    /// A quality inside the range, on a step of 1% (`0.85` stays `0.85`).
    static func clamped(_ quality: Double) -> Double {
        guard quality.isFinite else { return defaultValue }
        return min(range.upperBound, max(range.lowerBound, (quality * 100).rounded() / 100))
    }
}
